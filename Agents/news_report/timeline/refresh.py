"""리포트 생성 직후 타임라인을 따라오게 한다.

**이미 만들어둔 타임라인만 갱신한다.** 새 분야를 자동으로 «만들지» 않는 이유는, 사용자가
원한 적 없는 카테고리에 LLM 비용이 조용히 나가면 안 되기 때문이다. 새 타임라인을 만드는
것은 명시적인 행위로 남긴다(`timeline_runner.py --category "..."`).

리포트 1편이 늘면 대개 현재 월 버킷만 바뀌므로, 타임라인 1개당 호출은 1~2회로 억제된다
(`timeline/state.py` 의 봉인 규칙).
"""

from __future__ import annotations

import glob
import json
import os
from datetime import datetime
from typing import Callable

from renderers.timeline_markdown import write_timeline_markdown
from timeline.build import build_timeline


def existing_timeline_paths(output_dir: str) -> list[str]:
    return sorted(glob.glob(os.path.join(output_dir, "data", "timeline", "*.json")))


def _identity(path: str) -> tuple[str, str] | None:
    """상태 파일에서 (category_id, category_label) 만 꺼낸다."""
    try:
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None
    category_id = str(payload.get("category_id") or "").strip()
    label = str(payload.get("category_label") or "").strip()
    if not category_id or not label:
        return None
    return category_id, label


def refresh_existing_timelines(
    *,
    output_dir: str,
    provider,
    provider_name: str,
    now: datetime,
    log: Callable[[str], None] = lambda _message: None,
) -> list[str]:
    """이미 있는 타임라인을 최신 리포트까지 따라가게 한다. 경고 목록을 돌려준다.

    **리포트 job 을 실패시키지 않는다.** 리포트는 이미 성공적으로 만들어졌는데 타임라인
    종합이 실패했다고 job 전체를 실패로 만들면, 사용자는 멀쩡한 리포트를 잃는다.
    """
    warnings: list[str] = []
    paths = existing_timeline_paths(output_dir)
    if not paths:
        log("타임라인 없음 — 건너뜁니다. 새로 만들려면 timeline_runner.py --category 를 쓰세요.")
        return warnings

    reports_dir = os.path.join(output_dir, "data", "reports")
    for path in paths:
        identity = _identity(path)
        if identity is None:
            warnings.append(f"타임라인 상태 파일을 읽지 못했습니다: {os.path.basename(path)}")
            continue

        category_id, label = identity
        try:
            result = build_timeline(
                reports_dir=reports_dir,
                output_dir=output_dir,
                category_id=category_id,
                category_label=label,
                provider=provider,
                provider_name=provider_name,
                now=now,
                log=log,
            )
            write_timeline_markdown(output_dir, result.state)
            log(f"타임라인 갱신: {label} (LLM {result.total_calls}회)")
            warnings.extend(result.state.warnings)
        except Exception as error:  # noqa: BLE001 — 리포트 결과를 지키는 것이 우선이다
            warnings.append(f"타임라인 갱신 실패({label}): {type(error).__name__}: {error}")
            log(f"타임라인 갱신 실패: {label} ({type(error).__name__})")

    return warnings
