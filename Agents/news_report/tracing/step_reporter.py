"""Swift 앱에 현재 실행 단계를 알리는 STEP stdout reporter.

Python runner가 실제 deep research 단계를 실행하므로 Swift 앱은 내부 진행 상태를
직접 알 수 없다. 이 모듈은 `STEP:<name>` 형식의 stdout 신호를 출력해
Swift `NewsPipelineService`가 현재 단계를 UI에 표시할 수 있게 한다.

예시 stdout:

    STEP:collect
    STEP:summarize
"""

from __future__ import annotations

import sys
from typing import Protocol, TextIO


class StepLogger(Protocol):
    def info(self, scope: str, message: str) -> None:
        """STEP 신호와 같은 내용을 run log에도 남길 때 사용하는 최소 logger 계약."""


class StepReporter:
    def __init__(self, output: TextIO | None = None, logger: StepLogger | None = None):
        """Swift 앱이 읽을 수 있는 STEP stdout 신호를 출력한다.

        Args:
            output: STEP 신호를 쓸 출력 스트림. 지정하지 않으면 `sys.stdout`을 쓴다.
                테스트에서는 `io.StringIO` 같은 객체를 넘길 수 있다.
            logger: 선택적 run logger. 지정하면 STEP 신호를 stdout에 출력한 뒤
                같은 단계 정보를 run log에도 남긴다.
        """
        self._output = output or sys.stdout
        self._logger = logger

    def report(self, step_name: str) -> None:
        """현재 실행 단계를 `STEP:<name>` 형식으로 출력한다.

        Args:
            step_name: Swift UI에 표시할 현재 단계 이름. 예: `collect`,
                `summarize`, `render`.
        """
        print(self._format_step(step_name), file=self._output, flush=True)
        if self._logger:
            self._logger.info("step", f"STEP: {step_name}")

    def _format_step(self, step_name: str) -> str:
        return f"STEP:{step_name}"
