#!/usr/bin/env python3
"""카테고리별 월간 타임라인 생성 CLI.

리포트 파이프라인(`runner.py`)과 별도 프로세스인 이유:

- **실패 격리.** 리포트 생성은 이미 성공했는데 타임라인 종합이 실패했다고 해서
  리포트 job 전체를 실패로 만들면 안 된다.
- **요청과 무관.** 타임라인은 `data/reports/*.md` 만 읽는다. 커넥터 설정도,
  `NewsJobRequest` 의 어떤 필드도 필요 없다.
- **다른 주기.** 「6개월치 백필」이나 「이 카테고리만 다시」는 리포트 수집과 무관한
  on-demand 작업이다.

사용:
    uv run python3 timeline_runner.py --output-dir <dir> --category "금리/거시경제" --dry-run
    uv run python3 timeline_runner.py --output-dir <dir> --category "AI/반도체" --provider ollama
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import unicodedata
from datetime import datetime

from contracts.news_job_request import ProviderOptionsConfig
from providers.factory import create_provider
from renderers.timeline_markdown import write_timeline_markdown
from timeline.build import build_timeline


def category_id_for(label: str) -> str:
    """라벨에서 파일명으로 쓸 안정 식별자를 만든다.

    한글을 그대로 쓴다. 로마자로 바꾸면 사람이 `data/timeline/` 을 열었을 때 어떤
    카테고리인지 못 알아보고, vault 산출물 이름(«거시경제 타임라인.excalidraw.md»)과도
    어긋난다.
    """
    normalized = unicodedata.normalize("NFC", label).strip()
    return re.sub(r"[\s/]+", "-", normalized).strip("-") or "untitled"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="카테고리별 월간 타임라인 생성")
    parser.add_argument("--output-dir", required=True, help="data/reports 를 품은 폴더")
    parser.add_argument("--category", required=True, action="append",
                        help="카테고리 라벨. 여러 번 줄 수 있다")
    parser.add_argument("--provider", default="ollama")
    parser.add_argument("--model")
    parser.add_argument("--endpoint")
    parser.add_argument("--timeout", type=int)
    parser.add_argument("--since", help="이 날짜(YYYY-MM-DD) 이후 리포트만")
    parser.add_argument("--until", help="이 날짜(YYYY-MM-DD) 이전 리포트만")
    parser.add_argument("--think", action="store_true", default=False,
                        help="로컬 모델의 추론을 켠다. 기본은 꺼짐 — 스키마가 출력을 강제해 느려지기만 한다")
    parser.add_argument("--rebuild", action="store_true",
                        help="봉인을 무시하고 모든 달을 다시 종합한다")
    parser.add_argument("--dry-run", action="store_true",
                        help="어느 달을 다시 종합할지만 출력하고 LLM 을 부르지 않는다")
    args = parser.parse_args(argv)

    reports_dir = os.path.join(args.output_dir, "data", "reports")
    if not os.path.isdir(reports_dir):
        print(f"리포트 폴더가 없습니다: {reports_dir}", file=sys.stderr)
        return 2

    # dry-run 은 LLM 을 부르지 않으므로 provider 를 만들 필요도 없다.
    # provider CLI 가 깔려 있지 않은 환경에서도 계획을 볼 수 있어야 한다.
    provider = None
    if not args.dry_run:
        options = ProviderOptionsConfig(
            model=args.model, endpoint=args.endpoint, timeout=args.timeout
        )
        # 출력이 JSON schema 로 강제되므로 사고 토큰은 결과에 남지 않고 시간만 먹는다.
        provider = create_provider(args.provider, options, think=args.think)

    now = datetime.now()
    total_calls = 0
    for label in args.category:
        result = build_timeline(
            reports_dir=reports_dir,
            output_dir=args.output_dir,
            category_id=category_id_for(label),
            category_label=label,
            provider=provider,
            provider_name=args.provider,
            now=now,
            since=args.since,
            until=args.until,
            rebuild=args.rebuild,
            dry_run=args.dry_run,
            log=print,
        )
        # dry-run 은 실제로 부르지 않으므로 «부를 뻔한» 수를 센다.
        total_calls += (
            result.projected_calls if args.dry_run else result.total_calls
        )
        if not args.dry_run:
            print(f"[{label}] 마크다운: {write_timeline_markdown(args.output_dir, result.state)}")

    label = "예상 호출" if args.dry_run else "LLM 호출"
    print(f"\n{label}: {total_calls}회")
    return 0


if __name__ == "__main__":
    sys.exit(main())
