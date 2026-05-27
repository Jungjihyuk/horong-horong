# stages

normalize, dedupe, classify, rank, relevance filter, summarize, trend 분석처럼 리포트
생성 파이프라인의 개별 처리 단계를 담는다.

## 여기에 둔다

- 수집 item 정규화와 중복 제거
- ontology를 이용한 item 분류
- 관심사 기반 ranking
- LLM 기반 relevance scoring
- transcript/news summarization
- 카테고리별 trend/keyword 분석

## 여기에 두지 않는다

- 전체 실행 순서와 CLI 처리
- source별 수집 구현
- provider 구현체
- 최종 파일 쓰기
- Markdown/HTML 표현 생성

## 판단 기준

입력 데이터를 받아 다음 stage가 쓰기 좋은 데이터로 바꾸는 순수 처리 단위는 stages에
둔다. stage들을 어떤 순서로 묶을지는 patterns 또는 runner가 담당한다.
