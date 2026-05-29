# patterns

research 목적별 실행 전략을 stage 조합으로 정의한다.

pattern은 하나의 완결된 실행 흐름이다. 어떤 stage를 어떤 순서로 실행할지, 어떤
provider와 connector 조합을 사용할지, 반복·분기·fallback을 어떻게 적용할지를
관리한다. `news_report_v1` 같은 기본 뉴스 리포트 흐름도 baseline pattern으로
관리하며, `local_research_v1`, `graph_rag_research_v1` 같은 실험 pattern과 같은
방식으로 실행된다.

## 하위 구분

- `pipelines/`: 앱 기능 하나를 완성하는 제품 pipeline. 예: `news_report_v1`.
- `research/`: 조사와 추론 방법론 자체. 예: `multi_pass`, `local_model`, `graph_rag`.
- `context.py`: pattern 실행에 필요한 공통 실행 context.
- `result.py`: runner가 result JSON을 만들 때 필요한 pattern 실행 결과.
- `registry.py`: pattern 이름을 실행 구현체로 변환한다.

## 여기에 둔다

- `news_report_v1` 같은 baseline 실행 pattern
- `local_research_v1`, `graph_rag_research_v1` 같은 deep research 실험 pattern
- stage 호출 순서, 반복, 분기 정책
- provider/connector/stage 조합 전략
- multi-pass, critique-refine, graph-based research 같은 고수준 workflow
- pattern 실행 context와 result 모델
- pattern registry/factory
- pattern version과 실험 설정

## 여기에 두지 않는다

- stage 내부 구현
- provider별 실행 구현
- connector별 수집 구현
- Markdown 렌더링 세부 코드
- 산출물 파일 쓰기 구현
- 품질 평가 지표 계산

## 판단 기준

개별 처리 함수가 아니라 "어떤 목적의 research를 어떤 stage 조합으로 실행할지"를
표현하는 코드는 patterns에 둔다. runner는 pattern을 선택하고 실행 context를 넘기는
진입점만 맡는다.

간단히 말하면:

- `stages`: 처리 부품
- `patterns`: 부품의 조립 순서와 실행 전략
- `runner.py`: 실행 환경 준비와 pattern 호출
