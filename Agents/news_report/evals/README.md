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

## 현재 제공하는 eval

### research_run_metrics.py

`report.meta.json`과 `trace.jsonl`을 읽어 provider 비교에 필요한 1차 정량 지표를
계산한다. 실제 provider를 다시 호출하지 않는 offline eval이다.

```bash
python -m evals.research_run_metrics \
  --meta /path/to/report.meta.json \
  --trace /path/to/trace.jsonl
```

주요 지표:

- artifact별 생성 개수
- warning 개수
- provider structured output 호출/완료/실패 수
- provider 평균 latency
- schema별 호출 수
- repair rate. 현재 repair trace가 없으면 `null`로 표시한다.
- structured output reliability. `provider_completed` payload의 `repair_attempted`(bool)로
  1차 성공 / repair 복구 / 최종 실패를 분해해 `firstPassRate`, `repairRecoveryRate`,
  `finalFailureRate`를 계산한다. repair 필드가 없으면 repair 의존 비율은 `null`이다.

### compare_provider_metrics.py

여러 `research_run_metrics.py` 결과 JSON을 읽어 provider별 비교표를 만든다.

```bash
python -m evals.compare_provider_metrics \
  --metrics /tmp/Horong/metrics/ollama.json \
  --metrics /tmp/Horong/metrics/codex.json \
  --output /tmp/Horong/metrics/provider-comparison.json
```

비교 기준:

- 채택된 source candidate 수
- 생성된 source insight 수
- 생성된 trend insight 수
- warning 수
- provider/stage 실패 수
- 평균 provider latency
