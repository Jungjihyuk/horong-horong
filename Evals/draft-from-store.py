#!/usr/bin/env python3
"""실사용 메모에서 골든셋 케이스 초안을 만든다.

추천 파이프라인이 실제로 보는 것과 같은 조건으로 메모를 고른다.
- 미완료(ZISCOMPLETED = 0)
- 보관 안 됨(ZISARCHIVED = 0)

출력은 `Evals/golden/drafts/`(gitignore)에 쓴다.
**초안에는 실제 메모 본문이 그대로 들어 있으므로 각색 전에는 절대 cases/ 로 옮기지 말 것.**

사용:
    python3 Evals/draft-from-store.py            # 최근 메모 15개로 초안 1개
    python3 Evals/draft-from-store.py --count 3  # 초안 3개
    python3 Evals/draft-from-store.py --size 20  # 케이스당 메모 20개
"""
import argparse
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

STORE = Path.home() / "Library/Application Support/HorongHorong/Stores/v2/default.store"
ROOT = Path(__file__).resolve().parent.parent
DRAFTS = ROOT / "Evals/golden/drafts"

# 각색이 필요할 법한 부분을 표시만 해 둔다. 판단은 사람이 한다.
PII_HINTS = [
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+"), "이메일"),
    (re.compile(r"01[016-9][-\s]?\d{3,4}[-\s]?\d{4}"), "전화번호"),
    (re.compile(r"https?://\S+"), "URL"),
    (re.compile(r"\d{4,}"), "긴 숫자"),
]


def hints(text: str) -> list[str]:
    return sorted({label for pattern, label in PII_HINTS if pattern.search(text)})


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=1, help="만들 초안 개수")
    parser.add_argument("--size", type=int, default=15, help="케이스당 메모 개수")
    args = parser.parse_args()

    if not STORE.exists():
        print(f"스토어를 찾지 못했습니다: {STORE}", file=sys.stderr)
        return 1

    connection = sqlite3.connect(f"file:{STORE}?mode=ro", uri=True)
    rows = connection.execute(
        """
        SELECT ZCONTENT, ZICON, ZSTARTDATE, ZDEADLINE
        FROM ZMEMO
        WHERE ZISCOMPLETED = 0 AND ZISARCHIVED = 0 AND ZCONTENT IS NOT NULL
        ORDER BY ZUPDATEDAT DESC
        LIMIT ?
        """,
        (args.count * args.size,),
    ).fetchall()
    connection.close()

    if not rows:
        print("조건에 맞는 메모가 없습니다.", file=sys.stderr)
        return 1

    DRAFTS.mkdir(parents=True, exist_ok=True)
    written = []
    for index in range(args.count):
        chunk = rows[index * args.size : (index + 1) * args.size]
        if len(chunk) < 2:
            break
        memos = []
        flagged = []
        for position, (content, icon, _start, _deadline) in enumerate(chunk, start=1):
            found = hints(content)
            if found:
                flagged.append(f"m{position}({', '.join(found)})")
            memos.append({"id": f"m{position}", "content": content, "icon": icon or "📝"})

        draft = {
            "caseName": f"[초안{index + 1}] 각색 후 이름을 바꿔주세요",
            "note": (
                "실사용 메모에서 자동 생성된 초안입니다. "
                "본문을 각색하고 expectedGroups/shouldNotGroup 을 채운 뒤 cases/ 로 옮기세요."
                + (f" 각색 검토 필요: {', '.join(flagged)}" if flagged else "")
            ),
            "memos": memos,
            "expectedGroups": [],
            "shouldNotGroup": [],
        }
        path = DRAFTS / f"draft-{index + 1}.json"
        path.write_text(json.dumps(draft, ensure_ascii=False, indent=2) + "\n")
        written.append((path, len(memos), flagged))

    print(f"초안 {len(written)}개 생성 → {DRAFTS.relative_to(ROOT)}/")
    for path, size, flagged in written:
        note = f"  검토 필요: {', '.join(flagged)}" if flagged else ""
        print(f"  {path.name}  메모 {size}개{note}")
    print()
    print("다음 순서:")
    print("  1) 초안을 열어 본문을 각색 (이름·회사·연락처·URL 등)")
    print("  2) expectedGroups 에 '묶여야 하는' id 묶음을 적기")
    print("  3) shouldNotGroup 에 '묶이면 안 되는' 조합 적기")
    print("  4) 파일명을 05-xxx.json 처럼 바꿔 cases/ 로 이동")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
