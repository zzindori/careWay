#!/usr/bin/env python3
"""
Local welfare crawler for municipal welfare pages.

This module owns web fetching and content extraction only. The main batch script
keeps database writes and app-specific welfare payload mapping.
"""

from __future__ import annotations

import html as html_lib
import re
from typing import Any
from urllib.parse import parse_qs, urljoin, urlparse

import requests
from bs4 import BeautifulSoup, Comment

REQUEST_TIMEOUT_SECONDS = 10
BROWSER_TIMEOUT_MS = 15000


WEB_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7",
    "Accept-Encoding": "gzip, deflate, br",
    "Connection": "keep-alive",
}

PILOT_LOCAL_TARGETS = [
    {
        "region": "충북",
        "sub_region": "괴산군",
        "area_detail": "",
        "source_name": "괴산군 노인일자리",
        "source_type": "district_welfare",
        "url": "https://www.goesan.go.kr/welfare/contents.do?key=312",
        "focus_keywords": ["노인일자리확대지원", "참여대상", "지원근거"],
        "category": "finance",
        "target_age_group": "elderly",
        "min_age": 65,
    },
]

LOCAL_PILOT_KEYWORDS = [
    "노인", "어르신", "고령", "65세", "60세", "기초연금", "장기요양",
    "치매", "방문건강", "방문간호", "돌봄", "독거", "무료급식", "도시락",
    "보건소", "복지관", "행정복지센터", "주민센터", "수지구", "괴산군",
    "장애인", "특별공급", "복지사각지대", "취약계층",
]

SUJI_DONG_NAMES = [
    "풍덕천1동",
    "풍덕천2동",
    "신봉동",
    "죽전1동",
    "죽전2동",
    "죽전3동",
    "동천동",
    "상현1동",
    "상현2동",
    "상현3동",
    "성복동",
]

SUJI_DISCOVERY_SEEDS = [
    "https://www.sujigu.go.kr/index.asp",
    "https://www.sujigu.go.kr/lmth/03com02.asp",
]

SUJI_DISCOVERY_KEYWORDS = [
    "노인",
    "어르신",
    "기초연금",
    "장애인",
    "특별공급",
    "돌봄",
    "복지",
    "취약계층",
    "복지사각지대",
    "일자리",
    "무료급식",
    "이웃돕기",
]

ELDERLY_DISCOVERY_KEYWORDS = [
    "노인복지",
    "어르신",
    "노인",
    "기초연금",
    "노인일자리",
    "노인맞춤돌봄",
    "독거노인",
    "치매",
    "치매안심센터",
    "방문건강",
    "방문간호",
    "경로당",
    "무료급식",
    "도시락",
    "노인복지관",
    "시니어클럽",
    "대한노인회",
    "실버케어",
]

ELDERLY_EXCLUDE_KEYWORDS = [
    "채용",
    "입찰",
    "문화행사",
    "사진관",
    "홍보관",
    "주민등록",
    "장애인 특별공급",
    "청소년",
    "아동",
    "어린이",
    "문화강좌",
    "주민자치센터",
    "강좌",
    "교육신청",
]

REGION_ELDERLY_SOURCES = [
    {
        "region": "경기",
        "sub_region": "용인시",
        "area_detail": "",
        "source_prefix": "용인시",
        "seed_urls": [
            "https://www.yongin.go.kr/home/job/yiJobInfo/oldJob.jsp",
            "https://www.yongin.go.kr/home/www/www18/www18_02/www18_02_01.jsp",
            "https://www.yongin.go.kr/home/www/www18/www18_02/www18_02_04/www18_02_04_04.jsp",
        ],
        "seed_titles": {
            "https://www.yongin.go.kr/home/job/yiJobInfo/oldJob.jsp": "노인일자리",
            "https://www.yongin.go.kr/home/www/www18/www18_02/www18_02_01.jsp": "기초연금",
            "https://www.yongin.go.kr/home/www/www18/www18_02/www18_02_04/www18_02_04_04.jsp": "용인실버케어순이",
        },
    },
    {
        "region": "서울",
        "sub_region": "노원구",
        "area_detail": "",
        "source_prefix": "노원구",
        "seed_urls": [
            "https://www.nowonbokjisaem.co.kr/------------/---------------------/%ea%b8%b0%ec%b4%88%ec%97%b0%ea%b8%88/",
            "https://www.nowonbokjisaem.co.kr/agency/%eb%85%b8%ec%9b%90%ec%8b%9c%eb%8b%88%ec%96%b4%ed%81%b4%eb%9f%bd/",
            "https://www.nowonbokjisaem.co.kr/department/%eb%85%b8%ec%9b%90%ea%b5%ac%ec%b2%ad-%ea%b3%a0%eb%a0%b9%ec%82%ac%ed%9a%8c%ec%a0%95%ec%b1%85%ea%b3%bc/",
        ],
        "seed_titles": {
            "https://www.nowonbokjisaem.co.kr/------------/---------------------/%ea%b8%b0%ec%b4%88%ec%97%b0%ea%b8%88/": "기초연금",
            "https://www.nowonbokjisaem.co.kr/agency/%eb%85%b8%ec%9b%90%ec%8b%9c%eb%8b%88%ec%96%b4%ed%81%b4%eb%9f%bd/": "노원시니어클럽",
            "https://www.nowonbokjisaem.co.kr/department/%eb%85%b8%ec%9b%90%ea%b5%ac%ec%b2%ad-%ea%b3%a0%eb%a0%b9%ec%82%ac%ed%9a%8c%ec%a0%95%ec%b1%85%ea%b3%bc/": "노원구청 고령사회정책과",
        },
    },
]


def strip_html(text: str) -> str:
    if not text:
        return ""
    text = html_lib.unescape(text)
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("\xa0", " ").replace("\u200b", "")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _strip_noise_html(html: str) -> str:
    html = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", html)
    html = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", html)
    html = re.sub(r"(?is)<noscript[^>]*>.*?</noscript>", " ", html)
    return html


NOISE_ATTR_RE = re.compile(
    r"(?:^|[_-])(gnb|lnb|nav|menu|sitemap|footer|header|quick|search|login|family|breadcrumb|location|aside|side|sns|share|popup|banner|weather|top|bottom)(?:$|[_-])",
    re.IGNORECASE,
)

CONTENT_ATTR_RE = re.compile(
    r"(content|contents|container|article|board|bbs|view|detail|body|main|substance|program)",
    re.IGNORECASE,
)

DETAIL_MARKERS = [
    "지원근거",
    "참여대상",
    "사업내용",
    "지원내용",
    "신청방법",
    "문의",
    "담당부서",
    "상세내용",
]

NOISE_WORDS = [
    "사이트맵",
    "전체메뉴",
    "로그인",
    "회원가입",
    "화면크기",
    "통합검색",
    "패밀리사이트",
    "연관사이트",
    "본문 바로가기",
    "대메뉴 바로가기",
    "인기검색어",
    "개인정보",
    "정보공개",
    "민원안내",
]


def _extract_html_title(html: str, fallback: str) -> str:
    for pattern in [
        r"(?is)<h1[^>]*>(.*?)</h1>",
        r"(?is)<h2[^>]*>(.*?)</h2>",
        r"(?is)<title[^>]*>(.*?)</title>",
    ]:
        match = re.search(pattern, html)
        if not match:
            continue
        title = strip_html(match.group(1))
        title = re.sub(r"\s+", " ", title).strip(" -|")
        if title:
            return title[:80]
    return fallback


def _extract_first_phone(text: str) -> str:
    match = re.search(r"(?:0\d{1,2})-\d{3,4}-\d{4}", text or "")
    return match.group(0) if match else ""


def _fetch_html(url: str) -> str:
    try:
        response = requests.get(url, headers=WEB_HEADERS, timeout=REQUEST_TIMEOUT_SECONDS)
        response.raise_for_status()
        response.encoding = response.apparent_encoding or response.encoding
        return response.text
    except Exception:
        return _fetch_html_with_browser(url)


def _fetch_html_with_browser(url: str) -> str:
    from playwright.sync_api import sync_playwright

    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage"],
        )
        context = browser.new_context(
            user_agent=WEB_HEADERS.get("User-Agent"),
            ignore_https_errors=True,
        )
        page = context.new_page()
        page.goto(url, wait_until="domcontentloaded", timeout=BROWSER_TIMEOUT_MS)
        html = page.content()
        browser.close()
    return html


def _is_allowed_suji_url(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        return False
    if parsed.netloc and not parsed.netloc.endswith("sujigu.go.kr"):
        return False
    # 동 행정복지센터 소개 페이지는 서비스가 아니므로, 우선 동소식 상세 글만 후보화한다.
    return parsed.path.endswith("/lmth/03com02.asp") and "no=" in parsed.query


def _is_allowed_discovery_url(url: str, seed_url: str) -> bool:
    parsed = urlparse(url)
    seed = urlparse(seed_url)
    if parsed.scheme not in {"http", "https"}:
        return False
    if parsed.netloc and seed.netloc and parsed.netloc != seed.netloc:
        return False
    if parsed.query.startswith("s=") or "/?s=" in url:
        return False
    if any(parsed.path.lower().endswith(ext) for ext in [".jpg", ".jpeg", ".png", ".gif", ".pdf", ".hwp", ".hwpx", ".zip"]):
        return False
    return True


def _url_key(url: str) -> str:
    parsed = urlparse(url)
    return f"{parsed.netloc}{parsed.path}?{parsed.query}".rstrip("?")


def _suji_url_key(url: str) -> str:
    parsed = urlparse(url)
    no = parse_qs(parsed.query).get("no", [""])[0]
    return f"{parsed.path}?no={no}" if no else url


def _extract_dong_name(text: str) -> str:
    for dong in SUJI_DONG_NAMES:
        if dong in text:
            return dong
    return "수지구"


def _discovery_score(text: str, href: str) -> int:
    compact = f"{text} {href}"
    score = 0
    if any(dong in compact for dong in SUJI_DONG_NAMES):
        score += 30
    score += sum(20 for keyword in SUJI_DISCOVERY_KEYWORDS if keyword in compact)
    if "동소식" in compact:
        score += 10
    if "03com02" in href:
        score += 10
    if any(noise in compact for noise in ["주민자치센터", "문화행사", "제설활동", "강좌"]):
        score -= 30
    return score


def _elderly_discovery_score(text: str, href: str) -> int:
    compact = f"{text} {href}"
    score = 0
    score += sum(30 for keyword in ELDERLY_DISCOVERY_KEYWORDS if keyword in compact)
    score += sum(20 for marker in DETAIL_MARKERS if marker in compact)
    if any(keyword in compact for keyword in ["www18_02", "oldJob", "nowonbokjisaem", "agency", "department"]):
        score += 15
    score -= sum(40 for keyword in ELDERLY_EXCLUDE_KEYWORDS if keyword in compact)
    return score


def _infer_discovered_category(text: str) -> str:
    if any(keyword in text for keyword in ["기초연금", "노인일자리", "수당", "급여", "활동비", "일자리"]):
        return "finance"
    if any(keyword in text for keyword in ["치매", "방문건강", "방문간호", "보건", "검진"]):
        return "medical"
    if any(keyword in text for keyword in ["돌봄", "맞춤돌봄", "독거노인", "실버케어"]):
        return "care"
    if any(keyword in text for keyword in ["경로당", "무료급식", "도시락"]):
        return "living"
    return "living"


def _make_elderly_target(source: dict[str, Any], url: str, title: str) -> dict[str, Any]:
    title = _normalize_text(title) or source["source_prefix"]
    focus_keywords = [keyword for keyword in ELDERLY_DISCOVERY_KEYWORDS if keyword in title]
    focus_keywords.extend(["지원대상", "신청방법", "지원내용", "문의", "담당부서"])
    text_for_category = f"{title} {url}"
    return {
        "region": source["region"],
        "sub_region": source["sub_region"],
        "area_detail": source.get("area_detail", ""),
        "source_name": f"{source['source_prefix']} {title[:60]}",
        "source_type": "elderly_discovery",
        "url": url,
        "focus_keywords": list(dict.fromkeys(focus_keywords)),
        "category": _infer_discovered_category(text_for_category),
        "target_age_group": "elderly",
        "min_age": 65 if any(keyword in text_for_category for keyword in ["기초연금", "65세", "노인", "어르신"]) else None,
    }


def discover_elderly_region_targets(limit_per_region: int = 8) -> list[dict[str, Any]]:
    discovered: list[dict[str, Any]] = []
    seen_urls: set[str] = set()

    for source in REGION_ELDERLY_SOURCES:
        candidates: list[tuple[int, dict[str, Any]]] = []
        for seed_url in source["seed_urls"]:
            try:
                html = _fetch_html(seed_url)
                soup = BeautifulSoup(html, "html.parser")
            except Exception as exc:
                print(f"  ⚠ 노인복지 후보 탐색 실패 ({seed_url}): {exc}")
                continue

            seed_title = source.get("seed_titles", {}).get(seed_url) or _extract_html_title(html, source["source_prefix"])
            seed_text = _normalize_text(soup.get_text(" ", strip=True))[:4000]
            seed_score = _elderly_discovery_score(f"{seed_title} {seed_text}", seed_url)
            if seed_score >= 40:
                key = _url_key(seed_url)
                if key not in seen_urls:
                    seen_urls.add(key)
                    candidates.append((seed_score, _make_elderly_target(source, seed_url, seed_title)))

            for anchor in soup.find_all("a"):
                title = _normalize_text(anchor.get_text(" ", strip=True))
                href = anchor.get("href") or ""
                if not title or not href:
                    continue
                url = urljoin(seed_url, href)
                key = _url_key(url)
                if key in seen_urls or not _is_allowed_discovery_url(url, seed_url):
                    continue
                score = _elderly_discovery_score(title, url)
                if score < 50:
                    continue
                seen_urls.add(key)
                candidates.append((score, _make_elderly_target(source, url, title)))

        candidates.sort(key=lambda item: item[0], reverse=True)
        discovered.extend(target for _, target in candidates[:limit_per_region])
    return discovered


def discover_suji_dong_targets(limit: int = 12) -> list[dict[str, Any]]:
    candidates: list[tuple[int, dict[str, Any]]] = []
    seen_urls: set[str] = set()

    for seed in SUJI_DISCOVERY_SEEDS:
        try:
            soup = BeautifulSoup(_fetch_html(seed), "html.parser")
        except Exception as exc:
            print(f"  ⚠ 수지구 동소식 탐색 실패 ({seed}): {exc}")
            continue

        for anchor in soup.find_all("a"):
            title = _normalize_text(anchor.get_text(" ", strip=True))
            href = anchor.get("href") or ""
            if not title or not href:
                continue
            url = urljoin(seed, href)
            key = _suji_url_key(url)
            if key in seen_urls or not _is_allowed_suji_url(url):
                continue
            score = _discovery_score(title, url)
            if score < 40:
                continue

            dong = _extract_dong_name(title)
            focus_keywords = [keyword for keyword in SUJI_DISCOVERY_KEYWORDS if keyword in title]
            if dong != "수지구":
                focus_keywords.insert(0, dong)
            focus_keywords.extend(["지원", "신청", "대상", "문의"])
            target = {
                "region": "경기",
                "sub_region": "용인시",
                "area_detail": dong,
                "source_name": f"{dong} {title[:60]}",
                "source_type": "dong_notice",
                "url": url,
                "focus_keywords": list(dict.fromkeys(focus_keywords)),
                "category": "living",
            }
            seen_urls.add(key)
            candidates.append((score, target))

    candidates.sort(key=lambda item: item[0], reverse=True)
    return [target for _, target in candidates[:limit]]


def _attr_text(node) -> str:
    if not getattr(node, "attrs", None):
        return ""
    values: list[str] = []
    for key in ("id", "class", "role", "name"):
        value = node.get(key)
        if isinstance(value, list):
            values.extend(str(item) for item in value)
        elif value:
            values.append(str(value))
    return " ".join(values)


def _normalize_text(text: str) -> str:
    text = html_lib.unescape(text or "")
    text = text.replace("\xa0", " ").replace("\u200b", "")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def _node_text(node) -> str:
    return _normalize_text(node.get_text(" ", strip=True))


def _prepare_soup(html: str) -> BeautifulSoup:
    soup = BeautifulSoup(html, "html.parser")
    for comment in soup.find_all(string=lambda value: isinstance(value, Comment)):
        comment.extract()
    for tag in soup(["script", "style", "noscript", "svg", "iframe", "header", "footer", "nav", "aside", "form", "select", "button"]):
        tag.decompose()
    for tag in list(soup.find_all(True)):
        attrs = _attr_text(tag)
        if attrs and NOISE_ATTR_RE.search(attrs) and not CONTENT_ATTR_RE.search(attrs):
            tag.decompose()
    return soup


def _candidate_nodes(soup: BeautifulSoup) -> list:
    selectors = [
        "main",
        "article",
        "[role='main']",
        "#content",
        "#contents",
        "#container",
        ".content",
        ".contents",
        ".substance",
        ".board_view",
        ".bbs_view",
        ".view",
        ".view_cont",
        ".viewContent",
        ".detail",
        ".article",
    ]
    candidates = []
    seen = set()
    for selector in selectors:
        for node in soup.select(selector):
            identity = id(node)
            if identity not in seen:
                seen.add(identity)
                candidates.append(node)
    for node in soup.find_all(["section", "div"]):
        attrs = _attr_text(node)
        if CONTENT_ATTR_RE.search(attrs or ""):
            identity = id(node)
            if identity not in seen:
                seen.add(identity)
                candidates.append(node)
    if soup.body:
        candidates.append(soup.body)
    return candidates


def _score_candidate(text: str, target: dict[str, Any]) -> int:
    if len(text) < 80:
        return -1000
    keywords = [keyword for keyword in target.get("focus_keywords", []) if keyword]
    keyword_score = sum(text.count(keyword) for keyword in keywords) * 30
    marker_score = sum(text.count(marker) for marker in DETAIL_MARKERS) * 60
    welfare_score = sum(text.count(keyword) for keyword in LOCAL_PILOT_KEYWORDS) * 8
    noise_score = sum(text.count(word) for word in NOISE_WORDS) * 35
    length_score = min(len(text), 4000) // 120
    return keyword_score + marker_score + welfare_score + length_score - noise_score


def _extract_main_text(target: dict[str, Any], html: str) -> str:
    soup = _prepare_soup(html)
    scored: list[tuple[int, int, str]] = []
    for node in _candidate_nodes(soup):
        text = _node_text(node)
        if not text:
            continue
        scored.append((_score_candidate(text, target), len(text), text))
    if not scored:
        return strip_html(html)
    scored.sort(key=lambda item: (item[0], -abs(item[1] - 1800)), reverse=True)
    return scored[0][2]


def _focus_local_text(target: dict[str, Any], text: str) -> str:
    text = re.sub(r"\s+", " ", text or "").strip()
    if not text:
        return ""

    keywords = [keyword for keyword in target.get("focus_keywords", []) if keyword]
    priority_markers = DETAIL_MARKERS + keywords
    positions = [text.find(keyword) for keyword in priority_markers if text.find(keyword) >= 0]
    if not positions:
        return text[:2500]

    start = max(0, min(positions) - 120)
    focused = text[start:start + 2500].strip()

    for marker in keywords + ["지원근거", "참여대상", "사업내용", "신청", "문의"]:
        index = focused.find(marker)
        if index > 0:
            focused = focused[index:].strip()
            break
    return focused


def _clean_local_text(text: str) -> str:
    text = re.split(r"현재 페이지에서 제공하는 정보에 만족하십니까", text or "", maxsplit=1)[0]
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def _clean_local_title(title: str, fallback: str) -> str:
    generic_titles = [
        "site map",
        "YONGIN SPECIAL CITY 용인특례시",
        "노원복지소식",
        "괴산군청 분야별정보복지",
    ]
    return fallback if title in generic_titles else title


def _parse_local_html(target: dict[str, Any], html: str) -> dict[str, Any] | None:
    html = _strip_noise_html(html)
    title = _clean_local_title(_extract_html_title(html, target["source_name"]), target["source_name"])
    full_text = _extract_main_text(target, html)
    text = _clean_local_text(_focus_local_text(target, full_text))
    if not text:
        return None
    return {
        "title": title,
        "text": text[:5000],
        "phone": _extract_first_phone(text),
    }


def _fetch_with_browser(target: dict[str, Any]) -> dict[str, Any] | None:
    try:
        from playwright.sync_api import sync_playwright

        with sync_playwright() as pw:
            browser = pw.chromium.launch(
                headless=True,
                args=["--no-sandbox", "--disable-dev-shm-usage"],
            )
            context = browser.new_context(
                user_agent=WEB_HEADERS.get("User-Agent"),
                ignore_https_errors=True,
            )
            page = context.new_page()
            page.goto(target["url"], wait_until="domcontentloaded", timeout=BROWSER_TIMEOUT_MS)
            html = page.content()
            browser.close()
        return _parse_local_html(target, html)
    except Exception as exc:
        print(f"  ⚠ 브라우저 fallback 실패 ({target['source_name']}): {exc}")
        return None


def fetch_local_pilot_page(target: dict[str, Any]) -> dict[str, Any] | None:
    try:
        response = requests.get(target["url"], headers=WEB_HEADERS, timeout=REQUEST_TIMEOUT_SECONDS)
        if response.status_code == 429:
            return {"quota_exceeded": True}
        response.raise_for_status()
        response.encoding = response.apparent_encoding or response.encoding
        return _parse_local_html(target, response.text)
    except Exception as exc:
        page = _fetch_with_browser(target)
        if page:
            return page
        print(f"  ⚠ 파일럿 페이지 수집 실패 ({target['source_name']}): {exc}")
        return None
