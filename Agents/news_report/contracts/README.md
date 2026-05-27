# contracts

Swift 앱, Python runner, 내부 stage 사이에서 오가는 데이터 구조와 검증 모델을
정의한다.

## 여기에 둔다

- Swift 앱이 생성하고 Python runner가 읽는 요청/응답 모델
- 공유 JSON Schema와 1:1로 대응되는 Pydantic 모델
- 외부 API나 저장 파일 포맷처럼 다른 컴포넌트가 의존하는 구조
- 필드명 alias, 기본값, 타입/범위 검증이 필요한 경계 모델
- request 파일을 계약 모델로 변환하는 loader

## 여기에 두지 않는다

- 특정 런타임 구현 내부에서만 쓰는 helper 모델
- tracing 내부 이벤트처럼 아직 특정 모듈 내부에 닫혀 있는 구조
- connector 내부에서만 쓰는 임시 파싱 결과
- UI 표현 전용 모델

## 판단 기준

여러 컴포넌트가 같은 데이터 모양에 의존하면 contracts에 둔다.
한 모듈 내부 구현 세부사항이면 해당 모듈 안에 둔다.
