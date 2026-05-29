"""Swift UI 진행 상태용 STEP reporter 단위 테스트."""

from io import StringIO

import pytest

from tracing.step_reporter import StepReporter


# 시나리오 1. Python runner의 현재 단계가 Swift UI와 run log 양쪽에 전달된다.
@pytest.mark.unit
def test_step_reporter__reported_step__writes_stdout_and_log(fake_step_logger):
    # Given: stdout 대체 스트림과 호출 기록용 fake logger를 준비한다.
    output = StringIO()
    reporter = StepReporter(output=output, logger=fake_step_logger)

    # When: 현재 실행 단계를 reporter에 전달한다.
    reporter.report("collect")

    # Then: Swift UI용 STEP 신호와 run log 기록이 함께 남는다.
    assert output.getvalue() == "STEP:collect\n"
    assert fake_step_logger.info_calls == [("step", "STEP: collect")]


# 시나리오 2. run logger가 없어도 Swift UI용 STEP stdout 신호는 출력된다.
@pytest.mark.unit
def test_step_reporter__without_logger__writes_stdout_only():
    # Given: logger 없이 stdout 대체 스트림만 준비한다.
    output = StringIO()
    reporter = StepReporter(output=output)

    # When: 현재 실행 단계를 reporter에 전달한다.
    reporter.report("summarize")

    # Then: logger가 없어도 STEP stdout 신호 형식은 동일하다.
    assert output.getvalue() == "STEP:summarize\n"
