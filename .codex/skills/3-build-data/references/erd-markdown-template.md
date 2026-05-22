# 🧩 ERD

## 1. Source of Truth

- DBML: `[[schema.dbml]]`
- SQL: `[[schema.sql]]`

## 2. 시각화 방법 (dbdiagram.io)

1. `schema.dbml` 내용을 dbdiagram.io에 붙여넣는다.
2. 관계/카디널리티를 확인한다.
3. 필요 시 다이어그램 링크 또는 export 이미지를 아래에 반영한다.

## 3. 다이어그램 아티팩트

- dbdiagram 링크: (입력)
- PNG/SVG 파일: (입력)

## 4. SQL 생성

- 우선 로컬 CLI 시도: `dbml2sql docs/5. DB 명세서/schema.dbml -o docs/5. DB 명세서/schema.sql`
- 미지원 시 dbdiagram export SQL을 `schema.sql`로 저장

## 5. 리뷰 메모

- 변경된 테이블:
- 변경된 관계:
- 검토 필요 이슈:
