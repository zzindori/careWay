#!/usr/bin/env python3
"""
CareWay 복지서비스 통합 배치 파이프라인
========================================
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

import google.generativeai as genai
from supabase import create_client

# ── 설정 ──────────────────────────────────────────────────────────────────────

SUPABASE_URL = "https://dnnidnqwkjmbssxixpjg.supabase.co"
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
WELFARE_API_KEY = os.environ.get("WELFARE_API_KEY", "")

WELFARE_DETAIL_URL = "https://apis.data.go.kr/B554287/NationalWelfareInformationsV001/NationalWelfaredetailedV001"

MODEL = "gemini-1.5-flash"
API_REQUEST_DELAY = 0.3    # 복지로 API rate limit 방지
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
    if missing:
        print(f"❌ 환경변수 미설정: {', '.join(missing)}")
        sys.exit(1)


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
    try:
        resp = requests.get(WELFARE_DETAIL_URL, params=params, timeout=10)
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

    genai.configure(api_key=GEMINI_API_KEY)
    model = genai.GenerativeModel(MODEL)

    ok = fail = parse_err = 0

    for i, svc in enumerate(services):
        name_short = (svc.get("name") or "")[:25]
        print(f"  [{i+1}/{len(services)}] {name_short}... ", end="", flush=True)

        try:
            response = model.generate_content(make_prompt(svc))
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

    if phase != 2:
        run_phase1(supabase)
    if phase != 1:
        run_phase2(supabase)

    print("\n🎉 배치 완료! 앱을 재시작하면 업데이트된 데이터가 반영됩니다.")


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--phase":
        main(phase=int(args[1]))
    else:
        main()
