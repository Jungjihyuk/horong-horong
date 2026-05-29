# ontology

사용자 관심 키워드를 기반으로 뉴스 카테고리 체계를 생성, 저장, 분류한다.

## 여기에 둔다

- ontology/category 데이터 모델
- 관심 키워드 정규화와 해시 계산
- ontology JSON 캐시 읽기/쓰기
- LLM 기반 카테고리 생성
- seed fallback 생성
- keyword/semantic 기반 분류기
- 향후 ontology evolution, topic discovery, GraphRAG 준비 로직

## 여기에 두지 않는다

- 외부 뉴스 source 수집
- 전체 pipeline 실행 순서 조율
- 최종 Markdown 렌더링
- provider별 실행 구현

## 판단 기준

뉴스 항목을 어떤 카테고리 체계로 이해하고 분류할지에 관한 코드는 ontology에 둔다.
그 카테고리를 사용해 stage 흐름을 조립하는 코드는 patterns나 stages에 둔다.
