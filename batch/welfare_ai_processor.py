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
LOCAL_WELFARE_DETAIL_URL = "https://apis.data.go.kr/B554287/LocalGovernmentWelfareInformations/LcgvWelfaredetailed"

MODEL = "gemini-2.0-flash"
API_REQUEST_DELAY = 1.2    # 복지로 API rate limit 방지 (개발계정 100 RPM → 최소 0.6초, 여유분 포함)
GEMINI_DELAY = 4.5         # Gemini 무료 티어: 15 RPM → 4초 간격

# ── 환경변수 체크 ──────────────────────────────────────────────────────────────

def validate_env():
    missing = []
    if not SUPABASE_SERVICE_KEY:
        missing.append("SUPABASE_SERVICE_KEY")
    if not GEMINI_API_KEY:
        missing.append("GEMINI_API_KEY")
    if not WELFARE_API_KEY:
        missing.append("WELFARE_API_KEY")
    if not LOCAL_WELFARE_API_KEY:
        missing.append("LOCAL_WELFARE_API_KEY")
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
                "serv_id": serv_id,           # 중복 체크용, insert 때 online_url에 저장
                "name": g("wlfareSvcNm") or g("servNm"),
                "category": CATEGORY_MAP.get(g("lifeArray") or g("category"), "living"),
                "description": g("servDgst") or g("summary"),
                "target_info": g("tgtrDscr") or g("target"),
                "benefit_info": g("givBnfScpCn") or g("benefit"),
                "apply_place": g("aplyMtd") or g("applyMethod"),
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
                supabase.table("welfare_services").insert({
                    "name": it["name"],
                    "category": it["category"],
                    "description": it["description"] or it["name"],
                    "target_info": it["target_info"],
                    "benefit_info": it["benefit_info"],
                    "apply_place": it["apply_place"],
                    "online_url": it["serv_id"],   # WLF ID → 중복방지 및 상세조회용
                    "difficulty": 2,
                    "is_renewable": False,
                    "min_age": 0,
                    "max_income_level": 10,
                    "requires_ltc_grade": False,
                    "requires_alone": False,
                    "requires_basic_recipient": False,
                    "target_age_group": "unknown",
                    "source": "local",
                }).execute()
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
                wait = 60 * (attempt + 1)
                print(f"\n      ⚠ 429 → {wait}초 대기 후 재시도...", flush=True)
                time.sleep(wait)
                continue
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

        if detail is None:
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
- target_age_group:
    "elderly"  → 노인·어르신·60세 이상·65세 이상
    "youth"    → 청소년 (13~19세)
    "child"    → 아동·영유아 (0~12세)
    "adult"    → 일반 성인 (특정 고령 조건 없음)
    "all"      → 전 연령 대상
    "unknown"  → 판단 불가
- confidence: 추출 확신도 0.0~1.0
"""


def make_prompt(svc: dict) -> str:
    detail = (svc.get("detail_content") or "")[:600]
    return f"""당신은 한국 복지 서비스 자격 조건 분석 전문가입니다. 반드시 JSON만 응답하세요.

서비스명: {svc.get('name', '')}
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
  "target_age_group": "unknown",
  "confidence": 0.8
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
        .select("id, name, target_info, benefit_info, detail_content")
        .is_("filter_updated_at", "null")
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
                    "target_age_group": criteria.get("target_age_group", "unknown"),
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

def main(phase: int | None = None):
    validate_env()
    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    print("=" * 60)
    print("  CareWay 복지서비스 배치 파이프라인")
    print("=" * 60)

    if phase is None or phase == 0:
        run_phase0(supabase)
    if phase is None or phase == 1:
        run_phase1(supabase)
    if phase is None or phase == 2:
        run_phase2(supabase)

    print("\n🎉 배치 완료! 앱을 재시작하면 업데이트된 데이터가 반영됩니다.")


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--phase":
        main(phase=int(args[1]))
    else:
        main()
