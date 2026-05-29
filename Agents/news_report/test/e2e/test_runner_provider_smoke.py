"""provider별 runner e2e smoke 테스트."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import cast

import pytest


pytestmark = pytest.mark.e2e

NEWS_REPORT_ROOT = Path(__file__).resolve().parents[2]

PROVIDER_FIXTURES = [
    ("ollama", "ollama-all-sources-request.json"),
    ("claude", "claude-all-sources-request.json"),
    ("codex", "codex-all-sources-request.json"),
    ("gemini", "gemini-all-sources-request.json"),
    ("antigravity", "antigravity-all-sources-request.json"),
]

PROVIDER_COMMANDS = {
    "antigravity": "agy",
    "claude": "claude",
    "codex": "codex",
    "gemini": "gemini",
}


@pytest.mark.parametrize(("provider", "fixture_name"), PROVIDER_FIXTURES)
def test_runner_provider_smoke__e2e__creates_report_artifacts(
    provider: str,
    fixture_name: str,
    tmp_path: Path,
):
    # Given: 명시적으로 e2e 실행이 켜져 있고 provider 실행 조건이 준비되어 있다.
    require_e2e_enabled()
    require_provider_available(provider)
    request_path = build_temp_request(fixture_name, provider, tmp_path)
    result_path = tmp_path / f"{provider}-result.json"
    run_log_path = tmp_path / f"{provider}-run.log"
    debug_log_path = tmp_path / f"{provider}-debug.log"
    trace_log_path = tmp_path / f"{provider}-trace.jsonl"
    stdout_path = tmp_path / f"{provider}-stdout.log"
    stderr_path = tmp_path / f"{provider}-stderr.log"
    command = [
        sys.executable,
        "runner.py",
        "--request",
        str(request_path),
        "--result",
        str(result_path),
        "--log",
        str(run_log_path),
        "--debug-log",
        str(debug_log_path),
        "--trace-log",
        str(trace_log_path),
    ]

    # When: runner.py를 실제 subprocess로 실행한다.
    completed = run_runner_command(
        provider,
        command,
        trace_log_path,
        stdout_path,
        stderr_path,
        timeout=int(os.getenv("HORONG_E2E_TIMEOUT", "1200")),
    )

    # Then: 프로세스가 성공하고 Swift가 읽을 result/report/meta/trace 산출물이 생성된다.
    assert completed.returncode == 0, (
        f"stdout:\n{completed.stdout}\n\n"
        f"stderr:\n{completed.stderr}\n\n"
        f"run log:\n{read_if_exists(run_log_path)}\n\n"
        f"debug log:\n{read_if_exists(debug_log_path)}"
    )
    result = load_json_object(result_path)
    assert result["status"] in {"success", "partial_success"}
    assert result["reportPath"]
    assert result["metaPath"]

    output_dir = tmp_path / f"{provider}-output"
    report_rel = str(result["reportPath"])
    meta_rel = str(result["metaPath"])
    report_path = output_dir / report_rel
    meta_path = output_dir / meta_rel
    assert report_path.exists()
    assert meta_path.exists()
    assert trace_log_path.exists()

    meta = load_json_object(meta_path)
    research_artifacts = meta.get("researchArtifacts")
    assert isinstance(research_artifacts, dict)
    assert "sourceCandidates" in research_artifacts

    trace_text = trace_log_path.read_text(encoding="utf-8")
    assert "stage_started" in trace_text
    assert "stage_completed" in trace_text
    assert "provider_started" in trace_text
    assert "provider_completed" in trace_text
    assert "structured_output" in trace_text
    assert "artifact_written" in trace_text


def require_e2e_enabled() -> None:
    """e2e opt-in 환경변수가 없으면 테스트를 건너뛴다."""
    if os.getenv("HORONG_RUN_E2E") != "1":
        pytest.skip("HORONG_RUN_E2E=1 일 때만 provider e2e smoke test를 실행한다.")


def require_provider_available(provider: str) -> None:
    """provider별 로컬 실행 조건을 확인한다."""
    if provider == "ollama":
        if shutil.which("ollama") is None:
            pytest.skip("ollama 명령을 PATH에서 찾을 수 없다.")
        try:
            with urllib.request.urlopen("http://localhost:11434/api/tags", timeout=2):
                return
        except (OSError, urllib.error.URLError) as error:
            pytest.skip(f"Ollama 서버가 준비되지 않았다: {error}")

    command = PROVIDER_COMMANDS.get(provider)
    if command and shutil.which(command) is None:
        pytest.skip(f"{command} 명령을 PATH에서 찾을 수 없다.")


def build_temp_request(fixture_name: str, provider: str, tmp_path: Path) -> Path:
    """fixture request를 tmp_path 출력 경로로 복사한다."""
    fixture_path = NEWS_REPORT_ROOT / "test" / "fixtures" / "requests" / fixture_name
    payload = load_json_object(fixture_path)
    payload["outputDir"] = str(tmp_path / f"{provider}-output")
    payload["jobId"] = f"e2e-{provider}-smoke"

    request_path = tmp_path / f"{provider}-request.json"
    _ = request_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return request_path


def run_runner_command(
    provider: str,
    command: Sequence[str],
    trace_log_path: Path,
    stdout_path: Path,
    stderr_path: Path,
    *,
    timeout: int,
) -> subprocess.CompletedProcess[str]:
    """runner.py를 실행하고 progress opt-in이면 trace 진행 상황을 출력한다."""
    if os.getenv("HORONG_E2E_PROGRESS") == "1":
        return run_runner_command_with_progress(
            provider,
            command,
            trace_log_path,
            stdout_path,
            stderr_path,
            timeout=timeout,
        )

    return subprocess.run(
        list(command),
        cwd=NEWS_REPORT_ROOT,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def run_runner_command_with_progress(
    provider: str,
    command: Sequence[str],
    trace_log_path: Path,
    stdout_path: Path,
    stderr_path: Path,
    *,
    timeout: int,
) -> subprocess.CompletedProcess[str]:
    """Popen으로 runner.py를 실행하며 trace JSONL 새 이벤트를 출력한다."""
    print(f"[{provider}] e2e started", flush=True)
    started_at = time.monotonic()
    trace_offset = 0
    interval = float(os.getenv("HORONG_E2E_PROGRESS_INTERVAL", "1.0"))

    with stdout_path.open("w+", encoding="utf-8") as stdout_file, stderr_path.open(
        "w+",
        encoding="utf-8",
    ) as stderr_file:
        process = subprocess.Popen(
            list(command),
            cwd=NEWS_REPORT_ROOT,
            stdout=stdout_file,
            stderr=stderr_file,
            text=True,
        )

        while True:
            trace_offset = print_new_trace_events(provider, trace_log_path, trace_offset)

            returncode = process.poll()
            if returncode is not None:
                break

            elapsed = time.monotonic() - started_at
            if elapsed > timeout:
                process.terminate()
                try:
                    _ = process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    _ = process.wait(timeout=5)

                trace_offset = print_new_trace_events(
                    provider,
                    trace_log_path,
                    trace_offset,
                )
                stdout_file.flush()
                stderr_file.flush()
                stderr = read_if_exists(stderr_path)
                timeout_message = f"Timed out after {timeout}s"
                print(f"[{provider}] {timeout_message}", flush=True)
                return subprocess.CompletedProcess(
                    list(command),
                    -1,
                    read_if_exists(stdout_path),
                    f"{timeout_message}\n{stderr}",
                )

            time.sleep(interval)

        trace_offset = print_new_trace_events(provider, trace_log_path, trace_offset)
        stdout_file.flush()
        stderr_file.flush()

    print(f"[{provider}] e2e completed exit={process.returncode}", flush=True)
    return subprocess.CompletedProcess(
        list(command),
        int(process.returncode or 0),
        read_if_exists(stdout_path),
        read_if_exists(stderr_path),
    )


def print_new_trace_events(provider: str, trace_log_path: Path, offset: int) -> int:
    """trace JSONL에서 새로 추가된 이벤트만 progress 한 줄로 출력한다."""
    if not trace_log_path.exists():
        return offset

    with trace_log_path.open("r", encoding="utf-8") as file:
        _ = file.seek(offset)
        lines = file.readlines()
        next_offset = file.tell()

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        try:
            event = cast(dict[str, object], json.loads(stripped))
        except json.JSONDecodeError:
            continue
        print(format_trace_progress(provider, event), flush=True)

    return next_offset


def format_trace_progress(provider: str, event: Mapping[str, object]) -> str:
    """trace event를 e2e progress용 한 줄 문자열로 변환한다."""
    event_name = string_value(event.get("event")) or "unknown_event"
    stage = string_value(event.get("stage"))
    duration_ms = event.get("duration_ms")
    payload = payload_object(event)

    parts = [f"[{provider}]", event_name]
    if stage:
        parts.append(stage)

    schema = string_value(payload.get("schema"))
    if schema:
        parts.append(schema)

    source_type = string_value(payload.get("source_type"))
    if source_type:
        parts.append(f"source={source_type}")

    artifact_type = string_value(payload.get("artifact_type"))
    if artifact_type:
        parts.append(f"artifact={artifact_type}")

    status = string_value(payload.get("status"))
    if status:
        parts.append(f"status={status}")

    error_type = string_value(payload.get("error_type"))
    if error_type:
        parts.append(f"error={error_type}")

    if isinstance(duration_ms, int):
        parts.append(f"{duration_ms}ms")

    return " ".join(parts)


def payload_object(event: Mapping[str, object]) -> Mapping[str, object]:
    """trace event payload를 object mapping으로 읽는다."""
    payload = event.get("payload")
    if isinstance(payload, Mapping):
        return cast(Mapping[str, object], payload)
    return {}


def string_value(value: object) -> str:
    """문자열 값을 안전하게 읽는다."""
    return value if isinstance(value, str) else ""


def load_json_object(path: Path) -> dict[str, object]:
    """JSON 파일을 object payload로 읽는다."""
    return cast(dict[str, object], json.loads(path.read_text(encoding="utf-8")))


def read_if_exists(path: Path) -> str:
    """실패 메시지에 넣을 파일 내용을 읽는다."""
    if not path.exists():
        return "(file does not exist)"
    return path.read_text(encoding="utf-8")
