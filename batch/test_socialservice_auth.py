#!/usr/bin/env python3
"""
한국사회보장정보원 api.socialservice.or.kr:444 — 인증키 1개만 넣으면
URL 인코딩/디코딩 변형을 자동으로 만들어 호출 방식을 전부 시험한다.

PowerShell:
  $env:SOCIAL_SERVICE_API_KEY = "포털에서 복사한 키 (Encoding 또는 Decoding 아무거나)"
  python batch/test_socialservice_auth.py

또는:
  python batch/test_socialservice_auth.py --key "한 줄 붙여넣기"

키는 커밋하지 말 것.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
import urllib.parse

import requests

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

BASE = "https://api.socialservice.or.kr:444/api/service/common/serviceType"
SERVICE_TYPE_CODE = "8000"
SERVICE_TYPE_NAME = "장애아동가족지원"
TIMEOUT = 15


def _snippet(text: str, n: int = 400) -> str:
    t = text.replace("\n", " ").strip()
    return t if len(t) <= n else t[:n] + "..."


def _parse_result(xml: str) -> tuple[str, str]:
    import re

    m1 = re.search(r"<resultCode>([^<]+)</resultCode>", xml)
    m2 = re.search(r"<resultMsg>([^<]+)</resultMsg>", xml)
    return (
        (m1.group(1).strip() if m1 else "?"),
        (m2.group(1).strip() if m2 else "?"),
    )


def _key_fingerprint(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8", errors="replace")).hexdigest()[:10]


def build_key_candidates(raw: str) -> list[str]:
    """포털에서 준 한 줄로부터 의미 있는 serviceKey 후보 문자열들을 생성."""
    k = (raw or "").strip()
    out: list[str] = []
    seen: set[str] = set()

    def add(x: str) -> None:
        x = (x or "").strip()
        if not x or x in seen:
            return
        seen.add(x)
        out.append(x)

    add(k)

    # 디코딩 1~2회 (Encoding 형태로 붙여넣은 경우)
    cur = k
    for _ in range(2):
        try:
            nxt = urllib.parse.unquote(cur)
        except Exception:
            break
        if nxt == cur:
            break
        add(nxt)
        cur = nxt

    # 원문 기준 전체 퍼센트 인코딩
    add(urllib.parse.quote(k, safe=""))
    try:
        add(urllib.parse.quote(urllib.parse.unquote(k), safe=""))
    except Exception:
        pass

    # plus 인코딩 (쿼리 값으로 흔한 형태)
    add(urllib.parse.quote_plus(k))
    try:
        add(urllib.parse.quote_plus(urllib.parse.unquote(k)))
    except Exception:
        pass

    # 공백이 섞인 복사 실수
    add(k.replace(" ", ""))

    return out


def try_case(label: str, url: str | None, params: dict | None) -> tuple[str, str, str]:
    try:
        if url:
            r = requests.get(url, timeout=TIMEOUT)
        else:
            r = requests.get(BASE, params=params, timeout=TIMEOUT)
        code, msg = _parse_result(r.text)
        print(f"[{label}] HTTP {r.status_code} | resultCode={code} | resultMsg={msg}")
        if code != "99":
            print(f"    → 응답 앞부분: {_snippet(r.text)}")
        return code, msg, label
    except requests.RequestException as e:
        print(f"[{label}] 요청 실패: {e}")
        return "?", str(e), label


def main() -> int:
    p = argparse.ArgumentParser(description="사회서비스 API serviceKey 인코딩 조합 자동 시험")
    p.add_argument(
        "--key",
        default=os.environ.get("SOCIAL_SERVICE_API_KEY", "")
        or os.environ.get("SOCIAL_SERVICE_ENCODING", "")
        or os.environ.get("SOCIAL_SERVICE_DECODING", ""),
        help="포털에서 복사한 인증키 1개 (Encoding/Decoding 구분 없이)",
    )
    args = p.parse_args()
    raw_key = (args.key or "").strip()

    if not raw_key:
        print(
            "인증키가 없습니다. 포털에서 복사한 한 줄만 넣으면 됩니다.\n"
            "  $env:SOCIAL_SERVICE_API_KEY = '붙여넣기'\n"
            "  python batch/test_socialservice_auth.py\n"
            "또는: python batch/test_socialservice_auth.py --key \"...\""
        )
        return 1

    fp = _key_fingerprint(raw_key)
    print(f"키 지문(앞 10자 SHA256): {fp}  (원문 키는 출력하지 않음)")
    print(f"엔드포인트: {BASE}")
    print(f"파라미터: serviceTypeCode={SERVICE_TYPE_CODE}, serviceTypeName={SERVICE_TYPE_NAME}\n")

    candidates = build_key_candidates(raw_key)
    print(f"자동 생성한 serviceKey 후보: {len(candidates)}개\n")

    common = {
        "serviceTypeCode": SERVICE_TYPE_CODE,
        "serviceTypeName": SERVICE_TYPE_NAME,
    }

    best: list[tuple[str, str]] = []  # (label, code) where code != 99

    for i, sk in enumerate(candidates, start=1):
        short = f"후보{i} fp={_key_fingerprint(sk)}"

        code, msg, lab = try_case(f"{short} | params(requests)", None, {"serviceKey": sk, **common})
        if code != "99":
            best.append((lab, code))

        q = urllib.parse.urlencode(
            {"serviceKey": sk, **common},
            doseq=True,
            encoding="utf-8",
        )
        code2, msg2, lab2 = try_case(f"{short} | URL(urlencode 전체)", f"{BASE}?{q}", None)
        if code2 != "99":
            best.append((lab2, code2))

        q3 = urllib.parse.urlencode(
            {
                "serviceKey": urllib.parse.quote_plus(sk),
                **common,
            },
            doseq=True,
            encoding="utf-8",
        )
        code3, msg3, lab3 = try_case(
            f"{short} | URL(serviceKey만 quote_plus)",
            f"{BASE}?{q3}",
            None,
        )
        if code3 != "99":
            best.append((lab3, code3))

    print("\n--- 요약 ---")
    if best:
        print("99가 아닌 응답이 나온 조합 (이 방식을 앱/배치에 맞추면 됨):")
        for lab, c in best:
            print(f"  · {lab} → resultCode={c}")
    else:
        print(
            "모든 조합에서 resultCode=99 입니다.\n"
            "  → 인코딩 문제가 아니라 '이 호스트에 등록된 키가 아님'(개발/운영·상품 불일치)일 가능성이 큽니다."
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
