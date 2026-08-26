# App build
#
# mlx-swift 의 CudaBuild 플러그인과 mlx-swift-lm 의 매크로는 Xcode.app 에서는 한 번
# 신뢰하면 끝이지만, CLI 빌드에는 신뢰 기록이 없어 매번 검증에서 멈춘다.
# 플래그를 여기 묶어두면 `make build` 한 번으로 끝난다.
XCODEBUILD_FLAGS = -project HorongHorong.xcodeproj \
	-destination 'platform=macOS' \
	-skipPackagePluginValidation \
	-skipMacroValidation

generate:
	xcodegen generate

build: generate
	xcodebuild $(XCODEBUILD_FLAGS) -scheme HorongHorong -configuration Debug build

build-release: generate
	xcodebuild $(XCODEBUILD_FLAGS) -scheme HorongHorong -configuration Release build

build-appstore: generate
	xcodebuild $(XCODEBUILD_FLAGS) -scheme HorongHorongAppStore -configuration Release build

app-test: generate
	xcodebuild $(XCODEBUILD_FLAGS) -scheme HorongHorong -configuration Debug test

# Release
#
# 사람이 정하는 값은 VERSION 하나뿐이다. 빌드 번호·서명값·크기·날짜·릴리즈 노트는
# 전부 앞 단계 산출물에서 파생된다. 절차는
# docs/5. 운영/프로젝트 운영/12. 기술 문서/Build/release-checklist-and-automation-design.md 참고.
#
#   make release VERSION=0.2.3 SIGN_IDENTITY="Apple Development: ..."
#   make release-draft VERSION=0.2.3   ← 확인하며 끊어 갈 때 (권장)
release:
	VERSION=$(VERSION) Scripts/release.sh

# 빌드·서명·패키징까지만 확인한다. 커밋·태그·푸시·배포는 하지 않는다.
release-dry-run:
	VERSION=$(VERSION) DRY_RUN=1 Scripts/release.sh

# GitHub Release 를 «초안» 으로 만들고 멈춘다. appcast 는 배포하지 않으므로
# 사용자에게는 아직 아무것도 노출되지 않는다.
release-draft:
	VERSION=$(VERSION) DRAFT=1 Scripts/release.sh

# 초안을 확인한 뒤 마무리한다 — 초안 공개 → appcast 배포 → main→dev 백머지.
release-publish:
	VERSION=$(VERSION) PUBLISH_ONLY=1 Scripts/release.sh

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

# Generate static HTML matrix dashboard from evaluation JSONL
eval-report:
	python3 Evals/eval-report.py $(if $(INPUT),--input "$(INPUT)",) --output Evals/eval-report.html

# 모델 × 컨텍스트 조합을 순차 평가한다. 기본 조합은 Evals/goal-eval-matrix.json에서 고친다.
goal-eval-matrix: generate
	python3 Evals/run-goal-eval-matrix.py $(if $(MATRIX),--matrix "$(MATRIX)",)

# 기존 골든셋 실행 결과에 의미 품질 루브릭을 적용한다. 모델 실행·결정적 채점과 분리한다.
# MODEL은 CLI에 전달하지 않는 기록용 라벨이다. 실제 judge 모델은 CLI의 현재 선택을 따른다.
# 예: make llm-judge JUDGE=codex MODEL=gpt-5.6-sol LIMIT=5
llm-judge:
	python3 Evals/run-llm-judge.py --judge $(or $(JUDGE),codex) $(if $(MODEL),--model "$(MODEL)",) $(if $(INPUT),--input "$(INPUT)",) $(if $(LIMIT),--limit "$(LIMIT)",) $(if $(COMMAND),--command "$(COMMAND)",)

# 실사용(Release) DB를 디버그(Debug) DB로 복사
copy-prod-db:
	@mkdir -p "$$HOME/Library/Application Support/HorongHorong-Debug/Stores"
	@cp -f "$$HOME/Library/Application Support/HorongHorong/Stores/default.store"* "$$HOME/Library/Application Support/HorongHorong-Debug/Stores/" 2>/dev/null || true
	@cp -rf "$$HOME/Library/Application Support/HorongHorong/JourneyImages" "$$HOME/Library/Application Support/HorongHorong-Debug/" 2>/dev/null || true
	@echo "✅ 릴리스 DB 및 이미지를 디버그 저장소(HorongHorong-Debug)로 복사했습니다."
