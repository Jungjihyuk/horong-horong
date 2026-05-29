# Integration tests

`integration/`은 여러 모듈이 함께 맞물리는지를 검증한다.

## 책임

- request loader와 pipeline context 연결 검증
- fake provider 기반 research pattern 실행 검증
- artifact renderer/exporter 조합 검증
- runner에 가까운 흐름을 외부 네트워크 없이 검증

## 원칙

- 기본적으로 실제 네트워크와 실제 CLI를 사용하지 않는다.
- 외부 상태가 필요한 테스트는 `e2e/`로 보낸다.
- unit보다 넓은 범위를 보되, 실패 원인을 추적할 수 있어야 한다.

## 실행

```bash
cd Agents/news_report
.venv/bin/pytest -m integration test/integration -q
```
