#!/usr/bin/env python3
"""
CareWay local welfare crawler batch.

Runs separately from the national welfare API/AI classification pipeline.
GitHub Actions should use the Supabase service role key in SUPABASE_SERVICE_KEY
(not the anon public key) so RLS on staging tables can be bypassed as intended.
"""

from __future__ import annotations

import json
import os
import re
import time
import base64
from datetime import datetime, timezone
from pathlib import Path

from supabase import create_client

from local_welfare_crawler import (
    LOCAL_PILOT_KEYWORDS,
    PILOT_LOCAL_TARGETS,
    discover_elderly_region_targets,
    fetch_local_pilot_page,
    strip_html,
)


SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://dnnidnqwkjmbssxixpjg.supabase.co")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")
WEB_SCRAPE_DELAY = float(os.environ.get("LOCAL_WELFARE_CRAWL_DELAY", "0.5"))
LOCAL_WELFARE_CRAWL_TARGET = os.environ.get("LOCAL_WELFARE_CRAWL_TARGET", "pilot")
LOCAL_WELFARE_REPORT_PATH = os.environ.get("LOCAL_WELFARE_REPORT_PATH", "batch/output/local_welfare_report.json")
LOCAL_WELFARE_RESET_EXISTING = os.environ.get("LOCAL_WELFARE_RESET_EXISTING", "false").lower() in {"1", "true", "yes"}
LOCAL_WELFARE_PROMOTE_WARNINGS = os.environ.get("LOCAL_WELFARE_PROMOTE_WARNINGS", "false").lower() in {"1", "true", "yes"}

ALLOWED_SERVICE_TAGS = {
    "dementia",
    "mobility",
    "daily_care",
    "hearing",
    "vision",
    "medical",
    "hospital_companion",
    "meal_support",
    "home_visit",
    "financial_support",
    "housing_repair",
    "mental_health",
    "caregiver_support",
}

SERVICE_TAG_SEARCH_ALIASES = {
    "dementia": ["치매", "인지", "인지지원"],
    "mobility": ["이동", "이동지원", "교통지원", "차량지원", "택시"],
    "daily_care": ["돌봄", "일상생활", "가사", "요양", "재가"],
    "hearing": ["보청기", "청각", "난청"],
    "vision": ["시각", "안경", "개안", "저시력"],
    "medical": ["의료", "진료", "치료", "검진", "투약"],
    "hospital_companion": ["병원동행", "동행", "의료동행", "병원"],
    "meal_support": ["식사", "식사지원", "도시락", "급식"],
    "home_visit": ["방문", "방문돌봄", "방문요양", "재가방문"],
    "financial_support": ["지원금", "수당", "현금지원", "바우처", "급여"],
    "housing_repair": ["주거", "집수리", "주택개조", "주거개선"],
    "mental_health": ["정신건강", "심리", "상담", "우울"],
    "caregiver_support": ["가족돌봄", "간병가족", "부양가족", "돌봄휴가"],
}

SEARCH_TOKEN_STOPWORDS = {
    "안내",
    "안내표입니다",
    "나뉘어",
    "설명합니다",
    "유형",
    "사업",
    "내용",
    "운영",
    "기간",
    "이상",
    "이내",
    "일부를",
    "위해",
    "정함에",
    "따름",
    "비고",
    "비고로",
    "수집",
    "출처",
    "원문",
    "url",
    "https",
    "www",
    "go",
    "kr",
    "contents",
    "do",
    "key",
    "제목",
    "관련",
    "지역",
    "주민",
    "대상",
    "확인하세요",
    "finance",
    "medical",
    "living",
    "care",
    "housing",
    "mobility",
}

SEARCH_TOKEN_ALLOW_PATTERNS = [
    re.compile(r"^[가-힣]{2,12}(?:시|군|구)$"),
    re.compile(r"^\d{2,4}-\d{3,4}-\d{4}$"),
    re.compile(r"^\d+(?:\.\d+)?만원$"),
    re.compile(r"^\d+(?:~\d+)?개월$"),
]

SEARCH_TOKEN_KEYWORDS = {
    "노인일자리",
    "노인일자리확대지원",
    "노인공익활동사업",
    "노인역량활용사업",
    "공동체사업단",
    "취업지원",
    "취업알선형",
    "수행기관",
    "대한노인회",
    "노인복지관",
    "기초연금",
    "활동비",
    "지원금",
    "수당",
    "급여",
    "바우처",
    "돌봄",
    "방문건강",
    "장애인",
    "특별공급",
    "주거지원",
    "복지사각지대",
    "취약계층",
    "치매",
    "무료급식",
    "도시락",
    "의료",
    "검진",
}


def _split_search_words(text: str) -> list[str]:
    cleaned = strip_html(text or "").lower()
    return re.findall(r"[a-z0-9가-힣]+", cleaned) if cleaned else []


def _supabase_key_role(key: str) -> str:
    try:
        parts = key.split(".")
        if len(parts) < 2:
            return "unknown"
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        decoded = json.loads(base64.urlsafe_b64decode(payload.encode("utf-8")).decode("utf-8"))
        return decoded.get("role") or "unknown"
    except Exception:
        return "unknown"


def _infer_min_age(text: str) -> int | None:
    match = re.search(r"(?:만\s*)?(\d{2})\s*세\s*이상", text or "")
    if not match:
        return None
    age = int(match.group(1))
    return age if 0 < age < 120 else None


def _infer_income_level(text: str) -> int:
    text = _positive_rule_text(text)
    if "기초생활수급" in text or "생계급여 수급자 지원" in text:
        return 1
    if "차상위" in text:
        return 2
    if "저소득" in text:
        return 3
    return 10


def _infer_target_age_group(text: str) -> str:
    if any(keyword in text for keyword in ["임신", "출산", "산모", "영유아", "신생아", "태아", "입양"]):
        return "infant"
    if any(keyword in text for keyword in ["아동", "어린이", "초등", "중학생", "고등학생", "학생"]):
        return "child"
    if any(keyword in text for keyword in ["청소년", "청년", "대학생", "청년층"]):
        return "youth"
    if any(keyword in text for keyword in ["국가유공자", "참전유공자", "독립유공자"]):
        return "veteran"
    if any(keyword in text for keyword in ["장애인", "등록장애인"]):
        return "disabled"
    if any(keyword in text for keyword in ["노인", "어르신", "고령", "65세", "60세", "경로", "실버"]):
        return "elderly"
    return "all"


def _augment_service_tags(text: str) -> list[str]:
    tags = set()
    if any(keyword in text for keyword in ["병원동행", "이동지원", "교통지원", "차량지원", "택시"]):
        tags.update(["mobility", "hospital_companion"])
    if any(keyword in text for keyword in ["치매", "인지활동", "인지지원서비스"]):
        tags.add("dementia")
    if any(keyword in text for keyword in ["방문요양", "일상생활", "가사", "식사"]):
        tags.add("daily_care")
    if any(keyword in text for keyword in ["식사", "도시락", "급식"]):
        tags.add("meal_support")
    if any(keyword in text for keyword in ["방문요양", "방문돌봄", "방문건강", "방문간호", "가정방문", "재가방문"]):
        tags.add("home_visit")
    if any(keyword in text for keyword in ["보청기", "청각"]):
        tags.add("hearing")
    if any(keyword in text for keyword in ["안경", "시각", "개안"]):
        tags.add("vision")
    if any(keyword in text for keyword in ["의료지원", "진료", "치료", "투약", "검진", "보건소"]):
        tags.add("medical")
    if any(keyword in text for keyword in ["지원금", "수당", "급여", "바우처", "현금"]):
        tags.add("financial_support")
    if any(keyword in text for keyword in ["주거개선", "주택개조", "집수리"]):
        tags.add("housing_repair")
    if any(keyword in text for keyword in ["정신건강", "심리상담", "우울"]):
        tags.add("mental_health")
    if any(keyword in text for keyword in ["가족돌봄", "간병가족", "부양가족"]):
        tags.add("caregiver_support")
    return [tag for tag in tags if tag in ALLOWED_SERVICE_TAGS]


def _normalize_category(category: str, service_tags: list[str], text: str) -> str:
    if "medical" in service_tags or any(keyword in text for keyword in ["의료지원", "진료", "병원동행", "투약", "검진", "보청기", "안경", "치료"]):
        return "medical"
    if any(tag in service_tags for tag in ["daily_care", "dementia"]) or any(keyword in text for keyword in ["돌봄", "요양", "방문요양", "간병", "목욕", "재가"]):
        return "care"
    if "mobility" in service_tags or any(keyword in text for keyword in ["병원동행", "교통", "택시", "차량지원"]):
        return "mobility"
    if any(keyword in text for keyword in ["주거", "임대", "집수리", "주택"]):
        return "housing"
    if any(keyword in text for keyword in ["연금", "수당", "지원금", "현금", "바우처", "생계급여"]):
        return "finance"
    return category if category in {"medical", "care", "living", "housing", "finance", "mobility"} else "living"


def _build_applmet_list(apply_place: str) -> list[dict]:
    lines = [line.strip(" -•·\t") for line in re.split(r"\n+|(?<=\.)\s+", strip_html(apply_place)) if line.strip()]
    methods = []
    for line in lines:
        method = "기타"
        if re.search(r"\d{2,4}-\d{3,4}-\d{4}", line):
            method = "전화"
        elif any(keyword in line for keyword in ["방문", "주민센터", "시군구", "행정복지센터"]):
            method = "방문"
        elif any(keyword in line for keyword in ["온라인", "인터넷", "복지로", "홈페이지"]):
            method = "온라인"
        elif any(keyword in line for keyword in ["전화", "콜센터", "문의"]):
            method = "전화"
        methods.append({"method": method, "description": line})
    return methods


def _positive_rule_text(text: str) -> str:
    text = re.split(r"제외대상|제외자", text or "", maxsplit=1)[0]
    text = re.sub(r"유사\s*중복사업\s*[:：][^.。]*", " ", text)
    text = re.sub(r"유사\s*중복사업[^지원내용신청방법문의]*", " ", text)
    return text


def _normalize_service_name(sub_region: str, source_name: str) -> str:
    source_name = source_name.strip()
    if source_name.startswith(sub_region):
        return source_name
    return f"{sub_region} {source_name}".strip()


def _infer_apply_place(text: str, phone: str, fallback: str) -> str:
    if "사업 수행기관별 접수" in text or "수행기관별 접수" in text:
        return "사업 수행기관별 접수" + (f" / {phone}" if phone else "")
    if "행정복지센터 방문신청" in text or "읍면동 행정복지센터" in text or "읍·면·동 주민센터" in text:
        return "관할 읍면동 행정복지센터" + (f" / {phone}" if phone else "")
    return phone or fallback


def _requires_basic_recipient(text: str, max_income_level: int) -> bool:
    if max_income_level != 1:
        return False
    positive_text = _positive_rule_text(text)
    return "기초생활수급" in positive_text and not any(keyword in positive_text for keyword in ["또는", "차상위", "기초연금"])


def _requires_ltc_grade(text: str) -> bool:
    positive_text = _positive_rule_text(text)
    return "장기요양" in positive_text and ("등급" in positive_text or "인정" in positive_text)


def _requires_alone(text: str, name: str) -> bool:
    if "노인일자리" in name:
        return False
    positive_text = _positive_rule_text(text)
    return "독거노인" in positive_text or "독거 노인" in positive_text or "홀몸" in positive_text


def _build_search_tokens(payload: dict) -> list[str]:
    bag = []
    for key in ["name", "region", "sub_region", "apply_place"]:
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            bag.extend(_split_search_words(value))
    for key in ["description", "benefit_info", "detail_content"]:
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            bag.extend(_extract_domain_tokens(value))
    for tag in payload.get("service_tags") or []:
        bag.extend(_split_search_words(str(tag)))
        bag.extend(SERVICE_TAG_SEARCH_ALIASES.get(tag, []))

    seen = set()
    tokens = []
    for token in bag:
        if not _is_good_search_token(token) or token in seen:
            continue
        seen.add(token)
        tokens.append(token)
    return tokens[:80]


def _extract_domain_tokens(text: str) -> list[str]:
    tokens = []
    lowered = text.lower()
    for keyword in SEARCH_TOKEN_KEYWORDS:
        if keyword.lower() in lowered:
            tokens.append(keyword)
    tokens.extend(re.findall(r"\d+(?:\.\d+)?만원", text))
    tokens.extend(re.findall(r"\d+(?:~\d+)?개월", text))
    tokens.extend(re.findall(r"\d{2,4}-\d{3,4}-\d{4}", text))
    return tokens


def _is_good_search_token(token: str) -> bool:
    if not token or len(token) < 2:
        return False
    if token in SEARCH_TOKEN_STOPWORDS:
        return False
    if token.isdigit():
        return False
    if re.fullmatch(r"[a-z0-9]+", token):
        return False
    if any(pattern.match(token) for pattern in SEARCH_TOKEN_ALLOW_PATTERNS):
        return True
    if token in SEARCH_TOKEN_KEYWORDS:
        return True
    if token in ALLOWED_SERVICE_TAGS:
        return True
    if any(token in aliases for aliases in SERVICE_TAG_SEARCH_ALIASES.values()):
        return True
    if token.endswith(("지원", "사업", "수당", "급여", "연금", "복지관", "지회", "센터")):
        return True
    return False


def _is_service_like(text: str) -> bool:
    if any(keyword in text for keyword in ["범죄경력", "일제 점검"]):
        return False
    service_markers = [
        "지원대상",
        "참여대상",
        "사업내용",
        "지원내용",
        "신청방법",
        "수행기관",
        "활동비",
        "기초연금",
        "노인일자리",
        "방문건강",
        "장애인",
        "특별공급",
        "신청기간",
        "신청대상",
        "접수기간",
        "입주자",
        "공급",
        "치매",
        "무료급식",
        "돌봄",
    ]
    return any(marker in text for marker in service_markers)


def _quality_warnings(payload: dict) -> list[str]:
    warnings = []
    name = payload.get("name", "")
    sub_region = payload.get("sub_region", "")
    detail = payload.get("detail_content", "")
    raw_content = payload.get("raw_content", "")

    if sub_region and name.count(sub_region) > 1:
        warnings.append("duplicate_region_name")
    if len(detail) < 120:
        warnings.append("short_detail_content")
    if not payload.get("inq_place"):
        warnings.append("missing_phone")
    if "현재 페이지에서 제공하는 정보에 만족하십니까" in detail:
        warnings.append("municipal_satisfaction_noise")
    if any(title in raw_content for title in ["site map", "YONGIN SPECIAL CITY", "노원복지소식"]):
        warnings.append("generic_source_title")
    if payload.get("target_age_group") != "elderly":
        warnings.append("non_elderly_target")
    if payload.get("requires_disability") and "장애인" not in detail:
        warnings.append("weak_disability_requirement")
    return warnings


def _report_snapshot(payload: dict, warnings: list[str]) -> dict:
    return {
        "name": payload.get("name"),
        "category": payload.get("category"),
        "region": payload.get("region"),
        "sub_region": payload.get("sub_region"),
        "online_url": payload.get("online_url"),
        "apply_place": payload.get("apply_place"),
        "inq_place": payload.get("inq_place"),
        "target_age_group": payload.get("target_age_group"),
        "service_tags": payload.get("service_tags") or [],
        "requires_ltc_grade": payload.get("requires_ltc_grade"),
        "requires_alone": payload.get("requires_alone"),
        "requires_basic_recipient": payload.get("requires_basic_recipient"),
        "search_tokens": payload.get("search_tokens") or [],
        "warnings": warnings,
    }


def _build_candidate_record(target: dict, page: dict, payload: dict | None, warnings: list[str], status: str) -> dict:
    return {
        "source_url": target["url"],
        "source_name": target["source_name"],
        "source_type": target.get("source_type"),
        "region": target["region"],
        "sub_region": target["sub_region"],
        "area_detail": target.get("area_detail", ""),
        "title": page.get("title", ""),
        "content": page.get("text", "")[:5000],
        "phone": page.get("phone", ""),
        "payload": payload,
        "quality_warnings": warnings,
        "status": status,
        "promoted_service_url": payload.get("online_url") if payload and status == "promoted" else None,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def _upsert_candidate(supabase, target: dict, page: dict, payload: dict | None, warnings: list[str], status: str) -> None:
    record = _build_candidate_record(target, page, payload, warnings, status)
    supabase.table("local_welfare_candidates").upsert(record, on_conflict="source_url").execute()


def _write_report(report: dict) -> None:
    path = Path(LOCAL_WELFARE_REPORT_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"  리포트 저장: {path}")


def _print_report_summary(report: dict) -> None:
    stats = report.get("stats", {})
    print("\n━━━ LOCAL CRAWLER REPORT ━━━")
    print(
        "  "
        f"후보={stats.get('candidates', 0)}, "
        f"승격={stats.get('promoted', 0)}, "
        f"보류={stats.get('held', 0)}, "
        f"스킵={stats.get('skipped', 0)}, "
        f"실패={stats.get('failed', 0)}, "
        f"429={stats.get('quota', 0)}, "
        f"품질경고={stats.get('warnings', 0)}"
    )

    promoted = report.get("promoted") or []
    if promoted:
        print("  승격 샘플:")
        for item in promoted[:10]:
            warnings = ",".join(item.get("warnings") or []) or "-"
            print(f"    - {item.get('name')} | {item.get('category')} | 경고={warnings}")

    held = report.get("held") or []
    if held:
        print("  후보 보류 샘플:")
        for item in held[:10]:
            warnings = ",".join(item.get("warnings") or []) or "-"
            print(f"    - {item.get('name')} | {item.get('category')} | 경고={warnings}")

    skipped = report.get("skipped") or []
    if skipped:
        print("  스킵 샘플:")
        for item in skipped[:5]:
            print(f"    - {item.get('source_name')} | {item.get('reason')}")

    failed = report.get("failed") or []
    if failed:
        print("  실패 샘플:")
        for item in failed[:5]:
            print(f"    - {item.get('source_name')} | {item.get('reason')}")


def _build_payload(target: dict, page: dict) -> dict | None:
    text = page.get("text", "")
    if not any(keyword in text for keyword in LOCAL_PILOT_KEYWORDS):
        return None
    if not _is_service_like(text):
        return None

    title = page.get("title") or target["source_name"]
    region = target["region"]
    sub_region = target["sub_region"]
    area_detail = target.get("area_detail", "")
    name = _normalize_service_name(sub_region, target["source_name"])
    source_text = " ".join(filter(None, [name, text, area_detail]))
    rule_text = _positive_rule_text(source_text)
    tags = _augment_service_tags(rule_text)
    category = target.get("category") or _normalize_category("living", tags, source_text)
    target_age_group = target.get("target_age_group") or _infer_target_age_group(source_text)
    min_age = target.get("min_age") or _infer_min_age(source_text)
    max_income_level = _infer_income_level(rule_text)
    phone = page.get("phone", "")
    apply_place = _infer_apply_place(text, phone, target["source_name"])
    if area_detail:
        apply_place = f"{target['source_name']} ({area_detail})" + (f" / {phone}" if phone else "")
    target_info = " ".join(part for part in [region, sub_region, area_detail, "지역 주민 대상 안내"] if part)

    raw_content = "\n\n".join([
        f"[수집 출처]\n{target['source_name']}",
        f"[지역]\n{region} {sub_region} {area_detail}".strip(),
        f"[원문 URL]\n{target['url']}",
        f"[원문 제목]\n{title}",
        f"[원문 내용]\n{text[:3000]}",
    ])
    payload = {
        "name": name[:200],
        "category": category,
        "description": text[:300] or name,
        "target_info": target_info,
        "benefit_info": text[:800],
        "apply_place": apply_place,
        "online_url": target["url"],
        "difficulty": 2,
        "is_renewable": True,
        "min_age": min_age,
        "max_income_level": max_income_level,
        "requires_ltc_grade": _requires_ltc_grade(rule_text),
        "requires_alone": _requires_alone(rule_text, name),
        "requires_basic_recipient": _requires_basic_recipient(rule_text, max_income_level),
        "requires_disability": "장애" in source_text and "노인" not in source_text,
        "requires_veteran": any(keyword in source_text for keyword in ["국가유공자", "참전유공자"]),
        "gender": "any",
        "target_age_group": target_age_group,
        "region": region,
        "sub_region": sub_region,
        "service_tags": tags,
        "applmet_list": _build_applmet_list(apply_place),
        "inq_place": phone,
        "detail_content": text[:2000],
        "raw_content": raw_content,
        "source": "local_site_pilot",
        "ai_summary": "",
    }
    payload["search_tokens"] = _build_search_tokens(payload)
    return payload


def run() -> int:
    if not SUPABASE_SERVICE_KEY:
        raise RuntimeError("SUPABASE_SERVICE_KEY is required")

    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    key_role = _supabase_key_role(SUPABASE_SERVICE_KEY)
    report = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "finished_at": None,
        "target": LOCAL_WELFARE_CRAWL_TARGET,
        "reset_existing": LOCAL_WELFARE_RESET_EXISTING,
        "supabase_key_role": key_role,
        "stats": {"candidates": 0, "promoted": 0, "held": 0, "skipped": 0, "failed": 0, "quota": 0, "warnings": 0},
        "promoted": [],
        "held": [],
        "skipped": [],
        "failed": [],
    }
    print("=" * 60)
    print("  CareWay 지역 복지 수집 로봇")
    print("=" * 60)
    print(f"  Supabase key role: {key_role}")
    print("\n━━━ LOCAL CRAWLER: 지역 노인복지 파일럿 수집 ━━━")

    candidates = promoted = held = skip = fail = quota = 0
    if LOCAL_WELFARE_RESET_EXISTING:
        supabase.table("local_welfare_candidates").delete().neq("source_url", "").execute()
        supabase.table("welfare_services").delete().eq("source", "local_site_pilot").execute()
        print("  기존 지역 후보/승격 데이터 정리 완료")
    else:
        print("  기존 지역 수집 데이터 유지: 후보/최종 URL 기준 누적 upsert")

    discovered_targets = discover_elderly_region_targets()
    if discovered_targets:
        print(f"  지역 노인복지 후보 발견: {len(discovered_targets)}건")

    targets = PILOT_LOCAL_TARGETS + discovered_targets
    seen_urls = set()
    for target in targets:
        if target["url"] in seen_urls:
            continue
        seen_urls.add(target["url"])
        print(f"  {target['source_name']} 수집 중... ", end="", flush=True)
        page = fetch_local_pilot_page(target)
        if not page:
            print("⚠ 실패")
            fail += 1
            report["failed"].append({
                "source_name": target["source_name"],
                "url": target["url"],
                "reason": "fetch_failed",
            })
            continue
        if page.get("quota_exceeded"):
            print("⚠ 429 중단")
            quota += 1
            report["failed"].append({
                "source_name": target["source_name"],
                "url": target["url"],
                "reason": "quota_exceeded",
            })
            break

        payload = _build_payload(target, page)
        if not payload:
            print("↷ 복지 키워드 부족")
            skip += 1
            try:
                _upsert_candidate(supabase, target, page, None, ["not_service_like"], "skipped")
            except Exception as exc:
                print(f" 후보저장실패={exc}")
            report["skipped"].append({
                "source_name": target["source_name"],
                "url": target["url"],
                "reason": "not_service_like",
            })
            continue

        try:
            warnings = _quality_warnings(payload)
            can_promote = not warnings or LOCAL_WELFARE_PROMOTE_WARNINGS
            status = "promoted" if can_promote else "held"
            _upsert_candidate(supabase, target, page, payload, warnings, status)
            candidates += 1

            if can_promote:
                supabase.table("welfare_services").upsert(payload, on_conflict="online_url").execute()
                report["promoted"].append(_report_snapshot(payload, warnings))
                promoted += 1
                if warnings:
                    print(f"✓ 후보/승격 경고={len(warnings)}")
                else:
                    print("✓ 후보/승격")
            else:
                report["held"].append(_report_snapshot(payload, warnings))
                held += 1
                print(f"□ 후보보류 경고={len(warnings)}")
        except Exception as exc:
            print(f"❌ {exc}")
            fail += 1
            report["failed"].append({
                "source_name": target["source_name"],
                "url": target["url"],
                "reason": "upsert_failed",
                "error": str(exc),
            })
        time.sleep(WEB_SCRAPE_DELAY)

    print(f"\n  지역 수집 완료: 후보={candidates}, 승격={promoted}, 보류={held}, 스킵={skip}, 실패={fail}, 429={quota}")
    report["finished_at"] = datetime.now(timezone.utc).isoformat()
    report["stats"] = {
        "candidates": candidates,
        "promoted": promoted,
        "held": held,
        "skipped": skip,
        "failed": fail,
        "quota": quota,
        "warnings": sum(len(item["warnings"]) for item in report["promoted"] + report["held"]),
    }
    _write_report(report)
    _print_report_summary(report)
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(run())
