#!/usr/bin/env python3
"""
Apply selected SQL migration files using psql.

Requires:
- SUPABASE_DB_URL (Postgres connection string)
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = [
    ROOT / "supabase" / "migrations" / "20260427143000_create_local_welfare_region_queue.sql",
    ROOT / "supabase" / "migrations" / "20260427152000_seed_nationwide_region_queue.sql",
]


def _run_psql(db_url: str, sql_file: Path) -> None:
    if not sql_file.exists():
        raise FileNotFoundError(f"SQL file not found: {sql_file}")
    cmd = [
        "psql",
        db_url,
        "-v",
        "ON_ERROR_STOP=1",
        "-f",
        str(sql_file),
    ]
    subprocess.run(cmd, check=True)


def main() -> int:
    db_url = os.environ.get("SUPABASE_DB_URL", "").strip()
    if not db_url:
        print("SUPABASE_DB_URL is not set. Skip SQL migration apply.")
        return 0

    print("Applying SQL migrations for regional queue...")
    for sql_file in MIGRATIONS:
        print(f"- {sql_file.name}")
        _run_psql(db_url, sql_file)

    print("SQL migrations applied.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
