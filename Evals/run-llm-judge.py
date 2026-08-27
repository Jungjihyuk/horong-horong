#!/usr/bin/env python3
"""기존 목표 추천 실행 결과에 LLM-as-a-Judge 루브릭을 적용한다.

모델을 다시 실행하지 않고 Evals/results/*.jsonl 및 traces/*.json을 읽는다.
기본 judge는 Codex CLI이며, Claude는 --judge claude, 기타 CLI는 --command로 연결한다.
--model은 CLI에 전달하지 않는 기록용 라벨이다. 실제 모델은 각 CLI의 현재 선택/기본 설정을 따른다.
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EVALS = ROOT / "Evals"
RUBRIC = EVALS / "judges" / "rubric-v1.md"


def latest_results(path: Path) -> Path:
    if path.is_file():
        return path
    files = sorted(path.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)
    if not files:
        raise SystemExit(f"결과 JSONL을 찾지 못했습니다: {path}")
    return files[-1]


def load_cases():
    cases = {}
    for path in (EVALS / "golden" / "cases").rglob("*.json"):
        try:
            case = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if case.get("caseName"):
            cases[case["caseName"]] = case
    return cases


def load_traces():
    traces = {}
    for path in (EVALS / "results" / "traces").glob("*.json"):
        try:
            trace = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if trace.get("runId"):
            traces[trace["runId"]] = trace
    return traces


def extracted_payload(trace):
    for span in (trace or {}).get("spans", []):
        if span.get("name") != "extractedJSON":
            continue
        try:
            return json.loads(span.get("text") or "")
        except json.JSONDecodeError:
            return None
    return None


def review_without_reference_text(outcome):
    """Judge가 골든셋의 예시 문장을 그대로 비교하지 않도록 기준만 남긴다."""
    if not outcome:
        return None
    reviews = []
    for key, id_key in (("memoReviews", "memo"), ("goalReviews", "goal")):
        for review in outcome.get(key) or []:
            if review.get(id_key):
                item = {id_key: review[id_key]}
                if "missing" in review:
                    item["missing"] = review.get("missing") or []
                if "classification" in review:
                    item["classification"] = review.get("classification")
                if "reason" in review:
                    item["reason"] = review.get("reason")
                reviews.append(item)
    result = {"action": outcome.get("action")}
    if outcome.get("reason"):
        result["reason"] = outcome.get("reason")
    if reviews:
        result["reviews"] = reviews
    return result


def judge_input(row, case, payload, rubric):
    dataset_type = case.get("datasetType")
    context = case.get("context") or {}
    if dataset_type == "insufficient_information":
        criteria = ["guidance_fit", "guidance_actionability", "clarity", "grammar", "vocabulary", "tone"]
    elif dataset_type == "non_goal_or_noise":
        criteria = ["guidance_fit", "clarity", "grammar", "vocabulary", "tone"]
    else:
        criteria = ["semantic_cohesion", "noise_exclusion", "clarity", "measurability", "time_fit", "grammar", "vocabulary", "tone"]
        if context.get("persona") or context.get("profile"):
            criteria.append("relevance")

    case_view = {
        "caseName": case.get("caseName"),
        "datasetType": dataset_type,
        "task": row.get("task"),
        "context": context,
        "referenceDate": case.get("referenceDate"),
        "memos": case.get("memos"),
        "weeklyGoals": case.get("weeklyGoals"),
        "expectedGroups": [
            {"type": g.get("type"), "memos": g.get("memos", []), "goals": g.get("goals", [])}
            for g in case.get("expectedGroups") or []
        ],
        "expectedOutcome": review_without_reference_text(case.get("expectedOutcome")),
    }
    instruction = {
        "task": "목표 추천 결과를 루브릭에 따라 평가하라.",
        "rules": [
            "정답 문장과의 문자열 일치 여부가 아니라 의미와 유용성을 평가하라.",
            "결정적 지표(pairF1, guidanceF1, missingF1, noSuggestionCorrect)를 다시 계산하지 말고 루브릭의 의미 품질만 평가하라.",
            "non_goal_or_noise에서 모델이 비목표 안내(guidance)를 제공한 경우, 각 입력이 왜 목표가 아닌지(골든셋의 classification/reason)에 부합하게 잘 설명했는지를 guidance_fit으로 평가하라. 비목표 입력에는 guidance_actionability를 적용하지 않는다.",
            "목표나 안내가 생성되지 않은(noSuggestion 등) 경우 생성물이 없으므로 관련 기준은 null로 하고 notApplicable에 넣어라.",
            "적용되지 않는 기준은 scores에서 null로 하고 notApplicable에 넣어라.",
            "각 점수에는 한 문장의 근거를 써라.",
            "JSON 객체만 출력하고 Markdown fence를 사용하지 마라.",
        ],
        "rubric": rubric,
        "case": case_view,
        "actualResult": payload,
        "criteria": criteria,
        "outputSchema": {
            "items": [{"item": "group-1 or input-id", "scores": {"criterion": 0}, "reasons": {"criterion": "..."}}],
            "summary": {"criterion": 0},
            "notApplicable": [],
        },
    }
    return json.dumps(instruction, ensure_ascii=False, indent=2)


def run_cli(judge, prompt, command):
    if command:
        argv = shlex.split(command)
        completed = subprocess.run(argv, input=prompt, text=True, capture_output=True, cwd=ROOT, timeout=300)
        if completed.returncode:
            raise RuntimeError(completed.stderr.strip() or f"judge 종료 코드 {completed.returncode}")
        return completed.stdout
    if judge == "codex":
        with tempfile.NamedTemporaryFile(prefix="goal-judge-", suffix=".txt") as output:
            argv = ["codex", "exec", "--ephemeral", "--sandbox", "read-only", "--output-last-message", output.name, "-"]
            completed = subprocess.run(argv, input=prompt, text=True, capture_output=True, cwd=ROOT, timeout=300)
            if completed.returncode:
                raise RuntimeError(completed.stderr.strip() or f"codex 종료 코드 {completed.returncode}")
            return Path(output.name).read_text(encoding="utf-8")
    if judge == "claude":
        completed = subprocess.run(["claude", "-p", prompt], text=True, capture_output=True, cwd=ROOT, timeout=300)
        if completed.returncode:
            raise RuntimeError(completed.stderr.strip() or f"claude 종료 코드 {completed.returncode}")
        return completed.stdout
    raise SystemExit("antigravity 또는 사용자 CLI는 --command로 실행 명령을 지정하세요.")


def parse_json(text):
    text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start, end = text.find("{"), text.rfind("}")
        if start >= 0 and end > start:
            return json.loads(text[start : end + 1])
        raise


def main():
    parser = argparse.ArgumentParser(description="기존 목표 추천 결과에 LLM judge 적용")
    parser.add_argument("--judge", choices=("codex", "claude", "antigravity"), default="codex")
    parser.add_argument("--model", help="결과 파일명과 judgeModel에 남길 기록용 모델 라벨. CLI에는 전달하지 않음")
    parser.add_argument("--input", default=str(EVALS / "results"), help="결과 JSONL 또는 results 디렉터리")
    parser.add_argument("--output", help="judge JSONL 출력 경로")
    parser.add_argument("--command", help="judge CLI 명령. 프롬프트는 stdin으로 전달")
    parser.add_argument("--limit", type=int, default=20, help="평가할 최대 실행 수")
    parser.add_argument("--dry-run", action="store_true", help="첫 번째 judge 프롬프트만 출력")
    args = parser.parse_args()

    input_path = latest_results(Path(args.input).resolve())
    rows = [json.loads(line) for line in input_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    cases, traces = load_cases(), load_traces()
    rubric = RUBRIC.read_text(encoding="utf-8")
    selected = []
    for row in rows:
        case = cases.get(row.get("case_id"))
        payload = extracted_payload(traces.get(row.get("run_id")))
        if case and payload and row.get("source") != "live":
            selected.append((row, case, payload))
    selected = selected[: max(0, args.limit)]
    if not selected:
        raise SystemExit("trace와 골든셋 케이스가 모두 있는 평가 대상을 찾지 못했습니다.")

    if args.dry_run:
        print(judge_input(*selected[0], rubric))
        return

    stamp = datetime.now().strftime("%Y%m%dT%H%M%S%z")
    judge_model = args.model or os.environ.get("JUDGE_MODEL") or "default"
    model_slug = re.sub(r"[^A-Za-z0-9._-]+", "_", judge_model).strip("._-") or "default"
    output = Path(args.output).resolve() if args.output else EVALS / "results" / "judges" / f"{stamp}-{args.judge}-{model_slug}.jsonl"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as handle:
        for index, (row, case, payload) in enumerate(selected, start=1):
            print(f"[{index}/{len(selected)}] {row.get('model')} · {row.get('case_id')}")
            result = {
                "runId": row.get("run_id"), "caseId": row.get("case_id"), "model": row.get("model"),
                "recipe": row.get("recipe"), "judge": args.judge, "judgeModel": judge_model, "rubricVersion": "v1",
            }
            try:
                result["evaluation"] = parse_json(run_cli(args.judge, judge_input(row, case, payload, rubric), args.command))
                result["status"] = "ok"
            except (OSError, RuntimeError, json.JSONDecodeError) as error:
                result["status"], result["error"] = "error", str(error)
            handle.write(json.dumps(result, ensure_ascii=False) + "\n")
    print(f"judge 결과 저장: {output}")


if __name__ == "__main__":
    main()
