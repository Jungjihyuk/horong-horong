#!/usr/bin/env python3
"""기존 목표 추천 실행 결과에 LLM-as-a-Judge 루브릭을 적용한다.

모델을 다시 실행하지 않고 Evals/results/*.jsonl 및 traces/*.json을 읽는다.
기본 judge는 Codex CLI이며, Claude/Grok/Antigravity는 --judge claude|grok|antigravity,
기타 CLI는 --command로 연결한다.
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


def result_files(path: Path, use_all: bool):
    """평가할 결과 JSONL 목록. 기본은 가장 최근 파일 하나, 재시도는 전체 파일이다."""
    if path.is_file():
        return [path]
    files = sorted(path.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)
    if not files:
        raise SystemExit(f"결과 JSONL을 찾지 못했습니다: {path}")
    return files if use_all else [files[-1]]


def failed_run_ids():
    """judge가 시도했지만 끝내 성공하지 못한 run만 고른다.

    한 번도 채점하지 않은 run은 대상이 아니다. 실패 후 다른 judge로 성공한 run도
    제외해서, 재시도를 여러 번 이어 붙여도 남은 실패분만 계속 줄어들게 한다.
    """
    ok, failed = set(), set()
    for path in sorted((EVALS / "results" / "judges").glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not row.get("runId"):
                continue
            (ok if row.get("status") == "ok" else failed).add(row["runId"])
    return failed - ok


def slug(text):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", text or "").strip("._-") or "unknown"


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


def run_argv(argv, stdin=""):
    completed = subprocess.run(argv, input=stdin, text=True, capture_output=True, cwd=ROOT, timeout=300)
    if completed.returncode:
        raise RuntimeError(completed.stderr.strip() or f"judge 종료 코드 {completed.returncode}")
    return completed.stdout


def run_cli(judge, prompt, command):
    if command:
        argv = shlex.split(command)
        # grok처럼 프롬프트를 stdin이 아니라 인자로만 받는 CLI가 있다.
        if any("{prompt}" in arg for arg in argv):
            return run_argv([arg.replace("{prompt}", prompt) for arg in argv])
        return run_argv(argv, prompt)
    if judge == "codex":
        with tempfile.NamedTemporaryFile(prefix="goal-judge-", suffix=".txt") as output:
            run_argv(["codex", "exec", "--ephemeral", "--sandbox", "read-only",
                      "--output-last-message", output.name, "-"], prompt)
            return Path(output.name).read_text(encoding="utf-8")
    if judge == "claude":
        return run_argv(["claude", "-p", prompt])
    if judge == "grok":
        return run_argv(["grok", "-p", prompt])
    if judge == "antigravity":
        return run_argv(["agy", "-p", prompt])
    raise SystemExit("그 밖의 CLI는 --command로 실행 명령을 지정하세요. "
                     "프롬프트를 인자로 받는 CLI는 명령 안에 {prompt} 자리표시자를 쓰세요.")


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
    parser.add_argument("--judge", choices=("codex", "claude", "grok", "antigravity"), default="codex")
    parser.add_argument("--model", help="결과 파일명과 judgeModel에 남길 기록용 모델 라벨. CLI에는 전달하지 않음")
    parser.add_argument("--input", default=str(EVALS / "results"), help="결과 JSONL 또는 results 디렉터리")
    parser.add_argument("--output", help="judge JSONL 출력 경로. 지정하면 평가 대상 모델과 무관하게 한 파일에 쓴다")
    parser.add_argument("--command", help="judge CLI 명령. 프롬프트는 stdin으로 전달")
    parser.add_argument("--limit", type=int, default=0, help="평가할 최대 실행 수. 0이면 전체")
    parser.add_argument("--retry-failed", action="store_true",
                        help="이전 judge 실행에서 실패한 run만 다시 평가한다. results 디렉터리 전체를 훑는다")
    parser.add_argument("--dry-run", action="store_true", help="첫 번째 judge 프롬프트만 출력")
    args = parser.parse_args()

    retry_ids = failed_run_ids() if args.retry_failed else None
    if retry_ids is not None and not retry_ids:
        raise SystemExit("다시 평가할 실패 레코드가 없습니다.")

    paths = result_files(Path(args.input).resolve(), use_all=args.retry_failed)
    rows = []
    for path in paths:
        rows += [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    cases, traces = load_cases(), load_traces()
    rubric = RUBRIC.read_text(encoding="utf-8")
    selected, seen = [], set()
    for row in rows:
        run_id = row.get("run_id")
        if run_id in seen or (retry_ids is not None and run_id not in retry_ids):
            continue
        case = cases.get(row.get("case_id"))
        payload = extracted_payload(traces.get(run_id))
        if case and payload and row.get("source") != "live":
            seen.add(run_id)
            selected.append((row, case, payload))
    if not selected:
        raise SystemExit("trace와 골든셋 케이스가 모두 있는 평가 대상을 찾지 못했습니다.")
    found = len(selected)
    if args.limit > 0:
        selected = selected[: args.limit]

    if args.dry_run:
        print(judge_input(*selected[0], rubric))
        return

    stamp = datetime.now().strftime("%Y%m%dT%H%M%S%z")
    judge_model = args.model or os.environ.get("JUDGE_MODEL") or "default"
    # 평가 대상 모델별로 파일을 나눈다. judge 라벨만으로는 파일명이 서로 구분되지 않는다.
    groups = {}
    for item in selected:
        groups.setdefault("" if args.output else (item[0].get("model") or "unknown"), []).append(item)
    print(f"평가 대상 {len(selected)}건 (후보 {found}건 · 출력 파일 {len(groups)}개)")

    index = 0
    for target, items in groups.items():
        output = (Path(args.output).resolve() if args.output else EVALS / "results" / "judges" /
                  f"{stamp}-{slug(target)}-{args.judge}-{slug(judge_model)}.jsonl")
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("w", encoding="utf-8") as handle:
            for row, case, payload in items:
                index += 1
                print(f"[{index}/{len(selected)}] {row.get('model')} · {row.get('case_id')}")
                result = {
                    "runId": row.get("run_id"), "caseId": row.get("case_id"), "model": row.get("model"),
                    "recipe": row.get("recipe"), "judge": args.judge, "judgeModel": judge_model, "rubricVersion": "v1",
                }
                try:
                    result["evaluation"] = parse_json(run_cli(args.judge, judge_input(row, case, payload, rubric), args.command))
                    result["status"] = "ok"
                except (OSError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
                    result["status"], result["error"] = "error", str(error)
                handle.write(json.dumps(result, ensure_ascii=False) + "\n")
        print(f"judge 결과 저장: {output}")


if __name__ == "__main__":
    main()
