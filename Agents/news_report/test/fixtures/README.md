# News report test fixtures

이 폴더는 `runner.py`를 Swift 앱 없이 직접 실행할 때 쓰는 개발용 입력 파일과
테스트 fixture를 둔다.

## 책임

- request JSON fixture 관리
- provider 비교용 입력 조건 고정
- 수동 smoke test 실행 예시 제공
- 나중에 integration/e2e 테스트에서 재사용할 샘플 입력 보관

## 원칙

- fixture는 가능한 한 작게 유지한다.
- 실제 provider나 source를 타는 fixture는 `fixtures/requests`에 두고 실행 여부는 테스트가 결정한다.
- provider별 비교 fixture는 source 조건을 맞추고 `jobId`, `provider`, `outputDir`만 다르게 둔다.

## Ollama Google News smoke test

사전 조건:

```bash
ollama serve
ollama pull qwen3:14b
```

실행:

```bash
cd Agents/news_report

.venv/bin/python runner.py \
  --request test/fixtures/requests/ollama-google-news-request.json \
  --result /tmp/horong-result.json \
  --log /tmp/horong-run.log \
  --debug-log /tmp/horong-debug.log \
  --trace-log /tmp/horong-trace.jsonl
```

확인:

```bash
cat /tmp/horong-result.json
cat /tmp/horong-run.log
cat /tmp/horong-trace.jsonl
ls -R /tmp/horong-news-ollama-google-news
```

성공 기준:

- `result.json`의 `status`가 `success` 또는 `partial_success`다.
- `reportPath`, `metaPath`가 존재한다.
- meta JSON 안에 `researchArtifacts`가 포함된다.
- trace JSONL에 `stage_started`, `stage_completed`, `artifact_written` 이벤트가 남는다.

## Ollama all sources smoke test

Google News, YouTube, 요즘IT를 함께 수집한다. 각 source에서 최대 1개만 수집하도록
작게 잡아둔 개발용 fixture다.

```bash
cd Agents/news_report

.venv/bin/python runner.py \
  --request test/fixtures/requests/ollama-all-sources-request.json \
  --result /tmp/horong-all-sources-result.json \
  --log /tmp/horong-all-sources-run.log \
  --debug-log /tmp/horong-all-sources-debug.log \
  --trace-log /tmp/horong-all-sources-trace.jsonl
```

확인:

```bash
cat /tmp/horong-all-sources-result.json
cat /tmp/horong-all-sources-run.log
cat /tmp/horong-all-sources-trace.jsonl
ls -R /tmp/horong-news-ollama-all-sources
```

주의:

- YouTube fixture는 `Google Developers` 채널을 사용한다.
- `dateRangeHours`는 YouTube 최신 영상이 걸릴 가능성을 높이기 위해 168시간으로 둔다.
- 특정 source가 네트워크나 RSS 문제로 실패해도 runner는 가능한 source만으로
  `partial_success`를 반환할 수 있다.

## Provider comparison fixtures

같은 source 조건에서 provider만 바꿔 실행할 수 있도록 fixture를 나눠뒀다.

| Provider | Request fixture |
|---|---|
| Ollama | `test/fixtures/requests/ollama-all-sources-request.json` |
| Codex CLI | `test/fixtures/requests/codex-all-sources-request.json` |
| Claude CLI | `test/fixtures/requests/claude-all-sources-request.json` |
| Gemini CLI | `test/fixtures/requests/gemini-all-sources-request.json` |
| Opencode CLI | `test/fixtures/requests/opencode-all-sources-request.json` |
| Antigravity CLI | `test/fixtures/requests/antigravity-all-sources-request.json` |

실행 예시:

```bash
cd Agents/news_report

.venv/bin/python runner.py \
  --request test/fixtures/requests/codex-all-sources-request.json \
  --result /tmp/horong-codex-result.json \
  --log /tmp/horong-codex-run.log \
  --debug-log /tmp/horong-codex-debug.log \
  --trace-log /tmp/horong-codex-trace.jsonl
```

CLI provider는 각 명령(`codex`, `claude`, `gemini`, `opencode`, `agy`)이 로컬에서
로그인되어 있고 PATH에서 실행 가능해야 한다.
