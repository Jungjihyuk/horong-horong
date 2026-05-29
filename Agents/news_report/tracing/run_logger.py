"""Run 단위 실행 로그를 사람이 읽기 쉬운 문장형 로그로 남기는 logger.

이 모듈은 프로그램이 다시 읽는 구조화 이벤트를 남기는 `tracing/trace_writer.py`와
역할이 다르다. Swift 앱이 넘긴 `--log` 경로를 대표 실행 로그로 사용하고,
각 pattern, stage, provider, connector, storage의 상태를 scope와 함께 기록한다.

예시 로그:

    [2026-05-25 14:10:02 KST] [INFO] [runner] job started
    [2026-05-25 14:10:30 KST] [WARNING] [stage.judge] validation failed, retrying
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta, timezone


KST = timezone(timedelta(hours=9))


class KSTFormatter(logging.Formatter):
    def formatTime(self, record, datefmt=None):
        dt = datetime.fromtimestamp(record.created, KST)
        if datefmt:
            return dt.strftime(datefmt)
        return dt.strftime("%Y-%m-%d %H:%M:%S KST")


class RunLogger:
    def __init__(self, run_log_path: str, debug_log_path: str | None = None):
        """뉴스 리포트 생성 실행 1회(run)의 누적 로그를 기록한다.

        하나의 run은 사용자가 수동으로 실행했거나 스케줄러가 자동으로 시작한
        뉴스 수집, 판단, 요약, 리포트 저장의 한 번의 전체 실행을 뜻한다.
        이 logger는 run 안에서 발생하는 pattern, stage, provider, connector,
        storage 로그를 하나의 흐름으로 기록한다.

        Args:
            run_log_path: 이번 run의 대표 실행 로그 파일 경로. Swift 앱에서 실행할
                때는 `--log` 인자로 전달된 경로를 사용하고, Python 단독 실행에서는
                호출자가 직접 지정한 로그 파일 경로를 사용한다.
            debug_log_path: 이번 run의 개발자용 상세 로그 파일 경로. 지정하면
                DEBUG 레벨을 포함한 상세 로그를 별도 파일에 남긴다. 지정하지 않으면
                대표 실행 로그만 남긴다.
        """
        self._logger = logging.getLogger(f"news_report.run.{id(self)}")
        self._logger.setLevel(logging.DEBUG)
        self._logger.handlers.clear()
        self._logger.propagate = False

        self._add_file_handler(
            path=run_log_path,
            level=logging.INFO,
            formatter=self._run_formatter(),
        )

        if debug_log_path:
            self._add_file_handler(
                path=debug_log_path,
                level=logging.DEBUG,
                formatter=self._debug_formatter(),
            )

    def debug(self, scope: str, message: str):
        self._logger.debug(message, extra={"scope": scope})

    def info(self, scope: str, message: str):
        self._logger.info(message, extra={"scope": scope})

    def warning(self, scope: str, message: str):
        self._logger.warning(message, extra={"scope": scope})

    def error(self, scope: str, message: str):
        self._logger.error(message, extra={"scope": scope})

    def critical(self, scope: str, message: str):
        self._logger.critical(message, extra={"scope": scope})

    def exception(self, scope: str, message: str):
        self._logger.exception(message, extra={"scope": scope})

    def _add_file_handler(
        self,
        path: str,
        level: int,
        formatter: logging.Formatter,
    ) -> None:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        handler = logging.FileHandler(path, encoding="utf-8")
        handler.setLevel(level)
        handler.setFormatter(formatter)
        self._logger.addHandler(handler)

    def _run_formatter(self) -> logging.Formatter:
        return KSTFormatter(
            "[%(asctime)s] [%(levelname)s] [%(scope)s] %(message)s"
        )

    def _debug_formatter(self) -> logging.Formatter:
        return KSTFormatter(
            "[%(asctime)s] [%(levelname)s] [%(scope)s] "
            "%(filename)s:%(lineno)d %(funcName)s() - %(message)s"
        )
