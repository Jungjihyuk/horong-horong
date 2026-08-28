#!/bin/bash
# promptfoo exec provider — 추론을 다시 돌리지 않고 최신 결과에서 조회한다.
#
# 추론은 XCTest(GoalSuggestionEvalTests)가 이미 수행해 Evals/results/*.jsonl 에 남긴다.
# 여기서 다시 AFM 을 부르면 케이스마다 수 초씩 걸리고, 매 실행 결과가 달라져 비교가 불가능해진다.
#
# 인자: $1 = caseName (promptfooconfig 의 prompt 가 "{{caseName}}" 이므로 그대로 넘어온다)
set -euo pipefail
CASE_NAME="${1:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LATEST="$(ls -1 "$ROOT"/Evals/results/*.jsonl 2>/dev/null | sort | tail -1)"

if [ -z "$LATEST" ]; then
  echo '{"error":"결과 파일이 없습니다. 먼저 make eval-golden 을 실행하세요."}'
  exit 0
fi

python3 - "$LATEST" "$CASE_NAME" <<'PY'
import json, sys
path, name = sys.argv[1], sys.argv[2]
for line in open(path):
    line = line.strip()
    if not line:
        continue
    row = json.loads(line)
    if row.get("caseName") == name:
        print(json.dumps(row, ensure_ascii=False))
        break
else:
    print(json.dumps({"error": f"케이스를 찾지 못했습니다: {name}"}, ensure_ascii=False))
PY
