# 첫 평가: 일정 소재와 실행 의도 구분

Status: draft

- Entrypoint: 승인 후 구현할 격리된 의도 판단 평가기. 현재 실행 명령은 없음.
- Source: support-audit.md의 revision 및 앱 대화 공급자 경로를 기준으로 한다.
- Preserved behavior: 로컬 Ollama 모델 사용, 한국어 사용자 입력, 역할별 최근 대화, 비추론 모드를 첫 비교 조건으로 사용. 모델별 미지원 옵션은 오류로 기록한다.
- Reconstruction differences: 현재 앱의 키워드 선점 경로를 재현하지 않는다. 새 의도 판단용 프롬프트와 구조화 응답 또는 네이티브 도구 호출을 비교하는 프로토타입이며 제품 성능 평가가 아니다.
- 판단 계약 초안: conversation / schedule_lookup / schedule_create / clarification. 네이티브 호출 비교 시 schedule_lookup(date), schedule_create(title, date)의 요청을 관찰하고 대화 응답은 conversation으로 분리한다. 구조화 출력은 같은 행동과 인자를 표현한다. 실제 schema는 평가 구현 전에 고정하고 해시를 기록한다.
- Adapter: Harbor 입력을 평가기에 전달하고 실제 응답·호출·형식 오류를 기록한다. 개인정보 저장소와 연결하지 않는다.
- Session: 첫 과제는 단일 입력. 부정·정정과 복원은 후속 다중 턴 과제로 별도 검토한다.
- Credentials: 로컬 Ollama에는 별도 자격 증명 없음. 외부 모델·채점 서비스는 사용하지 않는다.
- Evidence: 모델 ID/설정, 입력, 관찰한 원시 모델 출력, 파싱 결과, 도구 요청, 오류, 지연을 기록한다. 기대 정답이나 채점 기준을 모델에 전달하지 않는다.
- 제한: 첫 과제는 행동 선택을 검증한다. 상담 문장의 자연스러움이나 앱의 저장·복원 성능 합격을 주장하지 않는다.
