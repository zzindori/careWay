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

WELFARE_DETAIL_URL = "https://apis.data.go.kr/B554287/NationalWelfareInformationsV001/NationalWelfaredetailedV001"

# 지자체복지서비스 API (한국사회보장정보원, 동일 제공기관 B554287)
LOCAL_WELFARE_LIST_URL = "https://apis.data.go.kr/B554287/LocalGovernmentWelfareInformations/LcgvWelfarelist"
LOCAL_WELFARE_DETAIL_URL = "https://apis.data.go.kr/B554287/LocalGovernmentWelfareInformations/LcgvWelfaredetailed"  # 사용 안 함 (웹 스크래핑으로 대체)
BOKJIRO_WEB_URL = "https://www.bokjiro.go.kr/ssis-tbu/twataa/wlfareInfo/moveTWAT52013M.do"

MODEL = "gemini-2.0-flash"
API_REQUEST_DELAY = 1.2    # 복지로 API rate limit 방지 (개발계정 100 RPM → 최소 0.6초, 여유분 포함)
WEB_SCRAPE_DELAY = 0.5     # 복지로 웹 스크래핑 딜레이 (API 한도 없음, 서버 부하 방지 목적)
GEMINI_DELAY = 4.5         # Gemini 무료 티어: 15 RPM → 4초 간격

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


# ── 환경변수 체크 ──────────────────────────────────────────────────────────────

def validate_env():
    missing = []
    if not SUPABASE_SERVICE_KEY:
        missing.append("SUPABASE_SERVICE_KEY")
    if not GEMINI_API_KEY:
        missing.append("GEMINI_API_KEY")
    if not WELFARE_API_KEY:
        missing.append("WELFARE_API_KEY")
    if missing:
        print(f"❌ 환경변수 미설정: {', '.join(missing)}")
        sys.exit(1)


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


# ════════════════════════════════════════════════════════════════════════════════
# PHASE 0 DETAIL: 지자체복지서비스 상세 수집 → DB 저장 (복지로 웹 스크래핑)
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

def fetch_local_welfare_web(session: requests.Session, serv_id: str) -> dict | None:
    """복지로 웹에서 지자체복지서비스 상세 스크래핑 (HTML 내 JSON 파싱)"""
    resp = session.get(
        BOKJIRO_WEB_URL,
        params={"wlfareInfoId": serv_id, "wlfareInfoReldBztpCd": "02"},
        timeout=15,
    )
    resp.raise_for_status()

    # initParameter({...}) 안의 JSON 추출 - raw_decode로 중첩 JSON 정확히 파싱
    # (비탐욕 정규식은 JSON 내부 `)` 문자를 잘못 종단점으로 인식하는 버그가 있음)
    decoder = json.JSONDecoder()
    outer = None
    for m in re.finditer(r'initParameter\s*\(\s*(\{)', resp.text):
        start = m.start(1)
        try:
            obj, _ = decoder.raw_decode(resp.text, start)
            if 'initValue' in obj:
                outer = obj
                break
        except json.JSONDecodeError:
            continue

    if not outer:
        return None

    init_val = outer.get("initValue", {})
    dm_raw = init_val.get("dmWlfareInfo", "{}")
    dtl_raw = init_val.get("dsWlfareInfoDtl", "[]")
    dm = json.loads(dm_raw) if isinstance(dm_raw, str) else dm_raw
    dtl = json.loads(dtl_raw) if isinstance(dtl_raw, str) else dtl_raw

    phones = [d["wlfareInfoReldCn"] for d in dtl if d.get("wlfareInfoDtlCd") == "010" and d.get("wlfareInfoReldCn")]

    return {
        "target_info": strip_html(dm.get("wlfareSprtTrgtCn") or ""),
        "benefit_info": strip_html(dm.get("wlfareSprtBnftCn") or ""),
        "apply_place": strip_html(dm.get("aplyMtdDc") or ""),
        "detail_content": strip_html(dm.get("wlfareInfoOutlCn") or ""),
        "inq_place": ", ".join(phones),
    }


def run_phase0_detail(supabase) -> int:
    print("\n━━━ PHASE 0 DETAIL: 지자체복지서비스 상세 수집 ━━━")

    # 미처리 항목 전체 조회 (웹 스크래핑은 API 한도 없음)
    result = (
        supabase.table("welfare_services")
        .select("id, name, online_url, description")
        .eq("source", "local")
        .is_("detail_fetched_at", "null")
        .limit(10000)
        .execute()
    )
    all_services = result.data or []

    if not all_services:
        print("  처리할 서비스 없음 (이미 완료)")
        return 0

    print(f"  처리 대상: {len(all_services)}개")
    ok = fail = 0

    session = requests.Session()
    session.headers.update(WEB_HEADERS)

    for i, svc in enumerate(all_services):
        serv_id = svc.get("online_url")
        name_short = (svc.get("name") or "")[:20]

        if not serv_id:
            fail += 1
            continue

        print(f"  [{i+1}/{len(all_services)}] {name_short}... ", end="", flush=True)

        try:
            data = fetch_local_welfare_web(session, serv_id)
            if not data:
                print("⚠ 파싱 실패")
                fail += 1
                time.sleep(WEB_SCRAPE_DELAY)
                continue

            update = {
                "target_info": data["target_info"],
                "benefit_info": data["benefit_info"],
                "apply_place": data["apply_place"],
                "detail_content": data["detail_content"] or svc.get("description", ""),
                "inq_place": data["inq_place"],
                "detail_fetched_at": datetime.now(timezone.utc).isoformat(),
            }
            supabase.table("welfare_services").update(update).eq("id", svc["id"]).execute()
            t = len(update["target_info"])
            b = len(update["benefit_info"])
            d = len(update["detail_content"])
            print(f"✓ (대상:{t}자 혜택:{b}자 내용:{d}자)")
            ok += 1

        except Exception as e:
            print(f"❌ {e}")
            fail += 1

        time.sleep(WEB_SCRAPE_DELAY)

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
    return m.group(1) if m else None


def fetch_welfare_detail(welfare_id: str) -> dict | None:
    params = {
        "serviceKey": WELFARE_API_KEY,
        "servId": welfare_id,
        "callTp": "D",
    }
    for attempt in range(3):
        try:
            resp = requests.get(WELFARE_DETAIL_URL, params=params, timeout=10)
            if resp.status_code == 429:
                print(f"\n      ⚠ 429 → 일일 한도 초과, 스킵")
                return "QUOTA_EXCEEDED" 
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

            detail_parts = []
            for tag in ["trgtList", "aplyMtd", "servDgst", "bsnsSumry", "servDtlLink"]:
                val = txt(tag)
                if val:
                    detail_parts.append(val)

            return {
                "applmet_list": applmet_list,
                "inq_place": txt("inqplCn"),
                "detail_content": "\n".join(detail_parts),
            }

        except Exception as e:
            print(f"      API 오류 ({welfare_id}): {e}")
            return None

    return None


def txt_from(element, tag: str) -> str:
    el = element.find(tag)
    return (el.text or "").strip() if el is not None else ""


def run_phase1(supabase) -> int:
    print("\n━━━ PHASE 1: 복지로 API 상세 수집 ━━━")

    result = (
        supabase.table("welfare_services")
        .select("id, name, online_url")
        .eq("source", "national")
        .is_("detail_fetched_at", "null")
        .execute()
    )
    services = result.data
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
            supabase.table("welfare_services").update({
                "applmet_list": detail["applmet_list"],
                "inq_place": detail["inq_place"],
                "detail_content": detail["detail_content"],
                "detail_fetched_at": datetime.now(timezone.utc).isoformat(),
            }).eq("id", svc["id"]).execute()
            print("✓")
            ok += 1

        time.sleep(API_REQUEST_DELAY)

    print(f"\n  Phase 1 완료: 성공={ok}, 스킵={skip}, 오류={fail}")
    return ok + skip

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
- summary: 이 서비스가 누구를 위한 것이고 어떤 혜택을 주는지를 중학생도 이해할 수 있는 말로 2~3문장으로 요약
    예: "소득이 적은 65세 이상 어르신께 매달 일정 금액을 드리는 제도예요. 기초생활수급자나 차상위계층 어르신이라면 신청해 볼 만해요."
    예: "65세 이상 어르신의 집을 고쳐주는 서비스예요. 방수·단열·난방 등 꼭 필요한 부분을 무료 또는 저가로 수리해 드려요."
    ※ 존댓말로 작성, 전문용어 대신 쉬운 표현 사용
"""


def make_prompt(svc: dict) -> str:
    detail = (svc.get("detail_content") or "")[:600]
    region_hint = svc.get("region") or ""
    return f"""당신은 한국 복지 서비스 자격 조건 분석 전문가입니다. 반드시 JSON만 응답하세요.

서비스명: {svc.get('name', '')}
지역: {region_hint if region_hint else '(미확인 - 내용에서 추출)'}
지원대상: {(svc.get('target_info') or '')[:500]}
지원내용: {(svc.get('benefit_info') or '')[:300]}
상세내용: {detail}

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


def run_phase2(supabase) -> int:
    print("\n━━━ PHASE 2: Gemini AI 분류 ━━━")

    result = (
        supabase.table("welfare_services")
        .select("id, name, target_info, benefit_info, detail_content, region")
        .is_("filter_updated_at", "null")
        .limit(1000)
        .execute()
    )
    services = result.data
    if not services:
        print("  ✅ 모든 서비스 AI 분류 완료")
        return 0

    print(f"  처리 대상: {len(services)}개 (모델: {MODEL})")
    print(f"  예상 소요시간: 약 {len(services) * GEMINI_DELAY / 60:.0f}분")

    genai_client = google_genai.Client(api_key=GEMINI_API_KEY)

    ok = fail = parse_err = 0

    for i, svc in enumerate(services):
        name_short = (svc.get("name") or "")[:25]
        print(f"  [{i+1}/{len(services)}] {name_short}... ", end="", flush=True)

        try:
            response = genai_client.models.generate_content(
                model=MODEL, contents=make_prompt(svc)
            )
            criteria = parse_json_response(response.text)

            if criteria is None:
                print("⚠ JSON 파싱 오류")
                parse_err += 1
            else:
                supabase.table("welfare_services").update({
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
                    "ai_criteria": criteria,
                    "filter_confidence": criteria.get("confidence", 0.0),
                    "filter_updated_at": datetime.now(timezone.utc).isoformat(),
                }).eq("id", svc["id"]).execute()
                print(f"✓ ({criteria.get('target_age_group', '?')})")
                ok += 1

        except Exception as e:
            print(f"❌ {e}")
            fail += 1

        time.sleep(GEMINI_DELAY)

    print(f"\n  Phase 2 완료: 성공={ok}, JSON오류={parse_err}, 기타오류={fail}")
    return ok


# ════════════════════════════════════════════════════════════════════════════════
# 메인
# ════════════════════════════════════════════════════════════════════════════════

def main(phase=None):
    validate_env()
    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    print("=" * 60)
    print("  CareWay 복지서비스 배치 파이프라인")
    print("=" * 60)

    if phase == "0":
        run_phase0(supabase)
    elif phase == "0_detail":
        run_phase0_detail(supabase)
    elif phase == "1":
        run_phase1(supabase)
    elif phase == "2":
        run_phase2(supabase)
    else:
        # both → 전체 실행
        run_phase0_detail(supabase)
        run_phase1(supabase)
        run_phase2(supabase)

    print("\n🎉 배치 완료!")


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--phase":
        main(phase=args[1])
    else:
        main()
