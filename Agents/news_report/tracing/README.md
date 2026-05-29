# tracing

run log, debug log, Swift step 출력, JSONL trace처럼 실행 상태를 관측하고 기록한다.

## 여기에 둔다

- 사람이 읽는 실행 로그 writer
- Swift UI가 소비하는 step reporter
- 분석 가능한 JSONL trace writer
- trace event 데이터 계약
- stage/provider/connector별 소요 시간, 실패, 산출물 기록

## 여기에 두지 않는다

- 비즈니스 로직 자체
- 리포트 품질 평가 기준
- 저장소 도메인 모델
- provider나 connector 구현

## 판단 기준

실행 중 무슨 일이 있었는지 외부에 드러내기 위한 코드는 tracing에 둔다. 실행 결과를
평가하는 코드는 evals에 두고, 실제 산출물을 쓰는 코드는 exporters에 둔다.
