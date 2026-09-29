"""Mac의 로컬 추론과 네트워크 없는 Harbor 검증 컨테이너를 연결한다."""
import asyncio
import hashlib
import json
from pathlib import Path

from harbor.agents.base import BaseAgent
from Evals.companion_eval import run_case


class CompanionAgent(BaseAgent):
    @staticmethod
    def name():
        return "companion-local-prototype"

    def version(self):
        return "0.1"

    async def setup(self, environment):
        # 모델에는 컨테이너나 호스트 셸 도구를 노출하지 않는다.
        await environment.upload_file(Path(__file__).with_name("companion_eval.py"), "/tmp/companion_eval.py")
        await environment.upload_file(Path(__file__).with_name("test_companion_eval.py"), "/tmp/test_companion_eval.py")
        result = await environment.exec("python3 -m unittest discover -s /tmp -p test_companion_eval.py -v")
        if result.return_code != 0:
            raise RuntimeError("Verifier calibration failed")

    async def run(self, instruction, environment, context):
        # instruction은 사용자 입력이며 숨겨진 채점 기준을 읽지 않는다.
        test = {"id": "trial", "message": instruction.strip(), "history": []}
        record = await asyncio.to_thread(run_case, test, self.model_name or "qwen3.5:9b")
        record["source_sha256"] = hashlib.sha256(Path(__file__).with_name("companion_eval.py").read_bytes()).hexdigest()
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        path = (self.logs_dir / "observed.json").resolve()
        path.write_text(json.dumps(record, ensure_ascii=False, indent=2))
        await environment.upload_file(path, "/tmp/observed.json")
        context.metadata = {"provider": "ollama", "prototype": True, "record": str(path)}
        if record.get("infrastructure_error"):
            raise RuntimeError(record["infrastructure_error"])
