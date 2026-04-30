#!/usr/bin/env python3
"""
Auto-enrich missing seed_urls in local_welfare_region_queue.

Strategy:
- Target rows with empty seed_urls
- Search web results (Korean query by sub_region + welfare terms)
- Pick best reachable official/go.kr-like URL
- Upsert seed_urls/seed_titles and move paused -> pending
"""

from __future__ import annotations

import os
import time
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

import requests
from bs4 import BeautifulSoup
from supabase import create_client


SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://dnnidnqwkjmbssxixpjg.supabase.co")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")
ENRICH_LIMIT = int(os.environ.get("LOCAL_WELFARE_SEED_ENRICH_LIMIT", "40"))
ENRICH_SLEEP_SECONDS = float(os.environ.get("LOCAL_WELFARE_SEED_ENRICH_SLEEP_SECONDS", "0.4"))
REQUEST_TIMEOUT_SECONDS = 12
ENRICH_MAX_SECONDS = int(os.environ.get("LOCAL_WELFARE_SEED_ENRICH_MAX_SECONDS", "180"))

WEB_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7",
}

SEARCH_TERMS = [
    "{sub_region} 노인복지",
    "{sub_region} 복지",
    "{sub_region} 시청",
    "{sub_region} 군청",
    "{sub_region} 구청",
]

# High-confidence manual fallback for frequently blocked/poorly indexed regions.
# Used only when web search candidates are empty or invalid.
MANUAL_SEED_URLS: dict[str, str] = {
    "용산구": "https://www.yongsan.go.kr",
    "성동구": "https://www.sd.go.kr",
    "광진구": "https://www.gwangjin.go.kr",
    "동대문구": "https://www.ddm.go.kr",
    "중랑구": "https://www.jungnang.go.kr",
    "성북구": "https://www.sb.go.kr",
    "도봉구": "https://www.dobong.go.kr",
    "노원구": "https://www.nowon.kr",
    "은평구": "https://www.ep.go.kr",
    "서대문구": "https://www.sdm.go.kr",
    "마포구": "https://www.mapo.go.kr",
    "양천구": "https://www.yangcheon.go.kr",
    "강서구": "https://www.gangseo.seoul.kr",
    "구로구": "https://www.guro.go.kr",
    "금천구": "https://www.geumcheon.go.kr",
    "영등포구": "https://www.ydp.go.kr",
    "동작구": "https://www.dongjak.go.kr",
    "관악구": "https://www.gwanak.go.kr",
    "서초구": "https://www.seocho.go.kr",
}


def _fetch_missing_seed_rows(supabase) -> list[dict[str, Any]]:
    rows = (
        supabase.table("local_welfare_region_queue")
        .select("id,region,sub_region,status,seed_urls")
        .or_("seed_urls.eq.[],seed_urls.is.null")
        .order("priority", desc=False)
        .order("id", desc=False)
        .limit(max(1, ENRICH_LIMIT))
        .execute()
        .data
        or []
    )
    return rows


def _extract_search_result_urls(html: str) -> list[str]:
    soup = BeautifulSoup(html, "html.parser")
    urls: list[str] = []
    for a in soup.select("a[href]"):
        href = (a.get("href") or "").strip()
        if not href:
            continue
        if "uddg=" in href:
            parsed = urlparse(href)
            uddg = parse_qs(parsed.query).get("uddg", [""])[0]
            href = unquote(uddg) if uddg else href
        if href.startswith("//"):
            href = f"https:{href}"
        if href.startswith("http://") or href.startswith("https://"):
            host = (urlparse(href).netloc or "").lower()
            if any(
                bad in host
                for bad in [
                    "duckduckgo.com",
                    "youtube.com",
                    "facebook.com",
                    "instagram.com",
                ]
            ):
                continue
            urls.append(href)
    # preserve order, dedupe
    deduped: list[str] = []
    seen: set[str] = set()
    for u in urls:
        key = u.rstrip("/")
        if key in seen:
            continue
        seen.add(key)
        deduped.append(u)
    return deduped


def _search_candidate_urls(sub_region: str) -> list[str]:
    candidates: list[str] = []
    for template in SEARCH_TERMS:
        query = template.format(sub_region=sub_region)
        try:
            resp = requests.get(
                "https://duckduckgo.com/html/",
                params={"q": query},
                headers=WEB_HEADERS,
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            resp.raise_for_status()
        except Exception:
            continue
        candidates.extend(_extract_search_result_urls(resp.text))
        time.sleep(ENRICH_SLEEP_SECONDS)
    # ordered unique
    out: list[str] = []
    seen: set[str] = set()
    for u in candidates:
        key = u.rstrip("/")
        if key in seen:
            continue
        seen.add(key)
        out.append(u)
    return out


def _score_candidate(url: str, sub_region: str) -> int:
    p = urlparse(url)
    compact = f"{p.netloc}{p.path}".lower()
    score = 0
    if p.scheme == "https":
        score += 10
    if compact.endswith(".go.kr") or ".go.kr" in compact:
        score += 40
    if any(token in compact for token in ["welfare", "bokji", "senior", "elfare"]):
        score += 30
    if any(token in compact for token in ["city", "gu", "gun", "si"]):
        score += 10
    if sub_region.replace(" ", "").lower() in compact:
        score += 15
    if any(ext in compact for ext in [".pdf", ".hwp", ".hwpx", ".zip"]):
        score -= 80
    return score


def _pick_best_url(sub_region: str, urls: list[str]) -> str | None:
    ranked = sorted(urls, key=lambda u: _score_candidate(u, sub_region), reverse=True)
    for url in ranked[:12]:
        try:
            resp = requests.get(url, headers=WEB_HEADERS, timeout=REQUEST_TIMEOUT_SECONDS, allow_redirects=True)
            ctype = (resp.headers.get("content-type") or "").lower()
            if resp.status_code >= 400:
                continue
            if "text/html" not in ctype and "application/xhtml+xml" not in ctype:
                continue
            return resp.url
        except Exception:
            continue
    return None


def _validate_html_url(url: str) -> str | None:
    try:
        resp = requests.get(url, headers=WEB_HEADERS, timeout=REQUEST_TIMEOUT_SECONDS, allow_redirects=True)
        ctype = (resp.headers.get("content-type") or "").lower()
        if resp.status_code >= 400:
            return None
        if "text/html" not in ctype and "application/xhtml+xml" not in ctype:
            return None
        return resp.url
    except Exception:
        return None


def main() -> int:
    if not SUPABASE_SERVICE_KEY:
        print("SUPABASE_SERVICE_KEY is not set. Skip seed URL enrichment.")
        return 0

    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    rows = _fetch_missing_seed_rows(supabase)
    if not rows:
        print("No missing seed_urls rows found.")
        return 0

    started_at = time.monotonic()
    updated = 0
    for row in rows:
        if (time.monotonic() - started_at) >= ENRICH_MAX_SECONDS:
            print("Seed URL enrichment time budget reached. Stop this run and continue next schedule.")
            break
        sub_region = str(row.get("sub_region") or "").strip()
        if not sub_region:
            continue
        urls = _search_candidate_urls(sub_region)
        best = _pick_best_url(sub_region, urls)
        if not best:
            manual = MANUAL_SEED_URLS.get(sub_region)
            if manual:
                best = _validate_html_url(manual)
        if not best:
            print(f"Seed URL not found: {sub_region}")
            continue

        payload = {
            "seed_urls": [best],
            "seed_titles": {best: f"{sub_region} 홈페이지"},
        }
        if str(row.get("status") or "") == "paused":
            payload["status"] = "pending"

        (
            supabase.table("local_welfare_region_queue")
            .update(payload)
            .eq("id", row["id"])
            .execute()
        )
        updated += 1
        print(f"Seed URL enriched: {sub_region} -> {best}")

    print(f"Seed URL enrichment complete: updated={updated}, checked={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
