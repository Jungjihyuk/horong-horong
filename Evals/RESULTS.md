# 평가 결과 보관 - 컴패니언 의도 평가

- 컴패니언 의도 평가는 Lantern 저장소에서 옮겨 왔다 (2026-09-29). 원본 커밋은 `834de38` · `5134d6f` · `2fde8cc` (2026-09-18)이다.
- 평가기(`companion_eval.py`)는 앱 코드를 불러오지 않는다. 로컬 Ollama를 직접 호출하고 평가용 가짜 일정 저장소로 실행하는 격리 평가다. 그래서 저장소를 옮겨도 같은 조건으로 돈다.
- 과제·판정 기준: `companion-intent/task.md`, `harness.md`, `environment.md`, `support-audit.md`
- 목표 추천 골든셋 결과는 이 문서가 아니라 `results/baselines/eval-v1/`에 있다.

## 버전

- `v1-baseline`: 프롬프트·문맥 개선 전 최초 비교 기준. `results/companion/v1-baseline/`에 manifest와 평가 스냅샷을 보존한다.
- `v2-eval-hardening`: 채점 강화. 내일 일정 2개를 모두 찾는지 본다. 저장된 목표와 대화 속 목표를 구분하는지 본다. 쓰지 않는 인자까지 검사한다. 프롬프트는 v1 그대로다.
- `v3-prompt-context`: 현재 실행 코드. 프롬프트와 문맥만 개선했고, v2의 사례·채점·추론 설정은 그대로다.
  - 도구를 실행하지 않은 것과 조회 결과가 비어 있는 것을 구분한다.
  - 정보 출처를 표시한다.
  - 현재 날짜와 요일을 준다.
  - 답변용 근거에서 ID를 빼고, 간결하게 답하도록 지시한다.
- v2·v3의 원시 결과는 Lantern 로컬에만 있고 여기로 옮기지 않았다. 이 저장소의 결과는 새로 쌓는다.

## 규칙

- 완료한 결과는 덮어쓰지 않는다. 같은 조건을 반복하면 새 run 번호를 쓴다. 이미 있는 출력 폴더는 비어 있어도 거부한다.
- 사례나 채점 기준을 바꾸면 manifest에 적는다. 기준이 다른 버전끼리 점수를 개선율로 비교하지 않는다.
- manifest의 `completed`는 실행 완료라는 뜻이지 모델 합격이 아니다. 인프라 오류와 답변 의미 품질은 따로 확인한다.
- `task.md` 기준으로 한 사례는 모델·설정당 3회 모두 통과해야 통과로 기록한다. 1회 결과로 합격을 말하지 않는다.
- 대용량 원시 결과는 로컬에만 둔다. Git에는 버전별 manifest와 평가 스냅샷만 올린다 (`.gitignore`).

## 실행 (v3, Ollama 실행 상태에서 하나씩 순차 실행)

```bash
python3 Evals/companion_eval.py --model gemma4:26b --output Evals/results/companion/v3-prompt-context/gemma4-26b/run-01
python3 Evals/companion_eval.py --model gemma4:e4b --output Evals/results/companion/v3-prompt-context/gemma4-e4b/run-01
python3 Evals/companion_eval.py --model qwen3:8b --output Evals/results/companion/v3-prompt-context/qwen3-8b/run-01
python3 Evals/companion_eval.py --model qwen3.5:9b --output Evals/results/companion/v3-prompt-context/qwen3.5-9b/run-01
```

- 반복 실행은 `run-02`, `run-03`처럼 새 run 번호를 지정한다.
- 각 run에는 15개 사례 JSON, manifest, 실행 코드 사본이 생긴다. 사례 JSON은 manifest의 `completed_cases`로 구분한다.
- 단위 테스트: `cd Evals && python3 -m unittest test_companion_eval`
