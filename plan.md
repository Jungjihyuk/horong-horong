# 골든셋 평가 — 현황과 다음 작업

> 작성: 2026-08-26
> 범위: 목표 추천(주간·월간) 골든셋 평가 파이프라인
> 관련 문서: `docs/5. 운영/프로젝트 운영/12. 기술 문서/Bug/incident-20260825-json-schema-key-order-collapses-ollama-output.md`

---

## 1. 지금까지 끝난 것

### 1-1. JSON 스키마 키 순서 사고 — 원인 확정 및 수정 완료

**증상**: 골든셋 62건 중 `noSuggestion` 56건. 모델 원문이 `{"resultType": "suggestions"}` 14토큰으로 끝남.

**원인**: `JSONEncoder`가 키 순서를 보존하지 않아 스키마의 `resultType`이 맨 뒤로 밀렸다. Ollama가 스키마를 GBNF 문법으로 바꿀 때 속성은 적힌 순서대로만 이어붙일 수 있어, 모델이 `resultType`을 먼저 쓰는 순간 `suggestions`가 등 뒤에 놓여 배열을 못 쓰고 객체가 닫혔다. 로깅 프록시로 실제 전송 바이트를 떠서 3/3 재현, `resultType`만 맨 앞으로 옮겨 3/3 정상으로 단일 변수 대조 확정.

**수정**:
- `JSONSchema.object(properties:)` — `[String: JSONSchema]` → 순서 있는 `[Property]`
- `JSONSchema`에 `stringEnum` 케이스 추가, `resultType`을 세 값으로 고정
- `Encodable` 제거 → `jsonText`로 직접 직렬화 (`JSONEncoder`로는 순서 보장 불가)
- `OllamaChatClient.body(_:format:)` — `format`만 손으로 붙여 순서를 전송까지 보존
- `JSONSchemaTests` 12개 — 실제 전송 바이트(`jsonText`) 기준으로 재작성

**검증**: 실제 모델 8케이스 8/8 정상(빈 결과 0건). 야간 매트릭스에서 `qwen3.8:27b`가 124건 완주(ok 93 / guidance 24 / noSuggestion 7).

### 1-2. 계측 배선

- `GoalSuggestionEvalTests`에 `TraceRecorder` 설치 (`Evals/results/traces/`)
- 케이스마다 다른 `runId` (`G-…-w1`, `-m1`) — 배치 전체가 한 `runId`를 쓰면 서로 덮어씀
- `defer`에서 `flush()` — 큐에 실린 쓰기가 테스트 종료로 유실되는 것 방지
- `ParseOutcome.Diagnostics.traceFacts` — 파싱 진단 7종을 원문 옆에 기록
- `rawResponse` span에 `tokensIn`/`tokensOut`

### 1-3. 평가 전용 타임아웃

- `Constants.achievementSuggestionTimeout` (제품 180초) / `achievementSuggestionEvalTimeout` (평가 350초)
- `AchievementViews.swift` 6곳에 주입 — 벽시계(`WeeklyGoalTask.run`·`MonthlyGoalTask.run`)와 URLRequest(`generateWithUsage`·`generate`) **양쪽이 같은 값**이어야 짧은 쪽이 새 벽이 되지 않음
- `HorongAI` 패키지 기본값은 180초 그대로 (패키지는 앱을 몰라야 함)

### 1-4. 리포트 — 유형별 채점 탭 4개 추가

`Evals/eval-report.py`에 기존 탭 2개를 그대로 두고 뒤에 붙임:

| 탭 | 내용 |
|---|---|
| 유형별 채점 | 능력 격자 · 유형별 분해 · 맥락 효과 · 파싱 진단 |
| 케이스별 | 행=케이스(유형별 그룹) · 열=모델 · recipe/task/유형 필터 |
| 실행 상세 | 최종 출력 + 단계별(입력·프롬프트 전문·모델 원문·추출 JSON·파싱) |
| 용어 | 지표 12종 · 실행 단계 6종 · 집계 규칙 정의 |

유형 정보는 `RunRecord`에 없어 케이스 파일과 `case_id`로 조인. **재실행 없이 기존 결과에 소급 적용**된다.

구현 중 잡은 버그: 완주 판정이 모델 이름 기준이라 옛 실행(31줄)이 섞여 6개 중 1개만 남던 것 → 실행 배치 기준으로 교체.

---

## 2. 지금 남아 있는 문제

### 2-1. 채점 지표 — 과잉 묶음의 심각도가 사라진다 ⚠️ 우선순위 높음

**사실**: 정답 묶음이 없는 케이스에서 모델이 잘못 묶으면 `pairF1 = 0`이 된다. 그런데 **"2개 지어냄"과 "5개 지어냄"이 똑같이 0**이다.

쌍 공간 혼동행렬로 보면:

| 모델 행동 | TP | FP | FN | TN | pairF1 |
|---|---|---|---|---|---|
| 안 묶음 | 0 | 0 | 0 | 전부 | **0/0 → 정의 안 됨** (코드가 1.0을 넣음) |
| [1,2,3] 묶음 | 0 | 3 | 0 | 나머지 | 0 (전부 FP) |

F1은 TN을 보지 않으므로 TN만 있는 케이스에서 정보량이 0이다. **1.0은 측정이 아니라 관례다.**

**측정 결과** — 정답 묶음 없는 38건에서 지어낸 쌍을 세면 순위가 뒤집힌다:

| 모델 | 자제 | 지어낸 묶음 | 지어낸 쌍 |
|---|---|---|---|
| appleFoundation | 0.08 | 38 | 71 |
| qwen3:1.7b | 0.66 | 15 | 59 |
| qwen3:4b | 0.32 | 29 | 76 |
| qwen3:8b | 0.58 | 20 | 58 |
| **qwen3.5:9b** | **0.42** | 30 | **95** |
| qwen3.8:27b | 0.71 | 11 | 54 |

`qwen3.5:9b`는 자제가 중간인데 지어낸 쌍은 최다다 — 자주 묶지는 않지만 **크게** 묶는다. 자제(빈도)만으로는 안 보인다.

### 2-2. `.parsed` trace span이 guidance를 안 싣는다

`WeeklyGoalTask.swift:509`, `MonthlyGoalTask.swift:197`이 `parsed.drafts`만 텍스트로 싣는다. guidance 결과는 `drafts`가 비어 있어 **텍스트가 빈 문자열**이 된다. `facts`의 `kept=1`은 맞는데 텍스트가 없어 "다 버려졌다"로 오해하게 된다.

재현: `G-2026-08-26T01-40-46+0900-m41` — `extractedJSON`에 guidance 3필드가 멀쩡히 있는데 `parsed`가 비어 있음.

### 2-3. `requestedIDs`가 두 경로에서 다른 것을 센다

`MonthlyGoalTask.swift:255` guidance 분기는 `requestedIDs: guidance.count`(안내 항목 수)를 넣는다. suggestions 분기는 실제 ID 개수를 센다. 같은 필드가 다른 의미를 담고 있어 용어 정의와 어긋난다.

### 2-4. 월간 경로가 토큰 수를 못 남긴다

`MonthlyGoalTask.run`은 `String` 반환 오버로드 하나뿐이라 `usage`를 실을 수 없다. 야간 실행에서 월간 31건 전부 `tokensOut`이 비어 있었다. 주간과 같은 모양의 `GenerationOutput` 오버로드가 필요하다.

### 2-5. 골든셋 데이터 — 분류가 어긋난 케이스 1건

`general` 31건 중 1건에 `expectedGroups`가 없다. 유형은 general인데 묶을 게 없다. 집계는 `datasetType`이 아니라 `expectedGroups`의 실제 유무로 판단하게 해 뒀으므로 결과는 안 흔들리지만, 케이스 파일 자체를 확인해야 한다.

### 2-6. `contextModes` 낭비

62개 케이스 전부 두 recipe로 도는데, `context`에 실제 내용(`persona`·`profile`)이 있는 건 46개뿐이다. 나머지 16개는 두 recipe의 프롬프트가 **글자 단위로 같아** 비교 정보가 0인데 실행 시간만 쓴다. `contextVariants`가 키 존재 여부가 아니라 **내용 유무**를 보게 하면 모델당 124 → 108건이 된다.

### 2-7. 비결정적 채점이 하나도 없다

지표 5종 전부 ID 집합 비교다. **생성된 텍스트를 읽는 지표가 없다.** 같은 케이스에서 6개 모델이 전부 `pairF1=1.0`인데 제목은 이렇게 다르다:

```
qwen3:1.7b   - 반품 및 포장 업무 완료          ← "포장"은 입력에 없는 말
qwen3.8:27b  - 온라인 주문 상품 반품 절차 완료
```

1.7B와 27B가 동점이다. 못 재는 것: title 품질 · 환각 · reason 타당성 · guidance 문장의 유용성.

### 2-8. 머신 한계 — 18GB급 모델은 이 맥에서 못 돌린다

야간 매트릭스가 7번째 모델(`qwen3.8:27b-mlx`, peak 18.72 GiB)에서 무너졌다. 로드 직전 `free=1.4 GiB, free_swap=0 B`. 2시간 20분 스래싱하다 WindowServer 워치독이 죽어(메인 스레드 40초 무응답) GUI 세션이 재시작되고 `make`가 붙어 있던 터미널과 함께 사라졌다.

24 GiB 예산에 18.7 GiB 모델 + Xcode 테스트 호스트 + OS는 마진이 없다. `iogpu.wired_limit_mb`를 올리는 건 **이 상황에서 역효과**다(페이지 아웃 불가 메모리만 늘어남).

### 2-9. 헬스체크 2초가 부하 상태에서 오탐을 만든다

`OllamaChatClient.swift:92` `request.timeoutInterval = 2`. 스래싱 중에는 살아 있는 서버도 `/api/tags`에 2초 안에 답하지 못한다. 야간 실행에서 `serverUnavailable` 9건이 전부 오탐이었다(서버 로그에 재시작 흔적 없음).

---

## 3. 다음 작업 — 우선순위 순

### A. 채점 정확도 (먼저)

- [x] **`지어낸 쌍` 지표 추가** — 정답 묶음 없는 케이스에서 FP 쌍 수를 센다. 능력 격자에 열 추가(낮을수록 좋으므로 색 방향 반전). 기존 데이터로 소급 계산 가능
- [x] `.parsed` span에 guidance 텍스트 싣기 — `WeeklyGoalTask.swift:509`, `MonthlyGoalTask.swift:197`
- [ ] `requestedIDs` 의미 정리 — guidance 분기에서 0으로 두거나 별도 필드 분리
- [ ] `general`인데 `expectedGroups`가 없는 케이스 1건 확인

### B. 실행 효율

- [ ] `contextVariants`가 `context` **내용** 유무를 보게 수정 (124 → 108건, 13% 절약)
- [ ] 러너에 모델 간 언로드(`keep_alive: 0`) + 대기 추가 — `OllamaChatClient.unload`가 이미 있다
- [ ] 헬스체크 2초 → 5초
- [ ] `MonthlyGoalTask`에 `GenerationOutput` 오버로드 추가 (월간 토큰 수 기록)

### C. 남은 모델 실행

매트릭스 13개 중 6개 완주, 7개 남음.

- [ ] **MLX 5개** (`Qwen3-1.7B/4B/8B-4bit`, `Qwen3.5-9B-4bit`, `gemma-4-e4b-it-4bit`) — 가장 큰 게 12 GB라 안전. 예상 2시간 30분 ~ 3시간 30분
- [ ] `gemma4:26b`(18.0 GiB) — 매트릭스에 섞지 말고 단독 실행하거나 제외
- [ ] `qwen3.8:27b-mlx`(18.7 GiB) — **제외 권장.** `qwen3.8:27b`와 같은 모델의 다른 양자화라 새 정보가 적고, 이 머신에서 완주 가능성이 낮다

> 참고: 스키마 수정은 **Ollama 경로에만** 적용된다. MLX는 `LogitProcessor`, AFM은 `@Generable`로 각자 다른 장치를 쓰므로 이번 버그의 영향도, 수정의 이득도 없다. 비교표에서 Ollama만 좋아진 것처럼 보여도 모델 성능 차이가 아니다.

### D. 비결정적 채점 (그 다음)

- [ ] **환각 검사** — 프롬프트가 이미 금지한 규칙(`입력에 없는 구체적인 숫자·결과·마감 조건을 만들지 마`)이고 정규식으로 결정적 판정이 가능하다. 비용 거의 없음. 지금 "1.7B와 27B 동점"인 문제를 바로 가른다
- [ ] **역방향 추론 채점** — 생성된 title만 주고 어떤 항목이 묶였는지 되맞히게 한다. 정답 라벨 없이 title이 내용을 담고 있는지 잰다
- [ ] **LLM-as-Judge + 루브릭** — 채점 모델을 어디서 구할지가 먼저 풀려야 한다. 로컬 최고가 `qwen3.8:27b`인데 건당 35초라 744건 채점에 7시간

---

## 4. 현재 상태 스냅샷

```
완주      6개  appleFoundation · qwen3:1.7b · qwen3:4b · qwen3:8b · qwen3.5:9b · qwen3.8:27b
미실행    7개  qwen3.8:27b-mlx(중단) · gemma4:26b · MLX 5개
케이스   62개  general 31 · context_dependent 13 · insufficient_information 12 · non_goal_or_noise 6
모델당  124건  62 케이스 × 2 recipe
trace    836개 (원문·프롬프트·파싱 진단 전부 보존)
```

| 모델 | 묶기 | 함정 | 안내 | 거절 | 자제 | 중앙 소요 |
|---|---|---|---|---|---|---|
| appleFoundation | 0.54 | 0.90 | 0.00 | 0.08 | 0.08 | 4.2s |
| qwen3:1.7b | 0.39 | 0.92 | 0.00 | 0.58 | 0.66 | 1.3s |
| qwen3:4b | 0.69 | 0.89 | 0.00 | 0.67 | 0.32 | 6.2s |
| qwen3:8b | 0.50 | 0.77 | 0.21 | 0.67 | 0.58 | 10.6s |
| qwen3.5:9b | 0.66 | 0.88 | 0.08 | 0.58 | 0.42 | 14.5s |
| qwen3.8:27b | 0.77 | 0.92 | 0.52 | 0.25 | 0.71 | 35.2s |

대상: 묶기·함정 86건 / 안내 24건 / 거절 12건 / 자제 38건. **유형마다 정답의 성격이 반대라 가로로 더한 값은 정의되지 않는다.**

파싱 진단(모델당 124건 누적) — `badID`는 전 모델 0건으로 정수 배열 스키마가 제 역할을 하고 있다:

| 모델 | modelReturned | kept | tooFewIDs | alreadyUsed | overMaxMemo |
|---|---|---|---|---|---|
| appleFoundation | 201 | 142 | 59 | 3 | 20 |
| qwen3:1.7b | 98 | 86 | 12 | 9 | 20 |
| qwen3:4b | 172 | 141 | 31 | 2 | 15 |
| qwen3:8b | 288 | 261 | 27 | 2 | 9 |
| qwen3.5:9b | 203 | 183 | 19 | 6 | 14 |
| qwen3.8:27b | 235 | 228 | 7 | 2 | 0 |

맥락 효과(짝지은 34쌍) — 6개 중 4개가 음수다. `withContext`를 켜면 오히려 나빠지며, 실행 시간은 두 배로 쓴다:

| 모델 | 개선 | 무변 | 악화 | 평균 Δ |
|---|---|---|---|---|
| appleFoundation | 6 | 17 | 11 | −0.036 |
| qwen3:1.7b | 9 | 20 | 5 | +0.038 |
| qwen3:4b | 9 | 19 | 6 | +0.007 |
| qwen3:8b | 7 | 17 | 10 | −0.065 |
| qwen3.5:9b | 7 | 17 | 10 | −0.019 |
| qwen3.8:27b | 2 | 27 | 5 | −0.039 |

---

## 5. 미해결 — 재조사 필요

수정 전 22:25 실행에서 **w1·w2·w3만 정상**이고 w4부터 전부 무너졌다. 키 순서 이론대로면 한 프로세스 안에서는 순서가 고정이라 균일해야 한다. 게다가 그 세 건의 출력은 키 순서가 스키마와 어긋나 있어(`reason, items, title, emoji` vs 스키마 `emoji, items, title, reason`) 애초에 문법 제약을 안 받은 것처럼 보인다.

가설(미검증): 앞 몇 건은 어떤 이유로 문법 제약이 적용되지 않았다. Ollama의 문법 컴파일 캐시나 슬롯 상태가 관련됐을 수 있다.

수정 후 야간 실행에서 `qwen3.8:27b`가 124건 완주했으므로 실용적으로는 해소됐다. 다시 재현되면 이 항목을 다시 판단한다.
