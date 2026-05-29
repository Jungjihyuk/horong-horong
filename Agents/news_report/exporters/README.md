# exporters

생성된 리포트, 메타 JSON, result JSON 같은 최종 산출물을 실제 파일로 기록한다.

## 여기에 둔다

- report 파일 쓰기
- meta JSON 파일 쓰기
- Swift 앱이 읽는 result JSON 쓰기
- artifact write 결과 반환
- exporter별 실패 처리

## 여기에 두지 않는다

- Markdown 문자열 생성
- stage별 데이터 처리
- trace event 모델
- provider/connector 구현

## 판단 기준

이미 만들어진 산출물을 외부 세계에 기록하는 책임은 exporters에 둔다. 산출물 내용을
어떻게 만들지는 renderers나 stages가 담당한다.
