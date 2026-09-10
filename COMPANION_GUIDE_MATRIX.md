# 루미롱 기능 안내 목적지 매트릭스

> 기준일: 2026-09-10  
> 목적: 루미롱이 설명할 수 있는 기능과 실제로 열어 보여줄 수 있는 UI 목적지의 차이를 추적한다.

## 판정 기준

| 등급 | 의미 |
|---|---|
| 설명 | `USER_GUIDE.md` 또는 앱 사실을 근거로 답할 수 있음 |
| 이동 | 창이나 탭을 열 수 있는 실제 진입 경로가 있음 |
| 강조 | 이동 후 안정적인 대상 ID로 특정 카드·행을 가리킬 수 있음 |

`CompanionKnowledgeRegistry`는 설명과 사용자 표현을, `CompanionDestinationRegistry`는 실행 가능한 목적지만 소유한다. 목적지가 없는 설명 항목도 허용한다. Registry에 등록되지 않은 문자열은 실행하지 않는다.

## 설정 화면

설정의 모든 `SettingsGroupCard`는 공통 컴포넌트에서 `card:<카드 제목>` ID를 자동으로 갖는다. 사용자용 14개 탭과 아래 카드 목적지는 `CompanionDestinationRegistry`에 등록되어 있다.

| 설정 탭 | 안내 가능한 카드·행 | 목적지 수준 | 현재 등록 |
|---|---|---|---|
| 일반 (`general`) | 동작 / 로그인 시 자동 시작 | 탭·카드·행 | 완료 |
| 외관 (`appearance`) | 모드 / 테마 / 아이콘 | 탭·카드·행 | 완료 |
| 타이머 (`timer`) | 프리셋 / 프리셋 시간 편집 / 알림 / 동작 / 메뉴바 표시 | 탭·카드 | 완료 |
| 단축키 (`hotkey`) | 전역 / 설정 | 탭·카드 | 완료 |
| 카테고리 매핑 (`category`) | 카테고리 / 앱 → 카테고리 / 웹사이트 → 카테고리 / 자리 비움 감지 임계값 / 짝 카테고리 (전환 무시) | 탭·카드 | 완료 |
| 통계 (`stats`) | 타임라인 표시 / 보관 / 추적 / 휴가 기간 | 탭·카드 | 완료 |
| 몰입 (`focus`) | 집중 넛지 / 개인화 / 개인 회고 기반 / 규칙 기반 기준 / 반복 방식 / 해줄 말 | 탭·카드 | 완료 |
| 성취 (`achievement`) | 추천 모델 / 주간 목표 추천 / 월간 목표 추천 / 여정 / 보상 / 적용 방식 | 탭·카드 | 완료 |
| 뉴스 (`news`) | 소스 / 관심 키워드 / 파이프라인 | 탭·카드 | 완료 |
| 실험실 (`lab`) | 실행 환경 / 안전장치 / 관심사 | 탭·카드 | 완료 |
| 루미롱 (`companion`) | 루미롱 / 활동 / 일정 브리핑 / 호로롱이 알아둘 것 / AI 대화 / 준비 중 | 탭·카드·일부 행 | 완료 |
| 기록 (`secondBrain`) | 퀵 메모 / 빠른 링크 / Todo 일정 / 일기 수면 기록 / 미리알림 가져오기 | 탭·카드·일부 행 | 완료 |
| 데이터 (`data`) | 저장소 / 백업 / 개선 데이터 | 탭·카드 | 완료 |
| 정보 (`about`) | 버전·GitHub·사용 가이드·라이선스 / 크레딧 | 탭·카드 | 완료 |

AI 실험실(`ailab`)은 개발자 전용이므로 루미롱 안내, LLM 목적지 후보, `CompanionDestinationRegistry`에서 모두 제외한다.

### 명시적인 행 강조 ID

| ID | 실제 위치 | Registry |
|---|---|---|
| `settings.launchAtLogin` | 일반 → 로그인 시 자동 시작 | 등록 |
| `settings.appearanceMode` | 외관 → 모드 | 등록 |
| `settings.theme` | 외관 → 테마 | 등록 |
| `settings.appIcon` | 외관 → 아이콘 | 미등록 |
| `settings.memoShortcut` | 기록 → 퀵 메모 단축키 | 미등록 |
| `settings.companionBasics` | 루미롱 → 기본 표시 | 등록 |
| `settings.activity` | 루미롱 → 활동 | 미등록 |
| `settings.briefing` | 루미롱 → 일정 브리핑 | 미등록 |
| `settings.profile` | 루미롱 → 호로롱이 알아둘 것 | 미등록 |
| `settings.chat` | 루미롱 → AI 대화 | 미등록 |

## 팝오버와 상세 화면

| 기능 화면 | 설명 근거 | 실제 진입 경로 | 강조 ID | 현재 Destination 지원 |
|---|---|---|---|---|
| 타이머 탭 | 사용 가이드 4 | 메뉴바 팝오버 → 타이머 | `tab.timer`, `timer.preset`, `timer.selectTask`, `timer.startFocus` | 지원 (Surface: popover) |
| 기록 탭 | 사용 가이드 5 | 메뉴바 팝오버 → 기록 | `tab.memo`, `memo.new` | 지원 (Surface: popover) |
| 통계 탭 | 사용 가이드 6 | 메뉴바 팝오버 → 통계 | `tab.stats`, `stats.detail` | 지원 (Surface: popover) |
| 뉴스 탭 | 사용 가이드 2 | 메뉴바 팝오버 → 뉴스 | `tab.news` | 지원 (Surface: popover) |
| 실험실 탭 | 사용 가이드 3 | 메뉴바 팝오버 → 실험실 | `tab.lab` | 지원 (Surface: popover) |
| 성취 탭 | 사용 가이드 9 | 메뉴바 팝오버 → 성취 | `tab.achievement` | 지원 (Surface: popover) |
| 통계 상세 | 사용 가이드 6·6-1 | 통계 → 상세 보기 | `stats.focusToggle` | 지원 (Surface: hub) |
| 루미롱 메뉴 | 사용 가이드 8 | 캐릭터 오른쪽 클릭 | `companion.menu.<action>` | 온보딩 전용 경로만 존재 |

## 기록 허브와 독립 창

| 기능 화면 | 설명 근거 | 실제 진입 경로 | 화면 상태 | 현재 Destination 지원 |
|---|---|---|---|---|
| Quick Note | 사용 가이드 5 | 기록 허브 → Quick Note | 구현됨 | 지원 (Surface: hub) |
| Diary | 사용 가이드 5 | 기록 허브 → Diary | 구현됨 | 지원 (Surface: hub) |
| Todo | 사용 가이드 5 | 기록 허브 → Todo | 구현됨 | 지원 (Surface: hub) |
| Knowledge | 사용 가이드 5 | 기록 허브 → Knowledge | 준비 중 표시 | 등록 금지 |
| Works | 사용 가이드 5 | 기록 허브 → Works | 준비 중 표시 | 등록 금지 |
| References | 사용 가이드 5 | 기록 허브 → References | 구현됨 | 지원 (Surface: hub) |
| 뉴스 허브·보관함 | 사용 가이드 10 | 뉴스 → 전체 보기·보관함 | 구현됨 | 지원 (Surface: hub) |
| 성취 상세 | 사용 가이드 9 | 성취 → 상세 보기 | 구현됨 | 지원 (Surface: hub) |

## 확인된 구조적 공백

1. ~~`CompanionDestination.Surface`가 현재 `settings`만 지원한다.~~ ➔ `settings`, `popover`, `hub`로 확장 완료.
2. ~~`CompanionOnboardingPresenter`의 Domain 목적지 실행 경로가 설정만 연결되어 있다.~~ ➔ `popover` 및 `hub` 라우팅 완료.
3. ~~설정 카드 대부분이 Registry에 미등록 상태였다.~~ ➔ 14개 탭 및 모든 카드 완전 등록 완료.
4. ~~`CompanionAppFacts`가 `USER_GUIDE.md` 전체 기능과 일대일로 정렬되어 있지 않았다.~~ ➔ `CompanionKnowledgeRegistry` 도입으로 30개 기능 설명 체계적 통합 완료.
5. Knowledge와 Works처럼 이름은 노출되지만 아직 사용할 수 없는 화면은 설명은 가능해도 실행 목적지로 등록하면 안 된다 (현재 제외 규칙 준수 중).
6. AI 실험실은 개발자 전용이므로 설명과 이동 목적지 모두 제공하지 않는다 (현재 제외 규칙 준수 중).
7. ~~일반 키워드('탭')가 구체적인 탭('성취 탭')을 가로채 엉뚱한 목적지(타이머)가 열리는 결함.~~ ➔ Specificity(최장 일치 키워드 길이) 정렬 도입, 팝오버 6개 탭 목적지 정밀 매핑 완료.
8. ~~짝 카테고리(전환 무시) 지식 및 목적지 미등록 결함.~~ ➔ `knowledge.categoryPairs` 등록, 주의 분산 제외 원리 및 현재 등록된 짝 카테고리 목록 사실 안내, `settings.category.pairs` 목적지 연결 완료 (총 33개 지식 항목).

## 다음 구현 순서

1. [완료] 설정 탭과 카드 목적지를 Registry에 완전 등록하고 실제 `SettingsTab` 변환 검증을 추가한다.
2. [완료] `Surface`를 팝오버·허브·독립 창으로 확장하고 Presentation 실행기를 surface별로 분기한다.
3. [완료] `CompanionKnowledgeRegistry`를 도입해 `CompanionAppFacts`와 사용 가이드 기능 설명을 통합한다.
4. 키워드 미매칭 시 LLM이 등록된 knowledge/destination ID만 반환하는 구조화 분류를 추가한다.
5. 신뢰도 정책과 일회성 이동 명령의 중복 소비·없는 대상 회귀 테스트를 추가한다.
