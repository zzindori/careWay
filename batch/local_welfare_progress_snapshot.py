#!/usr/bin/env python3
"""
Build a compact progress snapshot for nationwide local welfare rollout.
"""

from __future__ import annotations

import json
import os
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from supabase import create_client


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "batch" / "output" / "local_welfare_progress.json"

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://dnnidnqwkjmbssxixpjg.supabase.co")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")


def _fetch_all(table, select_cols: str, page_size: int = 1000) -> list[dict]:
    rows: list[dict] = []
    offset = 0
    while True:
        page = (
            table.select(select_cols)
            .range(offset, offset + page_size - 1)
            .execute()
            .data
            or []
        )
        if not page:
            break
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return rows


def main() -> int:
    snapshot = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "queue": {},
        "candidates": {},
        "top_failure_reasons": [],
        "note": "",
    }

    if not SUPABASE_SERVICE_KEY:
        snapshot["note"] = "SUPABASE_SERVICE_KEY is not set."
        OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT_PATH.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Progress snapshot saved: {OUTPUT_PATH}")
        return 0

    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    queue_rows = _fetch_all(
        supabase.table("local_welfare_region_queue"),
        "id,status,seed_urls",
    )
    total_regions = len(queue_rows)
    with_seed_urls = 0
    status_counter: Counter[str] = Counter()
    for row in queue_rows:
        status_counter[str(row.get("status") or "unknown")] += 1
        seed_urls = row.get("seed_urls") or []
        if isinstance(seed_urls, list) and len(seed_urls) > 0:
            with_seed_urls += 1

    candidate_rows = _fetch_all(
        supabase.table("local_welfare_candidates"),
        "status,failure_reason",
    )
    candidate_status_counter: Counter[str] = Counter()
    failure_counter: Counter[str] = Counter()
    for row in candidate_rows:
        candidate_status_counter[str(row.get("status") or "unknown")] += 1
        reason = str(row.get("failure_reason") or "").strip()
        if reason:
            failure_counter[reason] += 1

    snapshot["queue"] = {
        "total_regions": total_regions,
        "with_seed_urls": with_seed_urls,
        "without_seed_urls": max(0, total_regions - with_seed_urls),
        "seed_coverage_percent": round((with_seed_urls / total_regions) * 100, 2) if total_regions else 0.0,
        "active": status_counter.get("active", 0),
        "pending": status_counter.get("pending", 0),
        "paused": status_counter.get("paused", 0),
        "done": status_counter.get("done", 0),
    }
    snapshot["candidates"] = {
        "total_rows": len(candidate_rows),
        "promoted": candidate_status_counter.get("promoted", 0),
        "held": candidate_status_counter.get("held", 0),
        "skipped": candidate_status_counter.get("skipped", 0),
        "failed": candidate_status_counter.get("failed", 0),
    }
    snapshot["top_failure_reasons"] = [
        {"reason": reason, "count": count}
        for reason, count in failure_counter.most_common(10)
    ]

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Progress snapshot saved: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
