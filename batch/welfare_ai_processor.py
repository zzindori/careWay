#!/usr/bin/env python3
"""
CareWay 복지서비스 통합 배치 파이프라인
========================================
Phase 0: 지자체복지서비스 목록 수집 → DB 신규 등록
Phase 1: 복지로 API 상세 조회 → DB 저장 (신청방법, 문의처, 상세내용)
Phase 2: Gemini AI 분류 → DB 저장 (target_age_group, 필터 조건)

앱은 DB만 읽음. API 실시간 호출 없음.

사용법:
  # DB 컬럼 추가 (Supabase SQL Editor에서 먼저 실행)
  ALTER TABLE welfare_services
    ADD COLUMN IF NOT EXISTS target_age_group TEXT DEFAULT 'unknown',
    ADD COLUMN IF NOT EXISTS ai_criteria JSONB,
    ADD COLUMN IF NOT EXISTS filter_confidence FLOAT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS filter_updated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS applmet_list JSONB,
    ADD COLUMN IF NOT EXISTS inq_place TEXT DEFAULT '',
    ADD COLUMN IF NOT EXISTS detail_content TEXT DEFAULT '',
    ADD COLUMN IF NOT EXISTS detail_fetched_at TIMESTAMPTZ;

  # 환경변수
  set GEMINI_API_KEY=AIza...     (Google AI Studio → Get API Key)
  set SUPABASE_SERVICE_KEY=eyJ... (Supabase → Settings → API → service_role)
  set WELFARE_API_KEY=c488...

  # 패키지
  pip install google-generativeai supabase requests

  # 실행 (전체)
  python welfare_ai_processor.py

  # Phase만 선택 실행
  python welfare_ai_processor.py --phase 1   # API 수집만
  python welfare_ai_processor.py --phase 2   # AI 분류만

비용: 무료 (Gemini 1.5 Flash 무료 티어 - 하루 1,500회 요청)
"""

import os
import sys
import json
import time
import re
import hashlib
import requests
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

from google import genai as google_genai
from supabase import create_client

# ── 설정 ──────────────────────────────────────────────────────────────────────

SUPABASE_URL = "https://dnnidnqwkjmbssxixpjg.supabase.co"
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
WELFARE_API_KEY = os.environ.get("WELFARE_API_KEY", "")
LOCAL_WELFARE_API_KEY = os.environ.get("LOCAL_WELFARE_API_KEY", "")
SOCIAL_SERVICE_API_KEY = os.environ.get("SOCIAL_SERVICE_API_KEY", "")

WELFARE_DETAIL_URL = "https://apis.data.go.kr/B554287/NationalWelfareInformationsV001/NationalWelfaredetailedV001"

# 지자체복지서비스 API (한국사회보장정보원, 동일 제공기관 B554287)
LOCAL_WELFARE_LIST_URL = "https://apis.data.go.kr/B554287/LocalGovernmentWelfareInformations/LcgvWelfarelist"
LOCAL_WELFARE_DETAIL_URL = "https://apis.data.go.kr/B554287/LocalGovernmentWelfareInformations/LcgvWelfaredetailed"  # 사용 안 함 (웹 스크래핑으로 대체)
BOKJIRO_WEB_URL = "https://www.bokjiro.go.kr/ssis-tbu/twataa/wlfareInfo/moveTWAT52011M.do"
SOCIAL_SERVICE_PROVIDER_URL = "https://api.socialservice.or.kr:444/api/service/provider/providerList"

MODEL = "gemini-2.0-flash"
API_REQUEST_DELAY = 1.2    # 복지로 API rate limit 방지 (개발계정 100 RPM → 최소 0.6초, 여유분 포함)
WEB_SCRAPE_DELAY = 0.5     # 복지로 웹 스크래핑 딜레이 (API 한도 없음, 서버 부하 방지 목적)
GEMINI_DELAY = 4.5         # Gemini 무료 티어: 15 RPM → 4초 간격
MAX_DETAIL_API_RETRIES = 3
DETAIL_API_RETRY_BASE_DELAY = 1.5
AI_MIN_CONTENT_LENGTH = 40
AI_SKIP_CONFIDENCE_THRESHOLD = 0.85
CHECKPOINT_FILE = os.path.join(os.path.dirname(__file__), ".welfare_batch_checkpoint.json")
_SUB_REGION_COLUMN_AVAILABLE: bool | None = None

SOCIAL_CATEGORY_SERVICE_TYPE = {
    "care": "BA",
    "living": "BC",
    "medical": "BD",
    "housing": "BE",
}

SIDO_REGIONS = [
    "서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종",
    "경기", "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주",
]

# ── 환경변수 체크 ──────────────────────────────────────────────────────────────

# ── 지역명 정규화 (서울특별시 → 서울, 경기도 → 경기 등) ──────────────────────
def normalize_region(r: str) -> str:
    if not r:
        return ""
    if "서울" in r: return "서울"
    if "부산" in r: return "부산"
    if "대구" in r: return "대구"
    if "인천" in r: return "인천"
    if "광주" in r: return "광주"
    if "대전" in r: return "대전"
    if "울산" in r: return "울산"
    if "세종" in r: return "세종"
    if "경기" in r: return "경기"
    if "강원" in r: return "강원"
    if "충북" in r or "충청북" in r: return "충북"
    if "충남" in r or "충청남" in r: return "충남"
    if "전북" in r or "전라북" in r: return "전북"
    if "전남" in r or "전라남" in r: return "전남"
    if "경북" in r or "경상북" in r: return "경북"
    if "경남" in r or "경상남" in r: return "경남"
    if "제주" in r: return "제주"
    return r


def _is_missing_sub_region_column_error(err: Exception) -> bool:
    msg = str(err).lower()
    return "sub_region" in msg and ("column" in msg or "schema cache" in msg)


def _update_welfare_service(supabase, service_id: int, payload: dict):
    """
    `sub_region` 컬럼이 아직 없는 환경에서도 배치가 중단되지 않도록
    1회 자동 폴백(키 제거 후 재시도) 처리.
    """
    global _SUB_REGION_COLUMN_AVAILABLE

    if _SUB_REGION_COLUMN_AVAILABLE is False and "sub_region" in payload:
        payload = {k: v for k, v in payload.items() if k != "sub_region"}

    try:
        supabase.table("welfare_services").update(payload).eq("id", service_id).execute()
        if "sub_region" in payload:
            _SUB_REGION_COLUMN_AVAILABLE = True
        return
    except Exception as e:
        if "sub_region" in payload and _is_missing_sub_region_column_error(e):
            _SUB_REGION_COLUMN_AVAILABLE = False
            fallback = {k: v for k, v in payload.items() if k != "sub_region"}
            supabase.table("welfare_services").update(fallback).eq("id", service_id).execute()
            return
        raise


# ── 환경변수 체크 ──────────────────────────────────────────────────────────────

def validate_env(phase=None):
    missing = []
    if not SUPABASE_SERVICE_KEY:
        missing.append("SUPABASE_SERVICE_KEY")
    if phase in (None, "1", "1_lite"):
        if not WELFARE_API_KEY:
            missing.append("WELFARE_API_KEY")
    if phase in (None, "2", "2r"):
        if not GEMINI_API_KEY:
            missing.append("GEMINI_API_KEY")
    if phase == "providers":
        if not SOCIAL_SERVICE_API_KEY:
            missing.append("SOCIAL_SERVICE_API_KEY")
    if missing:
        print(f"❌ 환경변수 미설정: {', '.join(missing)}")
        sys.exit(1)


def _load_checkpoint() -> dict:
    try:
        if not os.path.exists(CHECKPOINT_FILE):
            return {}
        with open(CHECKPOINT_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_checkpoint(data: dict):
    try:
        with open(CHECKPOINT_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


def _checkpoint_get_start_index(phase_name: str) -> int:
    cp = _load_checkpoint()
    entry = cp.get(phase_name, {})
    if not isinstance(entry, dict):
        return 0
    idx = entry.get("next_index", 0)
    return idx if isinstance(idx, int) and idx >= 0 else 0


def _checkpoint_set_index(phase_name: str, next_index: int):
    cp = _load_checkpoint()
    cp[phase_name] = {
        "next_index": max(0, int(next_index)),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    _save_checkpoint(cp)


def _checkpoint_clear(phase_name: str):
    cp = _load_checkpoint()
    if phase_name in cp:
        del cp[phase_name]
        _save_checkpoint(cp)


# ════════════════════════════════════════════════════════════════════════════════
# PHASE 0: 지자체복지서비스 목록 수집 → DB 신규 등록
# ════════════════════════════════════════════════════════════════════════════════

CATEGORY_MAP = {
    "01": "medical",   # 건강
    "02": "care",      # 돌봄
    "03": "living",    # 생활지원
    "04": "housing",   # 주거
    "05": "finance",   # 경제
    "06": "mobility",  # 이동
    "07": "living",    # 교육 → 생활
    "08": "living",    # 문화여가 → 생활
}


def fetch_local_welfare_list(page: int, num_rows: int = 100) -> list:
    """지자체복지서비스 목록 1페이지 조회"""
    try:
        resp = requests.get(LOCAL_WELFARE_LIST_URL, params={
            "serviceKey": LOCAL_WELFARE_API_KEY,
            "pageNo": page,
            "numOfRows": num_rows,
        }, timeout=15)
        resp.raise_for_status()
        root = ET.fromstring(resp.text)

        items = []
        for item in root.findall(".//servList") or root.findall(".//list"):
            def g(tag):
                el = item.find(tag)
                return (el.text or "").strip() if el is not None else ""

            serv_id = g("wlfareInfoId") or g("servId")
            items.append({
                "serv_id": serv_id,
                "name": g("wlfareSvcNm") or g("servNm"),
                "category": CATEGORY_MAP.get(g("lifeArray") or g("category"), "living"),
                "description": g("servDgst") or g("summary"),
                "target_info": g("tgtrDscr") or g("target"),
                "benefit_info": g("givBnfScpCn") or g("benefit"),
                "apply_place": g("aplyMtd") or g("applyMethod"),
                "region": normalize_region(g("ctpvNm") or ""),
                "source": "local",
            })

        # 총 건수 파악
        total_el = root.find(".//totalCount")
        if total_el is None:
            total_el = root.find(".//totCnt")
        total = int(total_el.text) if total_el is not None and total_el.text else len(items)
        return items, total

    except Exception as e:
        print(f"    목록 조회 오류 (page {page}): {e}")
        return [], 0


def run_phase0(supabase) -> int:
    """Phase 0: 지자체복지서비스 전체 목록 수집 → welfare_services 신규 등록"""
    print("\n━━━ PHASE 0: 지자체복지서비스 수집 ━━━")

    # 기존 지자체 서비스 ID 목록 (online_url에 저장된 WLF ID로 중복 체크)
    existing = supabase.table("welfare_services").select("online_url").eq("source", "local").execute()
    existing_ids = {r["online_url"] for r in existing.data if r.get("online_url")}
    print(f"  기존 서비스: {len(existing_ids)}개")

    page, num_rows = 1, 100
    total_new = total_skip = 0

    while True:
        print(f"  페이지 {page} 조회 중...", end="", flush=True)
        items, total_count = fetch_local_welfare_list(page, num_rows)

        if not items:
            break

        if page == 1:
            print(f" 총 {total_count}개 서비스 발견")

        new_items = [it for it in items if it["serv_id"] and it["serv_id"] not in existing_ids]
        skip_items = len(items) - len(new_items)
        total_skip += skip_items

        for it in new_items:
            if not it["name"]:
                continue
            try:
                supabase.table("welfare_services").upsert({
                    "name": it["name"],
                    "category": it["category"],
                    "description": it["description"] or it["name"],
                    "target_info": it["target_info"],
                    "benefit_info": it["benefit_info"],
                    "apply_place": it["apply_place"],
                    "online_url": it["serv_id"],
                    "difficulty": 2,
                    "is_renewable": False,
                    "min_age": 0,
                    "max_income_level": 10,
                    "requires_ltc_grade": False,
                    "requires_alone": False,
                    "requires_basic_recipient": False,
                    "gender": "any",
                    "target_age_group": "unknown",
                    "region": it.get("region", ""),
                    "source": "local",
                }, on_conflict="online_url").execute()
                existing_ids.add(it["serv_id"])
                total_new += 1
            except Exception as e:
                if "duplicate" not in str(e).lower():
                    print(f"\n    ⚠ 삽입 오류 ({it['serv_id']}): {e}")

        print(f"  → 신규 {len(new_items)}개 등록, 중복 {skip_items}개 스킵")
        time.sleep(API_REQUEST_DELAY)

        if len(items) < num_rows:   # 마지막 페이지
            break
        page += 1

    print(f"\n  Phase 0 완료: 신규 등록={total_new}, 중복 스킵={total_skip}")
    return total_new


def _provider_uid(category: str, region: str, name: str, address: str, phone: str) -> str:
    key = f"{category}|{region}|{name}|{address}|{phone}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:32]


def fetch_social_providers(category: str, region: str, page_size: int = 200) -> list[dict]:
    service_type = SOCIAL_CATEGORY_SERVICE_TYPE.get(category)
    if not service_type or not SOCIAL_SERVICE_API_KEY:
        return []
    try:
        resp = requests.get(
            SOCIAL_SERVICE_PROVIDER_URL,
            params={
                "serviceType": service_type,
                "sigunguNm": region,
                "searchIdx": 0,
                "pageSize": page_size,
                "serviceKey": SOCIAL_SERVICE_API_KEY,
            },
            timeout=15,
        )
        resp.raise_for_status()
        root = ET.fromstring(resp.text)

        items = []
        for item in root.findall(".//item"):
            def txt(tag: str) -> str:
                el = item.find(tag)
                return (el.text or "").strip() if el is not None else ""

            name = txt("provNm")
            addr = txt("addr")
            phone = txt("telNo")
            if not name:
                continue
            items.append({
                "provider_uid": _provider_uid(category, region, name, addr, phone),
                "name": name,
                "address": addr,
                "phone": phone,
                "category": category,
                "region": region,
                "source": "socialservice",
                "updated_at": datetime.now(timezone.utc).isoformat(),
            })
        return items
    except Exception as e:
        print(f"    제공기관 조회 오류 ({category}/{region}): {e}")
        return []


def run_phase_providers(supabase) -> int:
    print("\n━━━ PHASE P: 사회서비스 제공기관 수집 ━━━")
    if not SOCIAL_SERVICE_API_KEY:
        print("  ⚠ SOCIAL_SERVICE_API_KEY 미설정 → 스킵")
        return 0

    total_upsert = 0
    for category in SOCIAL_CATEGORY_SERVICE_TYPE.keys():
        for region in SIDO_REGIONS:
            providers = fetch_social_providers(category, region)
            if not providers:
                continue
            try:
                supabase.table("service_providers").upsert(
                    providers,
                    on_conflict="provider_uid",
                ).execute()
                total_upsert += len(providers)
                print(f"  ✓ {category}/{region}: {len(providers)}건")
            except Exception as e:
                print(f"  ❌ 저장 실패 ({category}/{region}): {e}")
            time.sleep(0.2)

    print(f"  Phase P 완료: upsert={total_upsert}")
    return total_upsert


# ════════════════════════════════════════════════════════════════════════════════
# ════════════════════════════════════════════════════════════════════════════════

WEB_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7",
    "Accept-Encoding": "gzip, deflate, br",
    "Referer": "https://www.bokjiro.go.kr/ssis-tbu/twataa/wlfareInfo/moveTWAT52005M.do",
    "Connection": "keep-alive",
}

def strip_html(text: str) -> str:
    """HTML 태그 제거, <br/> → 줄바꿈"""
    if not text:
        return ""
    text = re.sub(r'<br\s*/?>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'<[^>]+>', '', text)
    return text.strip()


def parse_welfare_html(html: str) -> dict | None:
    """HTML에서 initParameter의 dmWlfareInfo 파싱"""
    # 알려진 필드 → 한글 레이블 매핑
    FIELD_LABELS = {
        "wlfareInfoOutlCn": "서비스 개요",
        "wlfareSprtTrgtCn": "지원 대상",
        "slctCritCn": "선정 기준",
        "wlfareSprtBnftCn": "지원 혜택",
        "aplyMtdDc": "신청 방법",
        "rqutPdFrmCn": "신청 서류",
        "servDgstNm": "서비스 요약",
        "wlfareTrgtNm": "대상 유형",
        "mngtMrofCd": "주관 부서",
        "wfareInfoPrmiDt": "시행일",
    }
    decoder = json.JSONDecoder()
    for m in re.finditer(r'initParameter\s*\(\s*(\{)', html):
        start = m.start(1)
        try:
            obj, _ = decoder.raw_decode(html, start)
            iv = obj.get('initValue', {})
            if not isinstance(iv, dict) or 'dmWlfareInfo' not in iv:
                continue
            dm_raw = iv.get("dmWlfareInfo", "{}")
            dtl_raw = iv.get("dsWlfareInfoDtl", "[]")
            dm = json.loads(dm_raw) if isinstance(dm_raw, str) else dm_raw
            dtl = json.loads(dtl_raw) if isinstance(dtl_raw, str) else dtl_raw
            phones = [d["wlfareInfoReldCn"] for d in dtl
                      if d.get("wlfareInfoDtlCd") == "010" and d.get("wlfareInfoReldCn")]

            # detail_content = 개요 + 선정기준 합산 (AI 분류에 활용)
            outline = strip_html(dm.get("wlfareInfoOutlCn") or "")
            criteria = strip_html(dm.get("slctCritCn") or "")
            if outline and criteria:
                detail = f"{outline}\n\n[선정기준]\n{criteria}"
            else:
                detail = outline or criteria

            # raw_content = 모든 텍스트 필드 레이블과 함께 전체 저장
            raw_parts = []
            for key, val in dm.items():
                if not isinstance(val, str) or not val.strip():
                    continue
                cleaned = strip_html(val.strip())
                if not cleaned:
                    continue
                label = FIELD_LABELS.get(key, key)
                raw_parts.append(f"[{label}]\n{cleaned}")
            if phones:
                raw_parts.append(f"[문의처]\n{', '.join(phones)}")
            raw_content = "\n\n".join(raw_parts)

            return {
                "target_info": strip_html(dm.get("wlfareSprtTrgtCn") or ""),
                "benefit_info": strip_html(dm.get("wlfareSprtBnftCn") or ""),
                "apply_place": strip_html(dm.get("aplyMtdDc") or ""),
                "detail_content": detail,
                "inq_place": ", ".join(phones),
                "raw_content": raw_content,
            }
        except (json.JSONDecodeError, Exception):
            continue
    return None


def fetch_local_welfare_playwright(page, serv_id: str) -> dict | None:
    """Playwright로 복지로 상세 페이지 로드 후 page.content()로 HTML 파싱.
    page는 매 요청마다 새로 생성된 페이지여야 함 (SPA 라우터 우회).
    """
    try:
        page.goto(
            f"{BOKJIRO_WEB_URL}?wlfareInfoId={serv_id}&wlfareInfoReldBztpCd=02",
            wait_until="domcontentloaded",
            timeout=20000,
        )
    except Exception as e:
        print(f"\n    [DEBUG] goto 실패: {str(e)[:120]}", flush=True)
        return None

    html = page.content()
    if not html:
        print(f"\n    [DEBUG] page.content() 비어있음", flush=True)
        return None

    if 'initParameter' not in html:
        print(f"\n    [DEBUG] HTML {len(html)}자, initParameter 없음 (서버가 데이터 미포함)", flush=True)
        return None

    result = parse_welfare_html(html)
    if not result:
        print(f"\n    [DEBUG] HTML {len(html)}자, initParameter 있음, 파싱 실패", flush=True)
    return result


def run_phase0_detail(supabase) -> int:
    from playwright.sync_api import sync_playwright

    print("\n━━━ PHASE 0 DETAIL: 지자체복지서비스 상세 수집 ━━━")

    limit = int(os.getenv("PHASE0_DETAIL_LIMIT", "200"))
    result = (
        supabase.table("welfare_services")
        .select("id, name, online_url, description")
        .eq("source", "local")
        .is_("detail_fetched_at", "null")
        .limit(limit)
        .execute()
    )
    all_services = result.data or []

    if not all_services:
        print("  처리할 서비스 없음 (이미 완료)")
        return 0

    print(f"  처리 대상: {len(all_services)}개")
    ok = fail = consecutive_fail = 0
    MAX_CONSECUTIVE_FAIL = 20

    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=True,
            args=[
                "--no-sandbox",
                "--disable-dev-shm-usage",
                "--disable-blink-features=AutomationControlled",
            ],
        )
        context = browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            locale="ko-KR",
            viewport={"width": 1280, "height": 800},
        )
        context.add_init_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")

        # 워밍업 - 홈페이지 먼저 방문해서 세션/쿠키 확립
        warmup_page = context.new_page()
        try:
            warmup_page.goto("https://www.bokjiro.go.kr/ssis-tbu/index.do",
                             wait_until="domcontentloaded", timeout=15000)
            time.sleep(1.0)
            warmup_page.goto("https://www.bokjiro.go.kr/ssis-tbu/twataa/wlfareInfo/moveTWAT52005M.do",
                             wait_until="domcontentloaded", timeout=20000)
        except Exception:
            pass
        finally:
            warmup_page.close()

        for i, svc in enumerate(all_services):
            serv_id = svc.get("online_url")
            name_short = (svc.get("name") or "")[:20]

            if not serv_id:
                fail += 1
                continue

            print(f"  [{i+1}/{len(all_services)}] {name_short}... ", end="", flush=True)

            # 매 요청 전 목록 페이지 방문 → 서버 세션 상태 리셋 (상세 데이터 미포함 방지)
            pre_page = context.new_page()
            try:
                pre_page.goto(
                    "https://www.bokjiro.go.kr/ssis-tbu/twataa/wlfareInfo/moveTWAT52005M.do",
                    wait_until="domcontentloaded", timeout=15000,
                )
                time.sleep(1.0)
            except Exception:
                pass
            finally:
                pre_page.close()

            # 상세 페이지 요청 (새 페이지로 실제 HTTP GET)
            page = context.new_page()
            should_break = False
            try:
                data = fetch_local_welfare_playwright(page, serv_id)
                if not data:
                    print("⚠ 파싱 실패")
                    fail += 1
                    consecutive_fail += 1
                    if consecutive_fail >= MAX_CONSECUTIVE_FAIL:
                        print(f"\n  연속 {MAX_CONSECUTIVE_FAIL}회 실패 → 조기 종료")
                        should_break = True
                    else:
                        time.sleep(WEB_SCRAPE_DELAY * 3)
                else:
                    source_text = "\n".join(
                        filter(
                            None,
                            [
                                data.get("raw_content", ""),
                                data.get("detail_content", ""),
                                data.get("apply_place", ""),
                            ],
                        )
                    )
                    inferred_region = infer_region(source_text)
                    base_region = inferred_region or ""
                    inferred_sub_region = infer_sub_region(source_text, base_region)
                    update = {
                        "target_info": data["target_info"],
                        "benefit_info": data["benefit_info"],
                        "apply_place": data["apply_place"],
                        "detail_content": data["detail_content"] or svc.get("description", ""),
                        "inq_place": data["inq_place"],
                        "raw_content": data["raw_content"],
                        "sub_region": inferred_sub_region or "",
                        "detail_fetched_at": datetime.now(timezone.utc).isoformat(),
                    }
                    _update_welfare_service(supabase, svc["id"], update)
                    t = len(update["target_info"])
                    b = len(update["benefit_info"])
                    d = len(update["detail_content"])
                    print(f"✓ (대상:{t}자 혜택:{b}자 내용:{d}자)")
                    ok += 1
                    consecutive_fail = 0

            except Exception as e:
                print(f"❌ {e}")
                fail += 1
                consecutive_fail += 1
                if consecutive_fail >= MAX_CONSECUTIVE_FAIL:
                    print(f"\n  연속 {MAX_CONSECUTIVE_FAIL}회 실패 → 조기 종료")
                    should_break = True

            finally:
                page.close()

            if should_break:
                break

            time.sleep(WEB_SCRAPE_DELAY)

        context.close()
        browser.close()

    print(f"\n  Phase 0 Detail 완료: 성공={ok}, 오류={fail}")
    return ok


# ════════════════════════════════════════════════════════════════════════════════
# PHASE 1: 복지로 API 상세 조회 → DB 저장
# ════════════════════════════════════════════════════════════════════════════════

def extract_welfare_id(online_url: str | None) -> str | None:
    if not online_url:
        return None
    try:
        from urllib.parse import urlparse, parse_qs
        qs = parse_qs(urlparse(online_url).query)
        if 'wlfareInfoId' in qs:
            return qs['wlfareInfoId'][0]
    except Exception:
        pass
    m = re.search(r'wlfareInfoId=([A-Z0-9]+)', online_url or '')
    if m:
        return m.group(1)
    # 순수 servId 형태 (예: WLF0001234, SVR0000001) → 그대로 반환
    if re.match(r'^[A-Z]{2,5}\d{5,10}$', online_url):
        return online_url
    return None


def fetch_welfare_detail(welfare_id: str) -> dict | None:
    params = {
        "serviceKey": WELFARE_API_KEY,
        "servId": welfare_id,
        "callTp": "D",
    }
    for attempt in range(1, MAX_DETAIL_API_RETRIES + 1):
        try:
            resp = requests.get(WELFARE_DETAIL_URL, params=params, timeout=10)
            if resp.status_code == 429:
                print(f"\n      ⚠ 429 → 일일 한도 초과, 스킵")
                return "QUOTA_EXCEEDED"
            if 500 <= resp.status_code < 600:
                raise requests.HTTPError(f"서버 오류 {resp.status_code}")
            if 400 <= resp.status_code < 500:
                print(f"      API 클라이언트 오류 ({welfare_id}): HTTP {resp.status_code}")
                return None
            resp.raise_for_status()

            root = ET.fromstring(resp.text)

            def txt(tag):
                el = root.find(f".//{tag}")
                return (el.text or "").strip() if el is not None else ""

            applmet_list = []
            for item in root.findall(".//applmetList"):
                method = txt_from(item, "applmetNm")
                desc = txt_from(item, "servSeDetailLink")
                if method:
                    applmet_list.append({"method": method, "description": desc})

            target_info = txt("trgtList")
            benefit_info = txt("givBnfScpCn") or txt("servDgst")
            apply_place = txt("aplyMtd")
            criteria = txt("slctCritCn")
            biz_summary = txt("bsnsSumry")
            detail_link = txt("servDtlLink")
            inq_place = txt("inqplCn")

            detail_parts = []
            for val in [target_info, apply_place, benefit_info, criteria, biz_summary, detail_link]:
                if val:
                    detail_parts.append(val)

            raw_parts = []
            if target_info:
                raw_parts.append(f"[지원 대상]\n{target_info}")
            if criteria:
                raw_parts.append(f"[선정 기준]\n{criteria}")
            if benefit_info:
                raw_parts.append(f"[지원 혜택]\n{benefit_info}")
            if apply_place:
                raw_parts.append(f"[신청 방법]\n{apply_place}")
            if inq_place:
                raw_parts.append(f"[문의처]\n{inq_place}")
            if biz_summary:
                raw_parts.append(f"[사업 요약]\n{biz_summary}")
            if detail_link:
                raw_parts.append(f"[상세 링크]\n{detail_link}")
            raw_content = "\n\n".join(raw_parts)

            return {
                "applmet_list": applmet_list,
                "inq_place": inq_place,
                "detail_content": "\n".join(detail_parts),
                "target_info": target_info,
                "benefit_info": benefit_info,
                "apply_place": apply_place,
                "raw_content": raw_content,
            }

        except (requests.RequestException, ET.ParseError) as e:
            if attempt == MAX_DETAIL_API_RETRIES:
                print(f"      API 오류 ({welfare_id}): {e}")
                return None
            backoff = DETAIL_API_RETRY_BASE_DELAY * attempt
            print(f"      재시도 {attempt}/{MAX_DETAIL_API_RETRIES} ({welfare_id}): {e}")
            time.sleep(backoff)

    return None


def txt_from(element, tag: str) -> str:
    el = element.find(tag)
    return (el.text or "").strip() if el is not None else ""


def run_phase1(supabase) -> int:
    print("\n━━━ PHASE 1: 복지로 API 상세 수집 ━━━")

    # 1차: 아직 한번도 수집 안 한 것
    result = (
        supabase.table("welfare_services")
        .select("id, name, online_url, target_info, benefit_info, apply_place, region")
        .eq("source", "national")
        .is_("detail_fetched_at", "null")
        .execute()
    )
    # 2차: 수집했지만 raw_content 비어있는 것 (재수집)
    result2 = (
        supabase.table("welfare_services")
        .select("id, name, online_url, target_info, benefit_info, apply_place, region")
        .eq("source", "national")
        .not_.is_("detail_fetched_at", "null")
        .eq("raw_content", "")
        .not_.is_("online_url", "null")
        .execute()
    )
    services = result.data + result2.data
    if not services:
        print("  ✅ 모든 서비스 상세 수집 완료")
        return 0

    print(f"  처리 대상: {len(services)}개")
    ok = fail = skip = 0

    for i, svc in enumerate(services):
        welfare_id = extract_welfare_id(svc.get("online_url"))
        name_short = (svc.get("name") or "")[:25]

        if not welfare_id:
            supabase.table("welfare_services").update({
                "detail_fetched_at": datetime.now(timezone.utc).isoformat(),
            }).eq("id", svc["id"]).execute()
            skip += 1
            continue

        print(f"  [{i+1}/{len(services)}] {name_short}... ", end="", flush=True)
        detail = fetch_welfare_detail(welfare_id)

        if detail == "QUOTA_EXCEEDED":
            # 일일 한도 초과 → 루프 즉시 종료
            print(f"\n  일일 한도 초과 → 중단 (성공={ok}, 스킵={skip}, 오류={fail})")
            break
        elif detail is None:
            print("❌ API 오류")
            fail += 1
        else:
            target_info = detail.get("target_info") or svc.get("target_info") or ""
            benefit_info = detail.get("benefit_info") or svc.get("benefit_info") or ""
            apply_place = detail.get("apply_place") or svc.get("apply_place") or ""
            sub_region = infer_sub_region(
                "\n".join(filter(None, [detail.get("raw_content", ""), detail.get("detail_content", ""), apply_place])),
                svc.get("region") or "",
            )
            _update_welfare_service(supabase, svc["id"], {
                "applmet_list": detail["applmet_list"],
                "inq_place": detail["inq_place"],
                "detail_content": detail["detail_content"],
                "target_info": target_info,
                "benefit_info": benefit_info,
                "apply_place": apply_place,
                "raw_content": detail.get("raw_content", ""),
                "sub_region": sub_region or "",
                "detail_fetched_at": datetime.now(timezone.utc).isoformat(),
            })
            print("✓")
            ok += 1

        time.sleep(API_REQUEST_DELAY)

    print(f"\n  Phase 1 완료: 성공={ok}, 스킵={skip}, 오류={fail}")
    return ok + skip


def run_phase1_lite(supabase, limit: int = 250) -> int:
    """상세 빈 데이터만 빠르게 보강 (일일 순환 배치용)."""
    print("\n━━━ PHASE 1-lite: 상세 누락 보강 ━━━")
    result = (
        supabase.table("welfare_services")
        .select("id, name, online_url, target_info, benefit_info, apply_place, detail_content, raw_content, region")
        .eq("source", "national")
        .not_.is_("online_url", "null")
        .or_("detail_content.eq.,raw_content.eq.")
        .limit(limit)
        .execute()
    )
    services = result.data or []
    if not services:
        print("  ✅ 보강할 누락 상세 없음")
        return 0

    print(f"  처리 대상: {len(services)}개")
    ok = fail = 0
    for i, svc in enumerate(services):
        welfare_id = extract_welfare_id(svc.get("online_url"))
        name_short = (svc.get("name") or "")[:25]
        if not welfare_id:
            continue
        print(f"  [{i+1}/{len(services)}] {name_short}... ", end="", flush=True)
        detail = fetch_welfare_detail(welfare_id)
        if detail in (None, "QUOTA_EXCEEDED"):
            print("⚠")
            fail += 1
            if detail == "QUOTA_EXCEEDED":
                break
        else:
            sub_region = infer_sub_region(
                "\n".join(
                    filter(
                        None,
                        [
                            detail.get("raw_content", ""),
                            detail.get("detail_content", ""),
                            detail.get("apply_place", ""),
                            svc.get("apply_place", ""),
                        ],
                    )
                ),
                svc.get("region") or "",
            )
            _update_welfare_service(supabase, svc["id"], {
                "applmet_list": detail["applmet_list"],
                "inq_place": detail["inq_place"],
                "detail_content": detail["detail_content"] or (svc.get("detail_content") or ""),
                "target_info": detail.get("target_info") or (svc.get("target_info") or ""),
                "benefit_info": detail.get("benefit_info") or (svc.get("benefit_info") or ""),
                "apply_place": detail.get("apply_place") or (svc.get("apply_place") or ""),
                "raw_content": detail.get("raw_content") or (svc.get("raw_content") or ""),
                "sub_region": sub_region or "",
                "detail_fetched_at": datetime.now(timezone.utc).isoformat(),
            })
            print("✓")
            ok += 1
        time.sleep(API_REQUEST_DELAY)
    print(f"\n  Phase 1-lite 완료: 성공={ok}, 오류={fail}")
    return ok

# ════════════════════════════════════════════════════════════════════════════════
# PHASE 2: Gemini AI 분류 → DB 저장
# ════════════════════════════════════════════════════════════════════════════════

EXTRACTION_RULES = """
추출 규칙:
- min_age: 최소 나이(정수), 없으면 null ("65세 이상"→65, "60세 이상"→60)
- max_age: 최대 나이(정수), 없으면 null
- gender: "any" / "male" / "female"
- max_income_level: 소득분위 1~10
    기초수급자≈1, 차상위≈2, 하위30%≈3, 하위40%≈4, 하위50%≈5,
    하위60%≈6, 하위70%≈7, 하위80%≈8, 제한없음=10
- income_description: 소득 조건 원문 요약 (없으면 "")
- requires_ltc_grade: 장기요양등급 필수 여부
- ltc_grade_min: 최소 등급 정수 (없으면 null, 1=최중증, 6=인지지원)
- ltc_grade_max: 최대 등급 정수 (없으면 null)
- requires_alone: 독거노인 전용 여부
- requires_basic_recipient: 기초생활수급자 전용 여부
- requires_disability: 장애인 전용 여부
- requires_veteran: 보훈대상자 필수 여부 (참전유공자·국가유공자·독립유공자)
- category: 서비스 카테고리 (하나만 선택)
    "medical"  → 의료비·건강검진·치료·투약·보청기·안경·개안수술
    "care"     → 돌봄·요양·방문요양·집안일·식사지원·목욕·일상생활 지원
    "living"   → 생활비·통신비·이동전화요금·냉난방비·식품·문화·여가·교육
    "housing"  → 주거·임대·집수리·주택개조
    "finance"  → 연금·수당·현금지원·바우처·생계급여
    "mobility" → 교통비·버스요금·차량지원·이동도우미·병원동행 (※이동통신/전화요금은 living)
    ※ 이동전화·통신비는 반드시 "living"으로 분류
- service_tags: 서비스 성격 태그 배열 (해당하는 것 모두 포함)
    "dementia"   → 치매 관련 서비스
    "mobility"   → 이동지원·병원동행·교통지원
    "daily_care" → 식사·세면·집안일·일상생활 지원
    "hearing"    → 청각 지원·보청기
    "vision"     → 시각 지원·안경·개안수술
    "medical"    → 의료비·건강검진·투약 지원
    예: ["daily_care", "mobility"] / 해당 없으면 []
- target_age_group:
    "elderly"   → 노인·어르신·65세이상·60세이상·장기요양
    "youth"     → 청소년·청년·대학생·13~39세
    "child"     → 아동·영유아·초중고·0~12세
    "infant"    → 신생아·임산부·산모·태아·출산
    "adult"     → 일반성인·특정연령조건없음
    "veteran"   → 참전유공자·국가보훈·독립유공자·보훈
    "disabled"  → 장애인 전용
    "all"       → 전연령·소득기준만있음
    "unknown"   → 판단불가
- region: 시도명
    지역 판단 기준 (아래 순서로 적용):
    1. API에서 지역 정보(region_hint)가 제공된 경우 → 그대로 사용 (내용과 무관하게 우선)
    2. 대상 자격/거주 조건에 시도명이 명시된 경우만 해당 시도로 분류
       ✅ "서울시에 주민등록된 어르신" → 서울
       ✅ "경기도 거주 65세 이상" → 경기
       ✅ "○○도 노인 전용 서비스" → 해당 시도
    3. 신청처·문의처에 특정 시도명이 등장하는 경우 → 해당 시도로 분류
       (특정 지역 기관에서만 신청 가능하면 사실상 그 지역 서비스)
       ✅ "서울 주민센터에 방문 신청" → 서울
       ✅ "부산광역시청 복지과 문의" → 부산
       ❌ "가까운 주민센터에 신청" → 전국 (특정 시도 없음)
       ❌ "복지로(bokjiro.go.kr) 온라인 신청" → 전국 (전국 공통)
    4. 전국 단위 서비스이거나 판단 불가 → "전국"
    ※ 시도명 형식: "서울" "경기" "부산" 등 짧은 형태 사용
- confidence: 추출 확신도 0.0~1.0
- summary: 40~50대 자녀가 부모님께 설명하고 바로 신청할 수 있도록 다음 내용을 포함해 2~4문장으로 작성
    ① 누가 받을 수 있는지 (나이·소득·거주지·상황 조건을 구체적으로)
    ② 어떤 혜택을 받는지 (금액·서비스 내용을 구체적으로, 금액은 숫자로 명시)
    ③ 어떻게 신청하는지 (방문/온라인/전화 등 간략히)
    ※ 존댓말로 작성, 전문용어 대신 쉬운 표현 사용
    예: "만 65세 이상 기초생활수급자 어르신께 매달 이·미용 서비스 바우처 3만원을 드리는 사업이에요.
         소득이 적은 홀몸 어르신이라면 신청해볼 만해요. 읍면동 주민센터에 방문해서 신청하시면 돼요."
    예: "부산에 사시는 65세 이상 어르신 중 소득 하위 70% 이하라면 냉·난방비를 최대 연 30만원 지원받을 수 있어요.
         부산시청 복지과나 가까운 주민센터에 문의하시면 돼요."
"""


def make_prompt(svc: dict) -> str:
    region_hint = svc.get("region") or ""
    raw = (svc.get("raw_content") or "").strip()
    target = (svc.get("target_info") or "").strip()
    benefit = (svc.get("benefit_info") or "").strip()
    detail = (svc.get("detail_content") or "").strip()

    # raw_content 우선 사용 (선정기준·신청방법 등 전체 포함), 없으면 개별 필드 조합
    if raw:
        content_block = f"원문 전체:\n{raw[:2000]}"
    else:
        parts = []
        if target: parts.append(f"지원대상: {target[:500]}")
        if benefit: parts.append(f"지원내용: {benefit[:300]}")
        if detail: parts.append(f"상세내용: {detail[:600]}")
        content_block = "\n".join(parts)

    return f"""당신은 한국 복지 서비스 자격 조건 분석 전문가입니다. 반드시 JSON만 응답하세요.

서비스명: {svc.get('name', '')}
지역: {region_hint if region_hint else '(미확인 - 내용에서 추출)'}
{content_block}

다음 JSON 형식으로만 응답:
{{
  "min_age": null,
  "max_age": null,
  "gender": "any",
  "max_income_level": 10,
  "income_description": "",
  "requires_ltc_grade": false,
  "ltc_grade_min": null,
  "ltc_grade_max": null,
  "requires_alone": false,
  "requires_basic_recipient": false,
  "requires_disability": false,
  "requires_veteran": false,
  "target_age_group": "unknown",
  "service_tags": [],
  "region": "{region_hint if region_hint else '전국'}",
  "confidence": 0.8,
  "summary": ""
}}

{EXTRACTION_RULES}"""


def parse_json_response(text: str) -> dict | None:
    text = text.strip()
    if "```" in text:
        for part in text.split("```"):
            part = part.strip().lstrip("json").strip()
            if part.startswith("{"):
                text = part
                break
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        s, e = text.find("{"), text.rfind("}") + 1
        if s >= 0 and e > s:
            try:
                return json.loads(text[s:e])
            except Exception:
                pass
    return None


def _build_ai_input_text(svc: dict) -> str:
    return " ".join(
        part.strip()
        for part in [
            svc.get("name") or "",
            svc.get("target_info") or "",
            svc.get("benefit_info") or "",
            svc.get("detail_content") or "",
            svc.get("raw_content") or "",
        ]
        if isinstance(part, str) and part.strip()
    )


def _build_ai_input_hash(svc: dict) -> str:
    source_text = _build_ai_input_text(svc)
    return hashlib.sha256(source_text.encode("utf-8")).hexdigest()


def _should_skip_ai_call(svc: dict, reclassify: bool) -> tuple[bool, str]:
    source_text = _build_ai_input_text(svc)
    if len(source_text) < AI_MIN_CONTENT_LENGTH:
        return True, "입력 텍스트 부족"

    if not reclassify:
        return False, ""

    ai_criteria = svc.get("ai_criteria")
    if not isinstance(ai_criteria, dict):
        return False, ""

    prev_hash = ai_criteria.get("input_hash")
    curr_hash = _build_ai_input_hash(svc)
    confidence = svc.get("filter_confidence") or 0.0
    try:
        confidence = float(confidence)
    except Exception:
        confidence = 0.0

    if prev_hash and prev_hash == curr_hash and confidence >= AI_SKIP_CONFIDENCE_THRESHOLD:
        return True, f"변경 없음(conf={confidence:.2f})"

    return False, ""


def run_phase2(supabase) -> int:
    print("\n━━━ PHASE 2: Gemini AI 분류 ━━━")

    result = (
        supabase.table("welfare_services")
        .select("id, name, target_info, benefit_info, detail_content, raw_content, region")
        .is_("filter_updated_at", "null")
        .order("id")
        .limit(1000)
        .execute()
    )
    services = result.data or []
    if not services:
        print("  ✅ 모든 서비스 AI 분류 완료")
        return 0

    start_index = _checkpoint_get_start_index("phase2")
    if start_index >= len(services):
        start_index = 0
    if start_index > 0:
        print(f"  체크포인트 복구: {start_index + 1}번째부터 재개")

    print(f"  처리 대상: {len(services)}개 (모델: {MODEL})")
    print(f"  예상 소요시간: 약 {len(services) * GEMINI_DELAY / 60:.0f}분")

    genai_client = google_genai.Client(api_key=GEMINI_API_KEY)

    ok = fail = parse_err = skipped = 0

    for i in range(start_index, len(services)):
        svc = services[i]
        name_short = (svc.get("name") or "")[:25]
        print(f"  [{i+1}/{len(services)}] {name_short}... ", end="", flush=True)

        should_skip, reason = _should_skip_ai_call(svc, reclassify=False)
        if should_skip:
            supabase.table("welfare_services").update({
                "filter_updated_at": datetime.now(timezone.utc).isoformat(),
            }).eq("id", svc["id"]).execute()
            print(f"↷ 스킵 ({reason})")
            skipped += 1
            _checkpoint_set_index("phase2", i + 1)
            continue

        try:
            response = genai_client.models.generate_content(
                model=MODEL, contents=make_prompt(svc)
            )
            criteria = parse_json_response(response.text)

            if criteria is None:
                print("⚠ JSON 파싱 오류")
                parse_err += 1
            else:
                input_hash = _build_ai_input_hash(svc)
                criteria_with_meta = dict(criteria)
                criteria_with_meta["input_hash"] = input_hash
                supabase.table("welfare_services").update({
                    "category": criteria.get("category", "living"),
                    "gender": criteria.get("gender", "any"),
                    "min_age": criteria.get("min_age"),
                    "max_income_level": criteria.get("max_income_level", 10),
                    "requires_ltc_grade": criteria.get("requires_ltc_grade", False),
                    "requires_alone": criteria.get("requires_alone", False),
                    "requires_basic_recipient": criteria.get("requires_basic_recipient", False),
                    "requires_disability": criteria.get("requires_disability", False),
                    "requires_veteran": criteria.get("requires_veteran", False),
                    "service_tags": criteria.get("service_tags", []),
                    "target_age_group": criteria.get("target_age_group", "unknown"),
                    "region": normalize_region(criteria.get("region") or svc.get("region") or "전국"),
                    "ai_summary": criteria.get("summary", ""),
                    "ai_criteria": criteria_with_meta,
                    "filter_confidence": criteria.get("confidence", 0.0),
                    "filter_updated_at": datetime.now(timezone.utc).isoformat(),
                }).eq("id", svc["id"]).execute()
                age   = criteria.get('target_age_group', '?')
                reg   = criteria.get('region') or '?'
                mage  = criteria.get('min_age')
                inc   = criteria.get('max_income_level', 10)
                ltc   = '요양O' if criteria.get('requires_ltc_grade') else '요양X'
                aln   = '독거O' if criteria.get('requires_alone') else '독거X'
                bas   = '기초O' if criteria.get('requires_basic_recipient') else '기초X'
                vet   = '보훈O' if criteria.get('requires_veteran') else ''
                dis   = '장애O' if criteria.get('requires_disability') else ''
                age_str = f'{mage}세↑' if mage else '-'
                inc_str = f'소득{inc}↓' if inc < 10 else '소득전체'
                extras = ' '.join(filter(None, [vet, dis]))
                print(f"✓ {age} | {reg} | {age_str} | {inc_str} | {ltc} | {aln} | {bas}{(' | ' + extras) if extras else ''}")
                ok += 1

        except Exception as e:
            print(f"❌ {e}")
            fail += 1

        _checkpoint_set_index("phase2", i + 1)
        time.sleep(GEMINI_DELAY)

    _checkpoint_clear("phase2")
    print(f"\n  Phase 2 완료: 성공={ok}, 스킵={skipped}, JSON오류={parse_err}, 기타오류={fail}")
    return ok


# ════════════════════════════════════════════════════════════════════════════════
# PHASE 2r: 전체 서비스 순환 재분류 (오래된 순)
# ════════════════════════════════════════════════════════════════════════════════

def run_phase2r(supabase) -> int:
    print("\n━━━ PHASE 2r: 전체 순환 재분류 (oldest first) ━━━")

    result = (
        supabase.table("welfare_services")
        .select("id, name, target_info, benefit_info, detail_content, raw_content, region, ai_criteria, filter_confidence")
        .not_.is_("filter_updated_at", "null")
        .order("filter_updated_at", desc=False)
        .order("id")
        .limit(1000)
        .execute()
    )
    services = result.data or []
    if not services:
        print("  ✅ 재분류할 서비스 없음")
        return 0

    start_index = _checkpoint_get_start_index("phase2r")
    if start_index >= len(services):
        start_index = 0
    if start_index > 0:
        print(f"  체크포인트 복구: {start_index + 1}번째부터 재개")

    print(f"  처리 대상: {len(services)}개 (모델: {MODEL})")
    print(f"  예상 소요시간: 약 {len(services) * GEMINI_DELAY / 60:.0f}분")

    genai_client = google_genai.Client(api_key=GEMINI_API_KEY)
    ok = fail = parse_err = skipped = 0

    for i in range(start_index, len(services)):
        svc = services[i]
        name_short = (svc.get("name") or "")[:25]
        print(f"  [{i+1}/{len(services)}] {name_short}... ", end="", flush=True)

        should_skip, reason = _should_skip_ai_call(svc, reclassify=True)
        if should_skip:
            supabase.table("welfare_services").update({
                "filter_updated_at": datetime.now(timezone.utc).isoformat(),
            }).eq("id", svc["id"]).execute()
            print(f"↷ 스킵 ({reason})")
            skipped += 1
            _checkpoint_set_index("phase2r", i + 1)
            continue

        try:
            response = genai_client.models.generate_content(
                model=MODEL, contents=make_prompt(svc)
            )
            criteria = parse_json_response(response.text)

            if criteria is None:
                print("⚠ JSON 파싱 오류")
                parse_err += 1
            else:
                input_hash = _build_ai_input_hash(svc)
                criteria_with_meta = dict(criteria)
                criteria_with_meta["input_hash"] = input_hash
                supabase.table("welfare_services").update({
                    "category": criteria.get("category", "living"),
                    "gender": criteria.get("gender", "any"),
                    "min_age": criteria.get("min_age"),
                    "max_income_level": criteria.get("max_income_level", 10),
                    "requires_ltc_grade": criteria.get("requires_ltc_grade", False),
                    "requires_alone": criteria.get("requires_alone", False),
                    "requires_basic_recipient": criteria.get("requires_basic_recipient", False),
                    "requires_disability": criteria.get("requires_disability", False),
                    "requires_veteran": criteria.get("requires_veteran", False),
                    "service_tags": criteria.get("service_tags", []),
                    "target_age_group": criteria.get("target_age_group", "unknown"),
                    "region": normalize_region(criteria.get("region") or svc.get("region") or "전국"),
                    "ai_summary": criteria.get("summary", ""),
                    "ai_criteria": criteria_with_meta,
                    "filter_confidence": criteria.get("confidence", 0.0),
                    "filter_updated_at": datetime.now(timezone.utc).isoformat(),
                }).eq("id", svc["id"]).execute()
                age  = criteria.get('target_age_group', '?')
                reg  = criteria.get('region') or '?'
                mage = criteria.get('min_age')
                inc  = criteria.get('max_income_level', 10)
                ltc  = '요양O' if criteria.get('requires_ltc_grade') else '요양X'
                aln  = '독거O' if criteria.get('requires_alone') else '독거X'
                bas  = '기초O' if criteria.get('requires_basic_recipient') else '기초X'
                vet  = '보훈O' if criteria.get('requires_veteran') else ''
                dis  = '장애O' if criteria.get('requires_disability') else ''
                age_str = f'{mage}세↑' if mage else '-'
                inc_str = f'소득{inc}↓' if inc < 10 else '소득전체'
                extras = ' '.join(filter(None, [vet, dis]))
                print(f"✓ {age} | {reg} | {age_str} | {inc_str} | {ltc} | {aln} | {bas}{(' | ' + extras) if extras else ''}")
                ok += 1

        except Exception as e:
            print(f"❌ {e}")
            fail += 1

        _checkpoint_set_index("phase2r", i + 1)
        time.sleep(GEMINI_DELAY)

    _checkpoint_clear("phase2r")
    print(f"\n  Phase 2r 완료: 성공={ok}, 스킵={skipped}, JSON오류={parse_err}, 기타오류={fail}")
    return ok


# ════════════════════════════════════════════════════════════════════════════════
# FIX REGION: 지자체 서비스 region 후처리 (전국 → 실제 지역)
# ════════════════════════════════════════════════════════════════════════════════

# (패턴, 지역) - 긴/구체적인 것 먼저 (앞에서부터 매칭)
_REGION_PATTERNS = [
    # 광역시 구/군 (고유명)
    ("해운대구|수영구|기장군|부산진구|사하구|금정구|연제구|사상구|영도구", "부산"),
    ("수성구|달서구|달성군", "대구"),
    ("미추홀구|남동구|부평구|계양구|강화군|옹진군", "인천"),
    ("광산구", "광주"),
    ("유성구|대덕구", "대전"),
    ("울주군", "울산"),
    # 경기 시/군
    ("수원시?|성남시?|의정부시?|안양시?|부천시?|광명시?|평택시?|안산시?|고양시?|과천시?|구리시?|남양주시?|오산시?|시흥시?|군포시?|의왕시?|하남시?|용인시?|파주시?|이천시?|안성시?|김포시?|화성시?|양주시?|포천시?|여주시?|연천군|가평군|양평군", "경기"),
    # 강원 시/군
    ("춘천시?|원주시?|강릉시?|동해시?|태백시?|속초시?|삼척시?|홍천군|횡성군|영월군|평창군|정선군|철원군|화천군|양구군|인제군|고성군|양양군", "강원"),
    # 충북 시/군
    ("청주시?|충주시?|제천시?|보은군|옥천군|영동군|증평군|진천군|괴산군|음성군|단양군", "충북"),
    # 충남 시/군
    ("천안시?|공주시?|보령시?|아산시?|서산시?|논산시?|계룡시?|당진시?|금산군|부여군|서천군|청양군|홍성군|예산군|태안군", "충남"),
    # 전북 시/군
    ("전주시?|군산시?|익산시?|정읍시?|남원시?|김제시?|완주군|진안군|무주군|장수군|임실군|순창군|고창군|부안군", "전북"),
    # 전남 시/군
    ("목포시?|여수시?|순천시?|나주시?|광양시?|담양군|곡성군|구례군|고흥군|보성군|화순군|장흥군|강진군|해남군|영암군|무안군|함평군|영광군|장성군|완도군|진도군|신안군", "전남"),
    # 경북 시/군
    ("포항시?|경주시?|김천시?|안동시?|구미시?|영주시?|영천시?|상주시?|문경시?|경산시?|군위군|의성군|청송군|영양군|영덕군|청도군|고령군|성주군|칠곡군|예천군|봉화군|울진군|울릉군", "경북"),
    # 경남 시/군
    ("창원시?|진주시?|통영시?|사천시?|김해시?|밀양시?|거제시?|양산시?|의령군|함안군|창녕군|남해군|하동군|산청군|함양군|거창군|합천군", "경남"),
    # 제주
    ("제주시?|서귀포시?", "제주"),
    # 세종
    ("세종시?", "세종"),
    # 도 이름
    ("경기도", "경기"), ("강원도|강원특별자치도", "강원"),
    ("충청북도", "충북"), ("충청남도", "충남"),
    ("전라북도|전북특별자치도", "전북"), ("전라남도", "전남"),
    ("경상북도", "경북"), ("경상남도", "경남"),
    ("제주특별자치도", "제주"),
    # 광역시 이름
    ("부산시?|부산광역시", "부산"), ("대구시?|대구광역시", "대구"),
    ("인천시?|인천광역시", "인천"), ("광주시?|광주광역시", "광주"),
    ("대전시?|대전광역시", "대전"), ("울산시?|울산광역시", "울산"),
    ("서울시?|서울특별시", "서울"),
]
_COMPILED = [(re.compile(p), r) for p, r in _REGION_PATTERNS]


def infer_region(text: str) -> str | None:
    for pattern, region in _COMPILED:
        if pattern.search(text):
            return region
    return None


_SUB_REGION_BY_REGION = {
    "서울": ["종로구", "중구", "용산구", "성동구", "광진구", "동대문구", "중랑구", "성북구", "강북구", "도봉구", "노원구", "은평구", "서대문구", "마포구", "양천구", "강서구", "구로구", "금천구", "영등포구", "동작구", "관악구", "서초구", "강남구", "송파구", "강동구"],
    "부산": ["중구", "서구", "동구", "영도구", "부산진구", "동래구", "남구", "북구", "해운대구", "사하구", "금정구", "강서구", "연제구", "수영구", "사상구", "기장군"],
    "대구": ["중구", "동구", "서구", "남구", "북구", "수성구", "달서구", "달성군", "군위군"],
    "인천": ["중구", "동구", "미추홀구", "연수구", "남동구", "부평구", "계양구", "서구", "강화군", "옹진군"],
    "광주": ["동구", "서구", "남구", "북구", "광산구"],
    "대전": ["동구", "중구", "서구", "유성구", "대덕구"],
    "울산": ["중구", "남구", "동구", "북구", "울주군"],
    "세종": ["세종시"],
    "경기": ["수원시", "성남시", "의정부시", "안양시", "부천시", "광명시", "평택시", "동두천시", "안산시", "고양시", "과천시", "구리시", "남양주시", "오산시", "시흥시", "군포시", "의왕시", "하남시", "용인시", "파주시", "이천시", "안성시", "김포시", "화성시", "광주시", "양주시", "포천시", "여주시", "연천군", "가평군", "양평군"],
    "강원": ["춘천시", "원주시", "강릉시", "동해시", "태백시", "속초시", "삼척시", "홍천군", "횡성군", "영월군", "평창군", "정선군", "철원군", "화천군", "양구군", "인제군", "고성군", "양양군"],
    "충북": ["청주시", "충주시", "제천시", "보은군", "옥천군", "영동군", "증평군", "진천군", "괴산군", "음성군", "단양군"],
    "충남": ["천안시", "공주시", "보령시", "아산시", "서산시", "논산시", "계룡시", "당진시", "금산군", "부여군", "서천군", "청양군", "홍성군", "예산군", "태안군"],
    "전북": ["전주시", "군산시", "익산시", "정읍시", "남원시", "김제시", "완주군", "진안군", "무주군", "장수군", "임실군", "순창군", "고창군", "부안군"],
    "전남": ["목포시", "여수시", "순천시", "나주시", "광양시", "담양군", "곡성군", "구례군", "고흥군", "보성군", "화순군", "장흥군", "강진군", "해남군", "영암군", "무안군", "함평군", "영광군", "장성군", "완도군", "진도군", "신안군"],
    "경북": ["포항시", "경주시", "김천시", "안동시", "구미시", "영주시", "영천시", "상주시", "문경시", "경산시", "군위군", "의성군", "청송군", "영양군", "영덕군", "청도군", "고령군", "성주군", "칠곡군", "예천군", "봉화군", "울진군", "울릉군"],
    "경남": ["창원시", "진주시", "통영시", "사천시", "김해시", "밀양시", "거제시", "양산시", "의령군", "함안군", "창녕군", "남해군", "하동군", "산청군", "함양군", "거창군", "합천군"],
    "제주": ["제주시", "서귀포시"],
}


def infer_sub_region(text: str, region_hint: str | None = None) -> str | None:
    if not text:
        return None
    norm = re.sub(r"\s+", " ", text)

    # 후보를 먼저 추출하고(시/군/구/특별자치시), 지역 힌트 기준으로 검증
    candidates = re.findall(r"[가-힣]{2,12}(?:시|군|구|특별자치시)", norm)
    if not candidates:
        return None

    hint = normalize_region(region_hint or "") if region_hint else ""
    if hint and hint in _SUB_REGION_BY_REGION:
        allowed = _SUB_REGION_BY_REGION[hint]
        for c in candidates:
            if c in allowed:
                return c
        return None

    # 힌트가 없으면 전체 목록에서 첫 매칭 사용
    for region, names in _SUB_REGION_BY_REGION.items():
        for c in candidates:
            if c in names:
                return c
    return None

# ── cmmCdNm 코드 기반 규칙 분류 ──────────────────────────────────────────────

# 생애주기 코드 → target_age_group
LFTM_CYC_MAP = {
    "노년":   "elderly",
    "아동":   "child",
    "청소년": "youth",
    "청년":   "youth",
    "영유아": "infant",
    "중장년": "adult",
    "구분없음(전생애)": "all",
}

def parse_cmmcd(raw_content: str) -> dict:
    """
    raw_content의 cmmCdNm 코드에서 규칙 기반 분류 추출
    AI 분류보다 정확한 경우가 많음
    """
    result = {}

    # cmmCdNm 추출
    cmmcd_match = re.search(r'\[cmmCdNm\]\s*(.+)', raw_content)
    if not cmmcd_match:
        return result
    cmmcd = cmmcd_match.group(1)

    # 생애주기 (LFTM_CYC_CD)
    lftm_match = re.search(r'LFTM_CYC_CD:([^;]+)', cmmcd)
    if lftm_match:
        values = lftm_match.group(1).split(',')
        # 노년이 포함되면 elderly 우선
        if "노년" in values:
            result["target_age_group"] = "elderly"
        elif len(values) >= 4:
            # 여러 생애주기면 all
            result["target_age_group"] = "all"
        else:
            for v in values:
                v = v.strip()
                if v in LFTM_CYC_MAP:
                    result["target_age_group"] = LFTM_CYC_MAP[v]
                    break

    # 장애인 여부
    if "DSPSN_REG_DCD:등록장애인" in cmmcd:
        result["requires_disability"] = True
        if "target_age_group" not in result:
            result["target_age_group"] = "disabled"

    # 소득 기준
    if "기초생활수급대상자" in cmmcd:
        result["requires_basic_recipient"] = True
        result["max_income_level"] = 1
    elif "차상위" in cmmcd:
        result["max_income_level"] = 2

    # 보훈 여부
    if any(k in cmmcd for k in ["보훈대상자", "국가유공자", "참전유공자"]):
        result["requires_veteran"] = True
        if "target_age_group" not in result:
            result["target_age_group"] = "veteran"

    # 독거 여부
    if "독거" in cmmcd:
        result["requires_alone"] = True

    return result

def run_fix_region(supabase) -> int:
    print("\n━━━ FIX REGION: 지자체 서비스 지역 후처리 ━━━")
    result = (
        supabase.table("welfare_services")
        .select("id, name, target_info, description, apply_place, detail_content, region, sub_region, raw_content")
        .eq("source", "local")
        .eq("region", "전국")
        .execute()
    )
    services = result.data or []
    print(f"  대상: {len(services)}개 (region=전국인 지자체 서비스)")

    updated = skipped = 0
    for svc in services:
        # raw_content에서 [addr] 태그 먼저 추출 (가장 정확)
        raw = svc.get("raw_content") or ""
        addr_match = re.search(r'\[addr\]\s*(.+)', raw)
        dept_match = re.search(r'\[bizChrDeptNm\]\s*(.+)', raw)

        inferred = None
        source_for_sub_region = ""

        # 1순위: [addr] 태그
        if addr_match:
            source_for_sub_region = addr_match.group(1).strip()
            inferred = infer_region(source_for_sub_region)

        # 2순위: [bizChrDeptNm] 태그
        if not inferred and dept_match:
            source_for_sub_region = dept_match.group(1).strip()
            inferred = infer_region(source_for_sub_region)

        # 3순위: 기존 텍스트 검색
        if not inferred:
            text = " ".join(filter(None, [
                svc.get("name", ""),
                svc.get("target_info", ""),
                svc.get("description", ""),
                svc.get("apply_place", ""),
                svc.get("detail_content", ""),
            ]))
            source_for_sub_region = text
            inferred = infer_region(text)

        if inferred:
            inferred_sub_region = infer_sub_region(source_for_sub_region, inferred)
            _update_welfare_service(
                supabase,
                svc["id"],
                {
                    "region": inferred,
                    "sub_region": inferred_sub_region or "",
                },
            )
            updated += 1
        else:
            skipped += 1

    print(f"  수정: {updated}개 / 추론 불가(유지): {skipped}개")
    return updated

# ════════════════════════════════════════════════════════════════════════════════
# FIX CMMCD: cmmCdNm 코드 기반 규칙 분류 보정
# ════════════════════════════════════════════════════════════════════════════════

def run_fix_cmmcd(supabase) -> int:
    """
    raw_content의 cmmCdNm 코드로 AI 분류 결과 보정
    특히 unknown → 정확한 분류로 변경
    """
    print("\n━━━ FIX CMMCD: 코드 기반 분류 보정 ━━━")

    result = (
        supabase.table("welfare_services")
        .select("id, name, target_age_group, raw_content")
        .not_.is_("raw_content", "null")
        .execute()
    )
    services = result.data or []
    print(f"  대상: {len(services)}개")

    updated = skipped = 0
    for svc in services:
        raw = svc.get("raw_content") or ""
        if not raw:
            skipped += 1
            continue

        fixes = parse_cmmcd(raw)
        if not fixes:
            skipped += 1
            continue

        # unknown인 경우만 덮어쓰기
        # 이미 분류된 것은 유지 (AI가 더 정확할 수 있음)
        current_age = svc.get("target_age_group", "unknown")
        if current_age == "unknown" and "target_age_group" in fixes:
            supabase.table("welfare_services").update(fixes).eq(
                "id", svc["id"]
            ).execute()
            updated += 1
        elif fixes:
            # unknown 아니어도 requires_* 필드는 업데이트
            fixes.pop("target_age_group", None)
            if fixes:
                supabase.table("welfare_services").update(fixes).eq(
                    "id", svc["id"]
                ).execute()
                updated += 1
            else:
                skipped += 1
        else:
            skipped += 1

    print(f"  보정: {updated}개 / 스킵: {skipped}개")
    return updated


def main(phase=None):
    validate_env(phase)
    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    print("=" * 60)
    print("  CareWay 복지서비스 배치 파이프라인")
    print("=" * 60)

    if phase == "0":
        run_phase0(supabase)
    elif phase == "providers":
        run_phase_providers(supabase)
    elif phase == "0_detail":
        run_phase0_detail(supabase)
    elif phase == "1":
        run_phase1(supabase)
    elif phase == "1_lite":
        run_phase1_lite(supabase)
    elif phase == "2":
        run_phase2(supabase)
    elif phase == "2r":
        run_phase1_lite(supabase, limit=300)
        run_phase2r(supabase)
    elif phase == "fix_region":
        run_fix_region(supabase)
    elif phase == "fix_cmmcd":          # ← 추가
        run_fix_cmmcd(supabase)
    elif phase == "fix_all":            # ← 추가 (region + cmmcd 한번에)
        run_fix_region(supabase)
        run_fix_cmmcd(supabase)        
    else:
        # both → 전체 실행
        run_phase0(supabase)
        run_phase_providers(supabase)
        run_phase0_detail(supabase)
        run_phase1(supabase)
        run_phase1_lite(supabase, limit=300)
        run_phase2(supabase)
        run_fix_region(supabase)

    print("\n🎉 배치 완료!")


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--phase":
        main(phase=args[1])
    else:
        main()
