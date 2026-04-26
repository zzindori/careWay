#!/usr/bin/env python3
"""
CareWay local welfare crawler batch.

Runs separately from the national welfare API/AI classification pipeline.
"""

from __future__ import annotations

import os
import re
import time

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


def _infer_min_age(text: str) -> int | None:
    match = re.search(r"(?:만\s*)?(\d{2})\s*세\s*이상", text or "")
    if not match:
        return None
    age = int(match.group(1))
    return age if 0 < age < 120 else None


def _infer_income_level(text: str) -> int:
    if "기초생활수급" in text or "생계급여" in text or "의료급여" in text:
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
    if any(keyword in text for keyword in ["치매", "인지"]):
        tags.add("dementia")
    if any(keyword in text for keyword in ["방문요양", "일상생활", "가사", "식사"]):
        tags.add("daily_care")
    if any(keyword in text for keyword in ["식사", "도시락", "급식"]):
        tags.add("meal_support")
    if any(keyword in text for keyword in ["방문", "재가", "방문요양", "방문돌봄"]):
        tags.add("home_visit")
    if any(keyword in text for keyword in ["보청기", "청각"]):
        tags.add("hearing")
    if any(keyword in text for keyword in ["안경", "시각", "개안"]):
        tags.add("vision")
    if any(keyword in text for keyword in ["의료", "진료", "치료", "투약", "검진"]):
        tags.add("medical")
    if any(keyword in text for keyword in ["지원금", "수당", "급여", "바우처", "현금"]):
        tags.add("financial_support")
    if any(keyword in text for keyword in ["주거개선", "주택개조", "집수리"]):
        tags.add("housing_repair")
    if any(keyword in text for keyword in ["정신건강", "상담", "우울"]):
        tags.add("mental_health")
    if any(keyword in text for keyword in ["가족돌봄", "간병가족", "부양가족"]):
        tags.add("caregiver_support")
    return [tag for tag in tags if tag in ALLOWED_SERVICE_TAGS]


def _normalize_category(category: str, service_tags: list[str], text: str) -> str:
    if "medical" in service_tags or any(keyword in text for keyword in ["의료", "진료", "병원", "투약", "검진", "보청기", "안경", "치료"]):
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
        if any(keyword in line for keyword in ["방문", "주민센터", "시군구", "행정복지센터"]):
            method = "방문"
        elif any(keyword in line for keyword in ["온라인", "인터넷", "복지로", "홈페이지"]):
            method = "온라인"
        elif any(keyword in line for keyword in ["전화", "콜센터", "문의"]):
            method = "전화"
        methods.append({"method": method, "description": line})
    return methods


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


def _build_payload(target: dict, page: dict) -> dict | None:
    text = page.get("text", "")
    if not any(keyword in text for keyword in LOCAL_PILOT_KEYWORDS):
        return None
    if not _is_service_like(text):
        return None

    title = page.get("title") or target["source_name"]
    name = f"{target['sub_region']} {target['source_name']}".strip()
    region = target["region"]
    sub_region = target["sub_region"]
    area_detail = target.get("area_detail", "")
    source_text = " ".join(filter(None, [name, text, area_detail]))
    tags = _augment_service_tags(source_text)
    category = target.get("category") or _normalize_category("living", tags, source_text)
    target_age_group = target.get("target_age_group") or _infer_target_age_group(source_text)
    min_age = target.get("min_age") or _infer_min_age(source_text)
    max_income_level = _infer_income_level(source_text)
    phone = page.get("phone", "")
    apply_place = phone or target["source_name"]
    if area_detail:
        apply_place = f"{target['source_name']} ({area_detail})" + (f" / {phone}" if phone else "")

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
        "target_info": f"{region} {sub_region} {area_detail} 지역 주민 대상 안내".strip(),
        "benefit_info": text[:800],
        "apply_place": apply_place,
        "online_url": target["url"],
        "difficulty": 2,
        "is_renewable": True,
        "min_age": min_age,
        "max_income_level": max_income_level,
        "requires_ltc_grade": "장기요양" in source_text and ("등급" in source_text or "인정" in source_text),
        "requires_alone": "독거" in source_text or "홀몸" in source_text,
        "requires_basic_recipient": max_income_level == 1,
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
    print("=" * 60)
    print("  CareWay 지역 복지 수집 로봇")
    print("=" * 60)
    print("\n━━━ LOCAL CRAWLER: 지역 노인복지 파일럿 수집 ━━━")

    ok = skip = fail = quota = 0
    supabase.table("welfare_services").delete().eq("source", "local_site_pilot").execute()
    print("  기존 파일럿 데이터 정리 완료")

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
            continue
        if page.get("quota_exceeded"):
            print("⚠ 429 중단")
            quota += 1
            break

        payload = _build_payload(target, page)
        if not payload:
            print("↷ 복지 키워드 부족")
            skip += 1
            continue

        try:
            supabase.table("welfare_services").upsert(payload, on_conflict="online_url").execute()
            print("✓")
            ok += 1
        except Exception as exc:
            print(f"❌ {exc}")
            fail += 1
        time.sleep(WEB_SCRAPE_DELAY)

    print(f"\n  지역 수집 완료: 저장={ok}, 스킵={skip}, 실패={fail}, 429={quota}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(run())
