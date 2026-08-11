#!/usr/bin/env python3
"""
HorongHorong 뉴스 리포트 파이프라인 실행 진입점.
사용법: python3 runner.py --request <request.json> --result <result.json> --log <logfile>

이 모듈은 Swift 앱이 실행하는 Python sidecar의 진입점이다.
Swift가 `--request`로 전달한 뉴스 리포트 생성 요청을 읽고, 실행 환경을 준비한 뒤
뉴스 리포트 pipeline pattern을 실행해 `--result` JSON으로 결과를 돌려준다.

runner.py의 책임:
- CLI 인자 파싱과 Python sidecar 실행 환경 준비
- request / logger / step reporter / trace writer 초기화
- provider 생성
- pipeline pattern 선택과 실행
- pattern 실행 결과를 Swift 앱이 읽을 result JSON으로 반환
- 성공/실패 결과 JSON 작성

runner.py의 경계:
- 개별 source 수집 구현은 connectors에 위임한다.
- provider별 LLM 실행 구현은 providers에 위임한다.
- ontology 생성/분류 세부 정책은 ontology와 stages에 위임한다.
- relevance scoring, summarization, trend 분석, markdown rendering은 stages와 renderers에 위임한다.

선택 인자: --debug-log <debug.log>, --trace-log <trace.jsonl>
"""

import argparse
import os
import sys
import traceback
from datetime import datetime, timezone
from functools import partial


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--debug-log")
    parser.add_argument("--trace-log")

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, script_dir)

    from contracts.request_loader import load_request
    from tracing.run_logger import RunLogger
    from tracing.step_reporter import StepReporter
    from tracing.trace_writer import TraceWriter

    run_logger = RunLogger(args.log, debug_log_path=args.debug_log)
    # stage 함수들은 log(message) 콜백을 기대하므로 scope 만 고정해 연결한다.
    log = partial(run_logger.info, "runner")
    step_reporter = StepReporter(logger=run_logger)
    step = step_reporter.report

    started_at = datetime.now(timezone.utc).isoformat()
    job_id = "unknown"
    trace = None

    try:
        request = load_request(args.request)

        job_id = request.job_id
        provider = request.provider
        interest_keywords = request.interest_keywords
        max_items = request.max_items_per_source

        from exporters.result_exporter import build_success_result, write_result
        from patterns import PipelineContext, create_pattern, default_pattern_name
        from providers.factory import create_provider
        from providers.usage import total_usage_of

        pattern = create_pattern(default_pattern_name())
        llm = create_provider(provider, request.provider_options)

        if args.trace_log:
            trace = TraceWriter(
                trace_path=args.trace_log,
                run_id=job_id,
                pattern=pattern.name,
                pattern_version=pattern.version,
            )
            trace.write(
                "run_started",
                provider=provider,
                interest_keywords=interest_keywords,
                source_count=len(request.sources),
                max_items_per_source=max_items,
            )

        log(
            f"Job started: {job_id}, provider: {provider}, keywords: {interest_keywords}"
        )

        context = PipelineContext(
            request=request,
            provider=llm,
            log=log,
            step=step,
            trace=trace,
            started_at=started_at,
        )
        pattern_result = pattern.run(context)

        step("index")
        result = build_success_result(
            job_id=job_id,
            started_at=started_at,
            report_path=pattern_result.report_path,
            meta_path=pattern_result.meta_path,
            source_stats=pattern_result.source_stats,
            items=pattern_result.items,
            warnings=pattern_result.warnings,
            usage=total_usage_of(llm),
        )
        write_result(args.result, result)
        status = result["status"]

        if trace:
            trace.write(
                "run_completed",
                status=status,
                item_count=len(pattern_result.items),
                warning_count=len(pattern_result.warnings),
                report_path=pattern_result.report_path,
                meta_path=pattern_result.meta_path,
            )
            trace.close()

        log(f"Job completed: {status}")
        sys.exit(0)

    except Exception as e:
        tb = traceback.format_exc()
        log(f"EXCEPTION: {tb}")
        if trace:
            trace.write(
                "run_failed",
                error_type=type(e).__name__,
                error_message=str(e),
            )
            trace.close()

        try:
            from exporters.result_exporter import build_failure_result, write_result

            error_result = build_failure_result(job_id, started_at, e)
            write_result(args.result, error_result)
        except Exception:
            pass

        sys.exit(1)


if __name__ == "__main__":
    main()
