#!/usr/bin/env python3
"""
Seed all nationwide sigungu entries into local_welfare_region_queue.

Rules:
- Keep existing rows untouched (status/priority/seed URLs remain)
- Insert missing sigungu rows as paused with empty seed_urls/seed_titles
"""

from __future__ import annotations

import json
import os
from typing import Any

import requests
from supabase import create_client


SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://dnnidnqwkjmbssxixpjg.supabase.co")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")
SIGUNGU_JSON_URL = (
    "https://raw.githubusercontent.com/2tle/korea-administrative-area-json/master/sigungu.json"
)


def _normalize_region(name: str) -> str:
    replacements = {
        "서울특별시": "서울",
        "부산광역시": "부산",
        "인천광역시": "인천",
        "대구광역시": "대구",
        "광주광역시": "광주",
        "대전광역시": "대전",
        "울산광역시": "울산",
        "세종특별자치시": "세종",
        "제주특별자치도": "제주",
        "경기도": "경기",
        "강원도": "강원",
        "충청북도": "충북",
        "충청남도": "충남",
        "전라북도": "전북",
        "전라남도": "전남",
        "경상북도": "경북",
        "경상남도": "경남",
    }
    return replacements.get(name, name)


def _load_sigungu_rows() -> list[dict[str, str]]:
    resp = requests.get(SIGUNGU_JSON_URL, timeout=30)
    resp.raise_for_status()
    payload = resp.json()
    rows: list[dict[str, str]] = []
    for item in payload.get("data", []):
        for region_full, districts in item.items():
            region = _normalize_region(region_full)
            if not districts:
                # 세종특별자치시처럼 하위 구분이 없는 경우
                rows.append({"region": region, "sub_region": f"{region}시"})
                continue
            for sub_region in districts:
                rows.append({"region": region, "sub_region": str(sub_region).strip()})
    return rows


def _fetch_existing_keys(supabase) -> set[tuple[str, str, str]]:
    keys: set[tuple[str, str, str]] = set()
    offset = 0
    page_size = 1000
    while True:
        data = (
            supabase.table("local_welfare_region_queue")
            .select("region,sub_region,area_detail")
            .range(offset, offset + page_size - 1)
            .execute()
            .data
            or []
        )
        if not data:
            break
        for row in data:
            keys.add(
                (
                    str(row.get("region") or "").strip(),
                    str(row.get("sub_region") or "").strip(),
                    str(row.get("area_detail") or "").strip(),
                )
            )
        if len(data) < page_size:
            break
        offset += page_size
    return keys


def _chunked(items: list[dict[str, Any]], size: int) -> list[list[dict[str, Any]]]:
    return [items[i : i + size] for i in range(0, len(items), size)]


def main() -> int:
    if not SUPABASE_SERVICE_KEY:
        print("SUPABASE_SERVICE_KEY is not set. Skip nationwide sigungu seed.")
        return 0

    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    existing = _fetch_existing_keys(supabase)
    sigungu_rows = _load_sigungu_rows()

    inserts: list[dict[str, Any]] = []
    priority = 5000
    for row in sigungu_rows:
        key = (row["region"], row["sub_region"], "")
        if key in existing:
            continue
        inserts.append(
            {
                "region": row["region"],
                "sub_region": row["sub_region"],
                "area_detail": "",
                "source_prefix": row["sub_region"],
                "seed_urls": [],
                "seed_titles": {},
                "status": "paused",
                "priority": priority,
            }
        )
        priority += 1

    if not inserts:
        print("Nationwide sigungu queue already seeded.")
        return 0

    for batch in _chunked(inserts, 200):
        supabase.table("local_welfare_region_queue").insert(batch).execute()

    print(f"Inserted nationwide sigungu rows: {len(inserts)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
