# Unit tests

`unit/`은 가장 작고 빠른 테스트를 둔다.

## 책임

- Pydantic 계약 검증
- provider/factory 동작 검증
- connector registry와 collector의 예외 처리 검증
- stage 함수의 순수 처리 로직 검증
- renderer/exporter의 문자열/JSON payload 생성 검증

## 원칙

- 실제 네트워크를 사용하지 않는다.
- 실제 Ollama 서버나 CLI agent를 호출하지 않는다.
- provider, trace, connector는 fake 객체로 대체한다.
- 실패 원인이 한 함수나 한 클래스 안에서 드러나야 한다.

## 실행

```bash
cd Agents/news_report
.venv/bin/pytest -m unit test/unit -q
```
