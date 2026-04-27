#!/usr/bin/env python3
"""
Advance local welfare region queue when latest run is healthy.
"""

from __future__ import annotations

import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT_PATH = ROOT / "batch" / "output" / "local_welfare_report.json"
QUEUE_PATH = ROOT / "batch" / "config" / "local_welfare_region_queue.json"


def _load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _is_healthy(report: dict) -> bool:
    stats = report.get("stats") or {}
    held = int(stats.get("held") or 0)
    warnings = int(stats.get("warnings") or 0)
    candidates = int(stats.get("candidates") or 0)
    failed_items = list(report.get("failed") or [])
    # 탐색성 URL의 일시적 접근 실패(fetch_failed)는 큐 확장을 막지 않는다.
    hard_failed = [
        item for item in failed_items
        if str(item.get("reason") or "") != "fetch_failed"
    ]
    return len(hard_failed) == 0 and held == 0 and warnings == 0 and candidates > 0


def main() -> int:
    auto_advance = os.environ.get("LOCAL_WELFARE_AUTO_ADVANCE_QUEUE", "true").lower() in {
        "1",
        "true",
        "yes",
    }
    if not auto_advance:
        print("Queue auto-advance disabled by LOCAL_WELFARE_AUTO_ADVANCE_QUEUE.")
        return 0

    report = _load_json(REPORT_PATH)
    if not report:
        print("No report found, skip queue advance.")
        return 0

    if not _is_healthy(report):
        print("Run is not healthy enough to advance queue.")
        return 0

    queue = _load_json(QUEUE_PATH)
    active = list(queue.get("active") or [])
    pending = list(queue.get("pending") or [])
    completed = list(queue.get("completed") or [])

    if not pending:
        print("No pending regions.")
        return 0

    next_region = pending.pop(0)
    active.append(next_region)
    completed.append(
        {
            "region": next_region.get("region", ""),
            "sub_region": next_region.get("sub_region", ""),
            "source_prefix": next_region.get("source_prefix", ""),
            "activated_by_report_started_at": report.get("started_at", ""),
            "activated_by_report_finished_at": report.get("finished_at", ""),
        }
    )

    new_queue = {
        "active": active,
        "pending": pending,
        "completed": completed,
    }
    QUEUE_PATH.write_text(
        json.dumps(new_queue, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Advanced region queue: {next_region.get('source_prefix', 'unknown')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
