# E2E tests

`e2e/`는 실제 사용자 실행 흐름에 가까운 테스트를 둔다.

## 책임

- `runner.py`를 실제 subprocess 또는 실제 명령 흐름으로 실행한다.
- request fixture를 사용해 result/report/meta/trace 파일 생성 여부를 확인한다.
- provider별 smoke test를 둘 수 있다.

## 원칙

- 실제 Ollama, CLI agent, 네트워크 connector에 의존할 수 있다.
- 기본 test run에서는 실행하지 않는다.
- `HORONG_RUN_E2E=1` 같은 명시적 opt-in 조건을 둔다.
- 결과 품질 평가는 여기서 깊게 하지 않고, “끝까지 실행되는가”를 먼저 본다.

## 실행

```bash
cd Agents/news_report
HORONG_RUN_E2E=1 .venv/bin/pytest -m e2e test/e2e -q
```

실제 provider 응답이 오래 걸릴 때는 progress 출력을 켤 수 있다.

```bash
HORONG_RUN_E2E=1 HORONG_E2E_PROGRESS=1 .venv/bin/pytest -m e2e test/e2e -s -q
```

`HORONG_E2E_PROGRESS=1`은 `trace.jsonl`에 새로 기록되는 이벤트를 콘솔에 출력한다.
pytest가 출력을 캡처하지 않도록 `-s`를 함께 붙인다.

## Smoke test 성공 기준

- 프로세스 exit code가 0이다.
- result JSON이 생성된다.
- `status`가 `success` 또는 `partial_success`다.
- report/meta 파일 경로가 result에 포함된다.
- trace JSONL에 주요 이벤트가 남는다.
