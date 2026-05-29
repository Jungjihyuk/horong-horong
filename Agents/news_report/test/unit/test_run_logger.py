"""뉴스 리포트 run logger 단위 테스트."""

import pytest

from tracing.run_logger import RunLogger


# 시나리오 1. RunLogger는 scope와 message를 사람이 읽는 run log 파일에 기록한다.
@pytest.mark.unit
def test_run_logger__info_message__writes_run_log(tmp_path):
    # Given: 임시 run log 경로와 RunLogger를 준비한다.
    log_path = tmp_path / "run.log"
    logger = RunLogger(str(log_path))

    # When: runner scope의 info 로그를 남긴다.
    logger.info("runner", "job started")
    for handler in logger._logger.handlers:
        handler.flush()

    # Then: run log 파일에 level, scope, message가 함께 기록된다.
    log_text = log_path.read_text(encoding="utf-8")
    assert "[INFO]" in log_text
    assert "[runner]" in log_text
    assert "job started" in log_text
