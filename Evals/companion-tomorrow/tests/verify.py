import json
import sys
from pathlib import Path
sys.path.insert(0, "/tmp")
from companion_eval import CASES, grade, annotate_record

record = json.loads(Path("/tmp/observed.json").read_text())
test = next(x for x in CASES if x["id"] == "tomorrow")
scores = grade(test, record)
if scores.get("error") == "infrastructure":
    raise RuntimeError("Inference infrastructure error, no model score")
output = Path("/logs/verifier")
output.mkdir(parents=True, exist_ok=True)
(output / "scores.json").write_text(json.dumps(scores, ensure_ascii=False))
(output / "review.json").write_text(json.dumps(annotate_record(test, record), ensure_ascii=False, indent=2))
# reward는 의도/실행의 객관적 부분만 의미한다. 상담 의미 품질은 별도 검토한다.
(output / "reward.txt").write_text(str(int(scores["intent"] and scores["execution"])))
