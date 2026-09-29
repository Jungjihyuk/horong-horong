# 평가 결과 보관 - 컴패니언 의도 평가

- 컴패니언 의도 평가는 Lantern 저장소에서 옮겨 왔다 (2026-09-29). 원본 커밋은 `834de38` · `5134d6f` · `2fde8cc` (2026-09-18)이다.
- 평가기(`companion_eval.py`)는 앱 코드를 불러오지 않는다. 로컬 Ollama를 직접 호출하고 평가용 가짜 일정 저장소로 실행하는 격리 평가다. 그래서 저장소를 옮겨도 같은 조건으로 돈다.
- 과제·판정 기준: `companion-intent/task.md`, `harness.md`, `environment.md`, `support-audit.md`
- 목표 추천 골든셋 결과는 이 문서가 아니라 `results/baselines/eval-v1/`에 있다.

## 버전

- `v1-baseline`: 프롬프트·문맥 개선 전 최초 비교 기준. `results/companion/v1-baseline/`에 manifest와 평가 스냅샷을 보존한다.
- `v2-eval-hardening`: 채점 강화. 내일 일정 2개를 모두 찾는지 본다. 저장된 목표와 대화 속 목표를 구분하는지 본다. 쓰지 않는 인자까지 검사한다. 프롬프트는 v1 그대로다.
- `v3-prompt-context`: 프롬프트와 문맥만 개선했고, v2의 사례·채점·추론 설정은 그대로다. 코드와 실행 목록은 `results/companion/v3-prompt-context/snapshot/`·`manifest.json`에 보관한다.
  - 도구를 실행하지 않은 것과 조회 결과가 비어 있는 것을 구분한다.
  - 정보 출처를 표시한다.
  - 현재 날짜와 요일을 준다.
  - 답변용 근거에서 ID를 빼고, 간결하게 답하도록 지시한다.
- `v3-native-tools`: v3의 사례·채점·문맥 규칙을 그대로 쓰고, 판단만 Ollama 네이티브 tool calling으로 바꾼 비교용 버전 (`companion_eval_native.py`). 보관 위치는 v3와 같은 방식.
- `v4-schedule-rule`: 현재 실행 코드. v3에 판단 규칙 3줄만 더했다. 사례·채점·추론 설정은 그대로다.
  - 이전 발언 확인(`history_recall`)은 사용자가 앞서 자기가 한 말을 물을 때만 쓴다.
  - 앞으로 있을 일정을 묻는 질문은 표현이 달라도 `schedule_lookup`이다. 예시는 시험 사례에 없는 표현만 쓴다.
  - `next_only=true`이면 `after`는 항상 비운다.
- v2의 원시 결과, 그리고 Lantern에서 1회 실행한 v3 원시 결과는 Lantern 로컬에만 있다. 이 저장소의 결과는 새로 쌓는다.

## 규칙

- 완료한 결과는 덮어쓰지 않는다. 같은 조건을 반복하면 새 run 번호를 쓴다. 이미 있는 출력 폴더는 비어 있어도 거부한다.
- 사례나 채점 기준을 바꾸면 manifest에 적는다. 기준이 다른 버전끼리 점수를 개선율로 비교하지 않는다.
- manifest의 `completed`는 실행 완료라는 뜻이지 모델 합격이 아니다. 인프라 오류와 답변 의미 품질은 따로 확인한다.
- `task.md` 기준으로 한 사례는 모델·설정당 3회 모두 통과해야 통과로 기록한다. 1회 결과로 합격을 말하지 않는다.
- 대용량 원시 결과는 로컬에만 둔다. Git에는 버전별 manifest와 평가 스냅샷만 올린다 (`.gitignore`).

## v3 실행 기록 - JSON 양식 (2026-09-29, 이 저장소에서 실행)

모델당 3회(`run-01`~`run-03`), 사례 15개. 통과 = 의도(행동·인자)와 실행(도구 호출·최종 상태)이 모두 맞은 경우다. 답변 문장의 의미 품질은 자동 판정하지 않았다 (`review_required`).

| 모델 | 회차별 통과 | 3회 모두 통과 | 사례당 시간 중앙값 | 3회 모두 실패한 사례 |
|---|---|---|---|---|
| gemma4:26b | 15 · 15 · 15 | 15/15 | 7.7초 | 없음 |
| qwen3.5:9b | 15 · 15 · 15 | 15/15 | 6.4초 | 없음 |
| gemma4:e4b | 14 · 14 · 14 | 14/15 | 4.0초 | `next`: 바로 다음 일정 요청을 `history_recall`로 판단 |
| qwen3:8b | 14 · 14 · 14 | 14/15 | 3.9초 | `next`: 행동은 맞지만 `after`에 현재 시각(10:00)을 넣음 |

- 사례당 시간은 판단·답변 두 번의 호출을 합친 값이고, 첫 사례에는 모델 로딩 시간이 들어 있다.
- 온도 0이라 세 회차의 판정이 같았다. 흔들린 사례는 없고, 틀린 사례는 매번 같은 방식으로 틀렸다.
- 인프라 오류는 없었다.
- 원시 결과: `results/companion/v3-prompt-context/<모델>/run-0N/` (로컬 보관)

## 판단 방식 비교: JSON 양식 vs 네이티브 도구 (2026-09-29, 이 저장소에서 실행)

- JSON 양식 (`v3-prompt-context`, `companion_eval.py`): 모델이 매번 `{행동, 날짜, 시간, 제목, 다음 것만}` 양식을 채우고, 코드가 읽어 도구를 실행한다. 모델 호출은 항상 2회다.
- 네이티브 도구 (`v3-native-tools`, `companion_eval_native.py`): Ollama `tools`에 도구 4개를 등록하고, 모델이 부를지·무엇을·어떤 값으로 부를지 정한다. 도구 결과는 같은 `answer_context`로 `tool` 메시지에 담는다. 도구가 필요 없으면 호출은 1회다.
- 사례·가짜 저장소·채점 기준·답변 규칙은 같다. 네이티브 방식에서는 도구가 필요 없는 세 행동(대화·되묻기·이전 발언 확인)을 "도구를 안 부름"으로 함께 채점한다. 판단 규칙은 같은 내용을 시스템 지시와 도구 설명으로 옮겼고, 문구는 다르다.
- 모델당 3회. 세 회차의 판정은 두 방식 모두 같았다.

| 모델 | JSON 양식 | 네이티브 도구 | 사례당 시간 중앙값 (JSON → 네이티브) |
|---|---|---|---|
| gemma4:26b | 15/15 | 15/15 | 7.7초 → 3.8초 |
| qwen3.5:9b | 15/15 | 12/15 | 6.4초 → 3.8초 |
| qwen3:8b | 14/15 | 13/15 | 3.9초 → 3.3초 |
| gemma4:e4b | 14/15 | 10/15 | 4.0초 → 1.6초 |

네이티브 방식에서 틀린 사례 (3회 모두 같은 방식으로 틀림):

- gemma4:e4b: 오늘·내일 일정 조회, 할일 추가, 목표 조회, 사용법 조회에서 도구를 부르지 않고 "조회해 드릴까요?"처럼 되물음
- qwen3.5:9b: 할일 추가에서 도구 없이 "추가해 드릴게요"라고만 답함(저장 안 됨). 사용법 질문에서 안내 자료를 조회하지 않고 스스로 설명함. "오늘 오후 2시 이후"에서 날짜를 빠뜨리고 시간 조건만 넣음(답변도 비어 있음)
- qwen3:8b: 할일 추가에서 말하지 않은 시간(10:00, 현재 시각)을 넣고 그 시간에 추가했다고 답함. 목표 조회에서 도구 없이 되물음
- 반대로 "지금 바로 다음 일정" 사례는 네이티브 방식에서 네 모델 모두 통과했다 (JSON 양식에서는 gemma4:e4b·qwen3:8b가 틀림)

읽는 법:

- 네이티브 방식의 주된 실패는 "불러야 할 도구를 안 부름"이다. 되묻기(e4b)는 불편하지만 안전한 편이다. 도구 없이 설명하거나 "추가해 드릴게요"라고 답하는 경우(qwen3.5:9b)는 근거 없는 답이 될 수 있어 더 위험하다.
- JSON 양식은 매번 행동을 고르게 강제해서, 중간 크기 로컬 모델에서 더 안정적이었다.
- 네이티브 방식이 빠른 것은 주로 도구가 필요 없는 사례에서 호출이 1회로 끝나기 때문이다.
- 네이티브 방식으로 전 사례를 통과한 것은 gemma4:26b뿐이다.
- 원시 결과: `results/companion/v3-native-tools/<모델>/run-0N/` (로컬 보관). 단위 테스트: `cd Evals && python3 -m unittest test_companion_eval_native`

## v4 회귀 평가 - JSON 양식 (2026-09-29, 이 저장소에서 실행)

v3에서 gemma4:e4b·qwen3:8b가 "바로 다음 일정" 사례를 매번 틀려서 판단 규칙 3줄을 더했다. 같은 15개 사례를 모델당 3회 돌려, 고쳐진 사례와 새로 깨진 사례를 v3와 비교했다.

| 모델 | v3 → v4 (3회 모두 통과) | 고쳐진 사례 | 새로 깨진 사례 | v4 사례당 시간 중앙값 |
|---|---|---|---|---|
| gemma4:e4b | 14 → **15** | `next` | 없음 | 3.8초 |
| qwen3:8b | 14 → **15** | `next` | 없음 | 3.7초 |
| gemma4:26b | 15 → 15 | - | 없음 | 8.1초 |
| qwen3.5:9b | 15 → **14** | - | `after` | 6.3초 |

- qwen3.5:9b는 v4에서 "오늘 오후 2시 이후 일정 보여줘"의 날짜를 빠뜨리고 시간 조건만 넣었다(3회 모두). 네이티브 도구 방식에서 같은 모델이 틀린 방식과 같다.
- 한 모델을 고친 규칙이 다른 모델의 다른 사례를 깨뜨렸다. 규칙을 바꿀 때마다 모든 모델·사례를 다시 돌려야 하는 이유다.
- 앱 기본 모델(`Constants.defaultCompanionOllamaModel = gemma4:e4b`)은 v4에서 전 사례를 통과했고 회귀가 없다.
- 원시 결과: `results/companion/v4-schedule-rule/<모델>/run-0N/` (로컬 보관)

## 실행 (v4, Ollama 실행 상태에서 하나씩 순차 실행)

```bash
python3 Evals/companion_eval.py --model gemma4:26b --output Evals/results/companion/v4-schedule-rule/gemma4-26b/run-01
python3 Evals/companion_eval.py --model gemma4:e4b --output Evals/results/companion/v4-schedule-rule/gemma4-e4b/run-01
python3 Evals/companion_eval.py --model qwen3:8b --output Evals/results/companion/v4-schedule-rule/qwen3-8b/run-01
python3 Evals/companion_eval.py --model qwen3.5:9b --output Evals/results/companion/v4-schedule-rule/qwen3.5-9b/run-01
```

- 이미 끝난 버전은 해당 버전 폴더의 `snapshot/` 코드로 재현한다. 현재 코드를 이전 버전 경로에 실행하지 않는다.
- 네이티브 도구 비교: `python3 Evals/companion_eval_native.py --model <모델> --output Evals/results/companion/v3-native-tools/<모델>/run-0N`

- 반복 실행은 `run-02`, `run-03`처럼 새 run 번호를 지정한다.
- 각 run에는 15개 사례 JSON, manifest, 실행 코드 사본이 생긴다. 사례 JSON은 manifest의 `completed_cases`로 구분한다.
- 단위 테스트: `cd Evals && python3 -m unittest test_companion_eval`
