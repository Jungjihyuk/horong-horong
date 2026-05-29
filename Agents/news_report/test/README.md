# News report tests

`Agents/news_report/test`는 Python sidecar의 테스트와 실행 fixture를 모아둔다.

## 폴더 구분

- `unit/`: 함수와 클래스 단위 테스트. 외부 네트워크, 실제 CLI, Ollama 서버를 사용하지 않는다.
- `integration/`: 여러 모듈 조합 테스트. 가능하면 fake provider/connector로 외부 의존성을 피한다.
- `e2e/`: 실제 runner 실행 흐름 테스트. 외부 provider, 네트워크 connector, 파일 출력을 포함할 수 있다.
- `fixtures/`: 테스트와 수동 smoke test에 사용하는 request JSON, 샘플 입력, 실행 안내를 둔다.

## 기본 실행

```bash
cd Agents/news_report
.venv/bin/pytest -m unit test -q
```

기본 테스트는 빠르고 재현 가능한 `unit` 테스트를 중심으로 실행한다.

## E2E 실행

E2E는 로컬 환경에 따라 실패할 수 있으므로 기본 테스트에서 분리한다.

```bash
cd Agents/news_report
HORONG_RUN_E2E=1 .venv/bin/pytest -m e2e test/e2e -q
```

E2E는 실제 `ollama`, `codex`, `claude`, 네트워크 RSS 수집 같은 외부 상태에 의존할 수 있다.
