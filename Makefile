# Test
unit:
	cd Agents/news_report && uv run pytest -m unit test -q
e2e:
	cd Agents/news_report && HORONG_RUN_E2E=1 uv run pytest -m e2e test/e2e -q
e2e-progress:
	cd Agents/news_report && HORONG_RUN_E2E=1 HORONG_E2E_PROGRESS=1 uv run pytest -m e2e test/e2e -s -q
ollama-test: 
	cd Agents/news_report && uv run runner.py --request test/fixtures/requests/ollama-all-sources-request.json --result /tmp/Horong/horong-ollama-result.json --log /tmp/Horong/horong-ollama-run.log --debug-log /tmp/Horong/horong-ollama-debug.log --trace-log /tmp/Horong/horong-ollama-trace.jsonl
codex-test: 
	cd Agents/news_report && uv run runner.py --request test/fixtures/requests/codex-all-sources-request.json --result /tmp/Horong/horong-codex-result.json --log /tmp/Horong/horong-codex-run.log --debug-log /tmp/Horong/horong-codex-debug.log --trace-log /tmp/Horong/horong-codex-trace.jsonl
claude-test: 
	cd Agents/news_report && uv run runner.py --request test/fixtures/requests/claude-all-sources-request.json --result /tmp/Horong/horong-claude-result.json --log /tmp/Horong/horong-claude-run.log --debug-log /tmp/Horong/horong-claude-debug.log --trace-log /tmp/Horong/horong-claude-trace.jsonl
antigravity-test: 
	cd Agents/news_report && uv run runner.py --request test/fixtures/requests/antigravity-all-sources-request.json --result /tmp/Horong/horong-antigravity-result.json --log /tmp/Horong/horong-antigravity-run.log --debug-log /tmp/Horong/horong-antigravity-debug.log --trace-log /tmp/Horong/horong-antigravity-trace.jsonl
gemini-test:
	cd Agents/news_report && uv run runner.py --request test/fixtures/requests/gemini-all-sources-request.json --result /tmp/Horong/horong-gemini-result.json --log /tmp/Horong/horong-gemini-run.log --debug-log /tmp/Horong/horong-gemini-debug.log --trace-log /tmp/Horong/horong-gemini-trace.jsonl

# Evals
ollama-run-metrics:
	mkdir -p /tmp/Horong/metrics
	cd Agents/news_report && uv run python -m evals.research_run_metrics --meta /tmp/horong-news-ollama-all-sources/data/meta/*.json --trace /tmp/Horong/horong-ollama-trace.jsonl --output /tmp/Horong/metrics/ollama.json
codex-run-metrics:
	mkdir -p /tmp/Horong/metrics
	cd Agents/news_report && uv run python -m evals.research_run_metrics --meta /tmp/horong-news-codex-all-sources/data/meta/*.json --trace /tmp/Horong/horong-codex-trace.jsonl --output /tmp/Horong/metrics/codex.json
claude-run-metrics:
	mkdir -p /tmp/Horong/metrics
	cd Agents/news_report && uv run python -m evals.research_run_metrics --meta /tmp/horong-news-claude-all-sources/data/meta/*.json --trace /tmp/Horong/horong-claude-trace.jsonl --output /tmp/Horong/metrics/claude.json
antigravity-run-metrics:
	mkdir -p /tmp/Horong/metrics
	cd Agents/news_report && uv run python -m evals.research_run_metrics --meta /tmp/horong-news-antigravity-all-sources/data/meta/*.json --trace /tmp/Horong/horong-antigravity-trace.jsonl --output /tmp/Horong/metrics/antigravity.json
gemini-run-metrics:
	mkdir -p /tmp/Horong/metrics
	cd Agents/news_report && uv run python -m evals.research_run_metrics --meta /tmp/horong-news-gemini-all-sources/data/meta/*.json --trace /tmp/Horong/horong-gemini-trace.jsonl --output /tmp/Horong/metrics/gemini.json
compare-provider-metrics:
	@METRICS_ARGS="$$(find /tmp/Horong/metrics -maxdepth 1 -name '*.json' ! -name 'provider-comparison.json' -exec printf ' --metrics %s' {} \;)"; \
	if [ -z "$$METRICS_ARGS" ]; then \
		echo "No provider metrics found. Run one of: make ollama-run-metrics, make codex-run-metrics, ..."; \
		exit 1; \
	fi; \
	cd Agents/news_report && uv run python -m evals.compare_provider_metrics $$METRICS_ARGS --output /tmp/Horong/metrics/provider-comparison.json

# 앱이 생성한 data 폴더에서 최신 meta+trace를 찾아 run metrics(구조화 출력 신뢰도 포함)를 집계한다.
# BASE는 환경/설정에 따라 다르므로 인자로 받는다. (= <agent root>/.../data, 보통 traces/ meta/ 하위 폴더를 가진 곳)
# 사용: make run-metrics BASE="/path/to/data"
# 예:   make run-metrics BASE="$$HOME/Documents/.../Experiment/Reports/data"
run-metrics:
	@if [ -z "$(BASE)" ]; then \
		echo "Usage: make run-metrics BASE=\"/path/to/data\"  (traces/, meta/ 를 포함한 폴더)"; \
		exit 1; \
	fi; \
	META="$$(ls -t "$(BASE)"/meta/*.json 2>/dev/null | head -1)"; \
	TRACE="$$(ls -t "$(BASE)"/traces/*.jsonl 2>/dev/null | head -1)"; \
	if [ -z "$$TRACE" ]; then \
		echo "trace 파일을 찾지 못했습니다: $(BASE)/traces/*.jsonl"; \
		exit 1; \
	fi; \
	if [ -z "$$META" ]; then \
		echo "meta 파일을 찾지 못했습니다: $(BASE)/meta/*.json (job이 끝나야 meta가 생성됩니다)"; \
		exit 1; \
	fi; \
	echo "meta : $$META"; \
	echo "trace: $$TRACE"; \
	cd Agents/news_report && uv run python -m evals.research_run_metrics --meta "$$META" --trace "$$TRACE"
