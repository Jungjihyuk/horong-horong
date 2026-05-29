# renderers

정제된 리포트 데이터를 Markdown, HTML, Swift 표시용 구조 등 사람이 읽는 표현으로
변환한다.

## 여기에 둔다

- Markdown 리포트 문자열 생성
- HTML 또는 Swift 표시용 view model 생성
- 숫자/시간/카테고리 표현 formatting
- 리포트 섹션 구성 규칙

## 여기에 두지 않는다

- 파일에 쓰는 로직
- LLM 요약 생성
- source 수집
- 실행 결과 JSON 생성

## 판단 기준

이미 준비된 데이터를 "어떻게 보여줄지" 결정하는 코드는 renderers에 둔다. 그 결과를
어디에 쓸지는 exporters가 담당한다.
