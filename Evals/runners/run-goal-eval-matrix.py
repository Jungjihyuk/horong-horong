#!/usr/bin/env python3
"""목표 추천 골든셋을 모델 × 컨텍스트 조건으로 순차 실행한다."""

import argparse
import json
import subprocess
from pathlib import Path


EVALS = Path(__file__).resolve().parent.parent
ROOT = EVALS.parent
CONFIG_PATH = EVALS / ".goal-eval-configuration.json"
MARKER_PATH = EVALS / ".run-golden"
VALID_PROVIDERS = {"appleFoundation", "ollama", "mlx"}
VALID_CONTEXT_MODES = {"withoutContext", "withContext"}


def saved_file(path):
    return path.read_bytes() if path.exists() else None


def restore_file(path, contents):
    if contents is None:
        path.unlink(missing_ok=True)
    else:
        path.write_bytes(contents)


def main():
    parser = argparse.ArgumentParser(description="목표 추천 골든셋 모델 매트릭스 실행기")
    parser.add_argument("--matrix", default="Evals/runners/goal-eval-matrix.json", help="모델 조합 JSON 파일")
    parser.add_argument("--skip-report", action="store_true", help="마지막 HTML 리포트 생성을 건너뜁니다")
    args = parser.parse_args()

    matrix_path = (ROOT / args.matrix).resolve()
    matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    context_modes = matrix.get("contextModes", ["withContext"])
    if not set(context_modes).issubset(VALID_CONTEXT_MODES):
        raise SystemExit(f"contextModes는 {sorted(VALID_CONTEXT_MODES)} 중에서 골라야 합니다.")
    models = matrix.get("models", [])
    if not models:
        raise SystemExit("models가 비어 있습니다.")

    old_config = saved_file(CONFIG_PATH)
    old_marker = saved_file(MARKER_PATH)
    try:
        MARKER_PATH.touch()
        for index, item in enumerate(models, start=1):
            provider = item.get("provider")
            if provider not in VALID_PROVIDERS:
                raise SystemExit(f"{item.get('name', index)}: provider는 {sorted(VALID_PROVIDERS)} 중 하나여야 합니다.")
            configuration = {
                "provider": provider,
                "model": item.get("model"),
                "contextModes": context_modes,
            }
            CONFIG_PATH.write_text(json.dumps(configuration, ensure_ascii=False), encoding="utf-8")
            print(f"\n[{index}/{len(models)}] {item.get('name', provider)} · {', '.join(context_modes)}")
            subprocess.run([
                "xcodebuild", "-project", "HorongHorong.xcodeproj", "-destination", "platform=macOS",
                "-skipPackagePluginValidation", "-skipMacroValidation", "-scheme", "HorongHorong",
                "-configuration", "Debug", "test",
                "-only-testing:HorongHorongTests/GoalSuggestionEvalTests",
            ], cwd=ROOT, check=True)
    finally:
        restore_file(CONFIG_PATH, old_config)
        restore_file(MARKER_PATH, old_marker)

    if not args.skip_report:
        subprocess.run([
            "python3", "Evals/report/eval-report.py", "--input", "Evals/results",
            "--output", "Evals/report/eval-report.html",
        ], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
