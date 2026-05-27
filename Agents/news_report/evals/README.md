# evals

리포트 품질, relevance 정확도, pattern 성능 비교 같은 평가 기준과 평가 실행 로직을
담는다.

## 여기에 둔다

- 리포트 품질 평가 기준
- relevance scoring 결과 검증
- provider/pattern별 성능 비교
- trace artifact를 읽어 latency, 실패율, 품질 지표 산출
- 실험 결과 요약 모델

## 여기에 두지 않는다

- 실제 pipeline stage 처리
- source 수집
- 산출물 렌더링
- 사람이 읽는 일반 실행 로그

## 판단 기준

무언가를 생성하는 코드가 아니라, 생성된 결과가 좋은지 판단하거나 비교하는 코드는
evals에 둔다.
