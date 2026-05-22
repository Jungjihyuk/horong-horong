---
category: {category}
completed: false
endpoint: /api/{path}
http_method: {METHOD}
description: {한 줄 설명}
request: {요청 필드 요약 또는 "없음"}
response: {응답 필드 요약}
requirement_priority: {🚨 P0 (필수 기능) | ⭐️ P1 (핵심 기능) | 🧩 P2 (중요하지만 급하지 않음)}
estimated_time: {예상 소요시간}
dependencies:
  - {의존 모델명}
incharge: {담당자}
tags:
  - {카테고리 한글명}
  - {관련 키워드}
  - requirement
---

# 🌐 {METHOD} {ENDPOINT} - {한 줄 설명}

## 📋 기본 정보
- **엔드포인트**: `{METHOD} {ENDPOINT}`
- **설명**: {상세 설명을 작성하세요}
- **완료 상태**: ❌ 미완료
- **우선순위**: {높음|중간|낮음}
- **예상 소요시간**: {estimated_time}

## 📤 Request

### Headers
```http
Content-Type: application/json
Accept: application/json
```

### {Query Parameters | Body Parameters}
| 파라미터 | 타입 | 필수 | 기본값 | 설명 |
|---------|------|------|-------|------|
| `field1` | string | ✅ | - | 설명 |
| `field2` | number | ❌ | 10 | 설명 |

### 예시 요청
```http
{METHOD} {ENDPOINT}
Content-Type: application/json
```

```json
{
  "field1": "value"
}
```

## 📥 Response

### 성공 응답 ({200|201|204})
```json
{
  "id": 1,
  "field": "value"
}
```

### 응답 필드 설명
| 필드 | 타입 | 설명 |
|-----|------|------|
| `id` | number | 고유 ID |
| `field` | string | 설명 |

### 에러 응답
- **400 Bad Request**: 잘못된 요청 데이터
- **404 Not Found**: 리소스를 찾을 수 없음
- **422 Validation Error**: 검증 실패
```json
{
  "detail": [
    {
      "loc": ["string", 0],
      "msg": "string",
      "type": "string"
    }
  ]
}
```
- **500 Internal Server Error**: 서버 내부 오류

## 🔒 권한 요구사항
- **인증**: {필요 없음 | JWT 필요}
- **권한**: {없음 | 관리자만}

## 💡 구현 고려사항

### 🔄 비즈니스 로직
- [ ] 입력값 유효성 검증
- [ ] 비즈니스 규칙 처리
- [ ] 응답 데이터 가공

### 🗃️ 데이터베이스
- [ ] 데이터베이스 스키마 확인
- [ ] 쿼리 최적화
- [ ] 트랜잭션 관리

### ⚡ 성능
- [ ] 캐싱 전략
- [ ] 응답 최적화
- [ ] 동시성 처리

## 🧪 테스트 케이스

### Unit Tests
- [ ] 정상 케이스 테스트
- [ ] 유효성 검증 테스트
- [ ] 에러 처리 테스트

### Integration Tests
- [ ] 전체 플로우 테스트
- [ ] 다른 API와의 연동 테스트

## 📊 데이터베이스 의존성

### 테이블
- **{ModelName}**: {용도 설명}

### 인덱스 권장사항
- {필요한 인덱스 설명}

## 📝 개발 노트

### 진행 상황
- [ ] API 스펙 정의 완료
- [ ] 데이터베이스 스키마 확인
- [ ] 비즈니스 로직 구현
- [ ] 단위 테스트 작성
- [ ] 통합 테스트 작성
- [ ] API 문서화 완료

### 이슈 및 블로커
- 없음

### 참고 자료
- [관련 문서 링크]()

## 🔗 관련 요구사항 (Related Requirements)
-   [[FR-XXX]]: 요구사항 설명
-   [[NFR-XXX]]: 요구사항 설명

---
*마지막 업데이트: {YYYY-MM-DD}*
