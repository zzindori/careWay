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

import requests
from bs4 import BeautifulSoup, Comment


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
    {
        "region": "경기",
        "sub_region": "용인시",
        "area_detail": "수지구",
        "source_name": "수지구 보건소 공지",
        "source_type": "public_health_center",
        "url": "https://www.yongin.go.kr/user/bbs/BD_selectBbs.do?q_bbsCode=1019&q_bbscttSn=20240503134345266&q_category=main&q_clCode=3",
        "focus_keywords": ["방문건강", "치매", "어르신", "노인"],
        "category": "medical",
    },
]

LOCAL_PILOT_KEYWORDS = [
    "노인", "어르신", "고령", "65세", "60세", "기초연금", "장기요양",
    "치매", "방문건강", "방문간호", "돌봄", "독거", "무료급식", "도시락",
    "보건소", "복지관", "행정복지센터", "주민센터", "수지구", "괴산군",
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


def _parse_local_html(target: dict[str, Any], html: str) -> dict[str, Any] | None:
    html = _strip_noise_html(html)
    title = _extract_html_title(html, target["source_name"])
    full_text = _extract_main_text(target, html)
    text = _focus_local_text(target, full_text)
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
            page.goto(target["url"], wait_until="domcontentloaded", timeout=30000)
            html = page.content()
            browser.close()
        return _parse_local_html(target, html)
    except Exception as exc:
        print(f"  ⚠ 브라우저 fallback 실패 ({target['source_name']}): {exc}")
        return None


def fetch_local_pilot_page(target: dict[str, Any]) -> dict[str, Any] | None:
    try:
        response = requests.get(target["url"], headers=WEB_HEADERS, timeout=20)
        if response.status_code == 429:
            return {"quota_exceeded": True}
        response.raise_for_status()
        response.encoding = response.apparent_encoding or response.encoding
        return _parse_local_html(target, response.text)
    except Exception as exc:
        print(f"  ⚠ 파일럿 페이지 수집 실패 ({target['source_name']}): {exc}")
        return _fetch_with_browser(target)
