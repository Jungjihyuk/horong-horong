# connectors

Google News, YouTube, LinkedIn, Yozm 같은 외부 뉴스 소스에서 원천 데이터를 수집한다.

## 여기에 둔다

- source별 connector 구현체
- connector 공통 protocol
- source type을 connector 구현체로 바꾸는 registry/factory
- 수집 성공/실패를 모아 runner에 전달하는 collector
- 외부 페이지/API 응답을 news item dict로 변환하는 source별 파싱 로직

## 여기에 두지 않는다

- LLM provider 실행 로직
- 수집 이후 normalize, dedupe, rank 같은 pipeline stage
- 최종 리포트 렌더링
- source와 무관한 저장소/캐시 정책

## 판단 기준

외부 데이터 source에 접속하거나 source 응답을 원천 item으로 바꾸는 코드는
connectors에 둔다. 여러 source에서 모인 뒤 적용되는 처리는 stages로 보낸다.
