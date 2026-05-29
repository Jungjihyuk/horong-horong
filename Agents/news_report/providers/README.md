# providers

Codex, Claude, Gemini, Ollama, MLX 같은 LLM/agent 실행 구현체를 제공한다.

## 여기에 둔다

- provider 공통 protocol
- 외부 CLI 기반 provider 구현체
- 로컬 모델 기반 provider 구현체
- provider 이름을 구현체로 바꾸는 factory/registry
- provider 실행 실패를 공통 예외로 감싸는 기반 클래스

## 여기에 두지 않는다

- prompt를 만드는 stage별 업무 로직
- source 수집 connector
- provider 응답을 리포트 형식으로 렌더링하는 코드
- provider 성능 평가/비교 로직

## 판단 기준

관심사는 "어떤 prompt를 실행해 텍스트 응답을 얻는가"까지다. 무엇을 물어볼지,
응답을 어떻게 해석할지는 stages나 evals에 둔다.
