# Excalidraw Text Elements Template

아래 블록을 Excalidraw 파일의 `## Text Elements`에 채운다.

## Context
- 사용자: [주 사용자군]
- 외부 시스템: [연동 대상]
- 제약: [법적/예산/운영 제약]

## Container
- Web App: [핵심 책임]
- API Server: [핵심 책임]
- Background Worker: [필요 시]
- PostgreSQL: [주요 엔티티]
- Redis: [캐시/큐 용도]

## Core Flows
1. 조회 흐름: UI -> API -> DB/Cache -> UI
2. 변경 흐름: UI -> API -> DB -> Cache Invalidate/Refresh
3. 비동기 흐름: API -> Queue/Worker -> DB

## Error Flows
1. 외부 API 실패: 타임아웃 -> 재시도 -> 실패 응답
2. DB 장애: 트랜잭션 롤백 -> 에러 로깅 -> 사용자 안내

## NFR Notes
- 성능: p95 목표, 캐시 전략
- 보안: 인증/인가, 입력 검증, 비밀정보 관리
- 가용성: 헬스체크, 재시도, 장애 격리
- 관측성: 로그/메트릭/트레이스

## Traceability
- 관련 FR: [FR-001, FR-00x]
- 관련 NFR: [NFR-001, NFR-00x]
- 관련 UI: [화면명1, 화면명2]
