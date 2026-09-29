# 대화 의도 판단 연결 조사

2026-09-18. 대상 change: persist-companion-conversation-context, task 5.1 (부분 조사).
소스 revision: c7e6b70a5d849755304dae97083ed37b9575edbb.

> 이관 메모 (2026-09-29): 이 조사는 Lantern 저장소에서 했고, 위 change·revision도 Lantern 기준이다.
> HorongHorong `a8a3d31`에서 아래 결론을 다시 확인했다: `CompanionController.send`는 키워드 분기 뒤 남은 입력만 모델에 보낸다.
> `OllamaChatClient`의 요청에 도구 필드가 없고 메시지는 role·content만 있다. MLX는 `streamResponse`만 쓴다.
> Apple 경로에도 도구 정의가 없다. 설치 모델 표와 캐시 확인은 조사 당시 기록이다.

## 실제 설치 확인

로컬 Ollama의 `ollama list`로 확인했다. 모델을 다운로드하거나 추론하지 않았다.

| 태그 | 설치 ID | 목록에 표시된 크기 |
|---|---|---|
| gemma4:e4b | c6eb396dbd59 | 9.6 GB |
| gemma4:26b | 5571076f3d70 | 17 GB |
| qwen3.5:9b | 6488c96fa5fa | 6.6 GB |
| qwen3:14b | bdbd181c33f2 | 9.3 GB |

크기는 저장된 모델 크기이며 실행 시 최대 메모리나 기기 최소 RAM이 아니다.

## 사용자 확인 후 후보 정정

사용자 요청으로 Qwen3 14B를 Qwen3 8B로 교체했다. 위 14B 행은 최초 Ollama 설치 조사 기록이며 현재 평가 후보가 아니다. Ollama의 qwen3:8b는 500a1f067a9f (목록 크기 5.2 GB)로 확인했다.

Direct 앱의 기본 캐시 `/Users/jihyeok/.cache/huggingface/hub`에서 다음 safetensors 파일의 실체까지 확인했다. 로딩·추론은 아직 검증하지 않았다.

| MLX 모델 | 확인한 가중치 파일 |
|---|---|
| mlx-community/Qwen3-8B-4bit | model.safetensors |
| mlx-community/Qwen3.5-9B-4bit | model-00001-of-00002, model-00002-of-00002 |
| mlx-community/gemma-4-e4b-it-4bit | model.safetensors |
| mlx-community/gemma-4-26b-a4b-it-4bit | model-00001-of-00003부터 model-00003-of-00003까지 |

평가 대상은 두 실행 경로 모두이며 Ollama만으로 제한하지 않는다. MLX는 앱과 같은 Swift/Metal 실행 경로를 우선 검토한다. Python MLX 실행 결과를 앱의 Swift 경로 검증으로 대체하지 않는다.

## 평가 실행 환경 확인

현재 PATH에서 Harbor CLI를 찾지 못했다. Docker CLI는 있으나 샌드박스 밖의 읽기 전용 `docker info`에서도 daemon에 연결하지 못했다. eval-engineering 스킬은 Harbor 실행을 요구하므로 이를 조용히 생략하지 않는다. MLX/Metal은 Mac 호스트 실행이 필요하므로 Harbor와 호스트 추론을 연결할지, 사용자의 명시적 선택으로 네이티브 평가 방식으로 바꿀지 먼저 결정한다. 아직 평가 실행이나 모델 합격 판정은 없다.

## 앱 연결과 하위 API를 구분한 결과

| 경로 | 조사 근거 | 현재 앱 대화 연결 | 남은 확인 |
|---|---|---|---|
| 공통 계약 | LLMSession.swift, PackageChatProviderAdapter.swift | 문자열 입력과 text/mood/status 응답. 도구 정의·호출·결과 계약 없음 | 신규 판단 계약과 실행 검증 필요 |
| Ollama | OllamaChatClient.swift, OllamaProvider.swift | ChatRequest에 tools 없음. Message는 role/content만 표현. 호출 결과를 파싱하지 않음 | 설치 모델의 실제 tool call 및 파서 재현 |
| Ollama 구조화 출력 | OllamaChatClient.streamUpdates(format:) | JSONSchema 전송 API는 존재하지만 OllamaSession.reply의 stream 경로는 사용하지 않음 | 의도용 schema 연결과 형식/의미 평가 |
| MLX | MLXProvider.swift와 설치된 mlx-swift-lm ChatSession.swift | 앱은 streamResponse를 사용하고 tools/toolDispatch를 전달하지 않음 | 모델별 템플릿·파서 호환성과 실제 모델 호출 |
| MLX 하위 API | HorongAI/.build/checkouts/mlx-swift-lm/Libraries/MLXLMCommon/ChatSession.swift | tools, toolDispatch, streamDetails API가 설치 소스에 존재 | 존재만으로 네 후보의 실행 지원을 확정하지 않음 |
| Apple | AppleFoundationModelsProvider.swift | SystemLanguageModel.default 사용, toolDefinitions 비어 있음. GeneratedReply는 text/mood 구조화 출력만 제공 | Apple 자체 모델의 별도 지원 검증. 이 경로로 네 Ollama 모델을 선택하는 계약은 없음 |

CompanionController.send는 저장·사용법·일정 키워드 분기 뒤 남은 입력만 모델로 보낸다. 이를 그대로 실행하면 모델의 의도 판단 능력을 측정할 수 없다.

## 평가 경계

먼저 새 의도 판단 계약의 격리된 후보 평가가 필요하다. 기존 앱 동작을 그대로 측정한 결과라고 부르지 않는다. 이후 실제 대화 경로에 통합한 프롬프트·도구·복원 문맥으로 task 8.3에서 다시 측정한다.

아직 모델 추론·도구 호출 재현·Harbor 실행·의미 평가를 하지 않았다. task 5.1~5.5를 완료 처리하지 않는다. 평가 스킬의 사전 검토에 따라 harness/environment/task 초안을 승인받은 뒤 평가 구현을 시작한다.
