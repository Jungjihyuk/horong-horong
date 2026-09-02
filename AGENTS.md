# 저장소 작업 규칙

이 문서는 이 저장소에서 작업하는 AI 코딩 에이전트의 실행 규칙을 정의한다.
목표는 아키텍처의 순수성 자체가 아니라 **정확하고, 최소하며, 검증 가능하고, 회귀에 안전하며, 현재 아키텍처와 일관된 변경**이다.

이 앱은 **MVVM + Clean Architecture**의 Presentation / Domain / Data 구조로 점진적으로 마이그레이션한다. 아직 이전이 끝나지 않았으므로 요청 범위를 벗어난 마이그레이션을 강행하지 않는다.

AGENTS.md와 CLAUDE.md는 서로 다른 에이전트의 진입점을 위해 항상 동일한 내용으로 유지한다. 규칙을 변경할 때는 두 파일을 함께 갱신하고 cmp -s AGENTS.md CLAUDE.md로 확인한다.

## 0. 규칙 우선순위

지시가 충돌할 때는 다음 순서를 따른다.

1. 사용자의 명시적 요청
2. §1 핵심 규칙
3. §3~4 아키텍처와 레이어 규칙
4. §7 검증 요구사항
5. Swift 코드 컨벤션과 ADR (§9)
6. 기존 구현 스타일

레거시 코드는 자동으로 올바른 패턴이 아니다. 주변 코드가 그렇다는 이유만으로 복사하지 않는다. 이 저장소의 상당 부분은 현재 아키텍처 이전에 작성되었다.

다음 규칙은 문서 전체에 항상 적용한다.

- 실행하지 않은 검증을 완료했다고 보고하지 않는다.
- 추측을 사실로 서술하지 않는다.
- 요청된 작업으로 추적되지 않는 라인은 변경하지 않는다.
- 사용자의 요청과 핵심 규칙이 충돌하면 충돌과 결과를 먼저 설명하고 확인받는다.

충돌 시 선호 순서는 다음과 같다.

> 정확성 → 회귀 안전성 → 가독성 → 아키텍처 → 성능 → 추상화

### 기본 원칙

| 원칙 | 의미 |
|---|---|
| Think Before Coding | 조용히 가정하지 않는다. 모호하면 해석 후보와 결과를 제시한다. |
| Simplicity First | 문제를 해결하는 최소 코드만 작성하고 투기적 확장을 하지 않는다. |
| Surgical Changes | 필요한 것만 수정하고 내가 만든 불필요한 코드만 정리한다. |
| Goal-Driven Execution | 구현 전에 검증 가능한 성공 기준을 정하고 충족할 때까지 반복한다. |

## 1. 핵심 규칙 (Critical Rules)

이 규칙은 편의성, 레거시 패턴, 일반적인 베스트 프랙티스 직관보다 우선한다.

### R1. 반쪽 마이그레이션 금지

하나의 View는 레거시 @Query 기반 또는 ViewModel + Repository 기반 중 하나만 사용한다. 둘을 동시에 사용하지 않는다.

~~~swift
// BAD
struct TodoView: View {
    @Query private var memos: [Memo]
    @State private var viewModel = TodoViewModel()
}
~~~

View를 마이그레이션할 때는 같은 변경 안에서 @Query를 완전히 제거한다. 요청이 해당 View의 마이그레이션을 정당화하지 않으면 기존 방식을 그대로 둔다.

### R2. 시간에 의존하는 파생 값을 저장하지 않는다

다음 질문으로 판정한다.

> 쓰기 작업 없이 자정이 지나는 것만으로 이 값이 틀릴 수 있는가?

그렇다면 저장하지 않고 저장된 사실에서 계산한다.

| 저장하는 사실 | 저장하지 않는 해석 |
|---|---|
| createdAt, deadline, sectionRaw, completedAt | today, overdue, currentBucket, 시간 의존 상태 |

### R3. @ViewBuilder 메서드는 렌더링 경계가 아니다

some View를 반환하는 헬퍼는 독립적인 SwiftUI 렌더링 경계를 만들지 않는다.

사용자 데이터 크기에 비례하는 컬렉션의 행은 값 타입을 입력으로 받는 실제 View 타입으로 만들고 Equatable을 적용한다.

~~~swift
struct TodoRowView: View, Equatable {
    let item: TodoSummary
}
~~~

R3와 R5는 사용자 데이터에 비례해 커지는 컬렉션에는 사전 측정 없이 적용할 수 있는 구조적 기본값이다. 특정 성능 원인을 단정하거나 고정 크기 컬렉션을 변경할 때는 측정한다.

### R4. @Model은 신규·마이그레이션 경계를 넘지 않는다

SwiftData @Model 객체는 Data 계층 안에 둔다.

신규 또는 마이그레이션된 코드에서는 다음을 금지한다.

- Repository API에서 @Model 반환
- ViewModel이 @Model 보유
- @Model을 액터 경계 너머로 전달
- Domain에 SwiftData 타입 노출

기존 @Query View는 해당 View를 완전히 마이그레이션하기 전까지 한시적 예외다. 예외 범위를 넓히지 않는다. 계층 경계에는 Sendable, Equatable 값 타입을 사용한다.

앱 타깃은 Swift 6 language mode를 사용한다. 동시성 위반은 컴파일러를 우회할 문제가 아니라 소유권과 경계 설계 문제로 취급한다. HorongAI 패키지는 현재 Swift 5 mode이므로 예외다.

### R5. 사용자 크기 리스트는 모든 계층에서 lazy를 유지한다

LazyVStack은 직속 자식에 대해서만 lazy하다. ScrollView부터 ForEach까지 중간 컨테이너가 eager 생성을 유발하지 않는지 확인한다.

다음에는 무조건 lazy 컨테이너로 바꾸지 않는다.

- .position 등 좌표 기반 레이아웃 의존
- 즉시 크기 계산 필요
- ScrollViewReader 동작 의존
- 요일 7개, 기분 선택지 5개 같은 고정 소규모 컬렉션

### R6. 비싼 재사용 객체는 static let으로 만든다

DateFormatter, RelativeDateTimeFormatter, NumberFormatter, NSRegularExpression을 View body, 행 생성, 반복 호출 메서드 안에서 만들지 않는다.

### R7. #Predicate 변경은 런타임 검증이 필수다

컴파일 성공은 SwiftData 변환 성공을 보장하지 않는다. 추가·수정한 predicate는 실제 또는 인메모리 ModelContainer에서 fetch하여 검증한다.

SwiftData가 직접 변환할 수 있는 저장 프로퍼티를 선호한다. 계산 프로퍼티와 임의 Swift 함수가 predicate에서 동작한다고 가정하지 않는다.

### R8. Domain 정책은 결정적이어야 한다

Domain 정책에서 Date(), UserDefaults.standard, FileManager.default 같은 환경 값을 직접 읽지 않고 입력으로 주입한다.

~~~swift
static func resolve(
    deadline: Date?,
    now: Date,
    calendar: Calendar = .current
) -> TodoBucket
~~~

자정, 월·연 경계, 윤년과 관련된 동작을 독립적으로 테스트할 수 있어야 한다.

### R9. Repository와 Gateway 경계는 Domain 값 타입을 사용한다

Repository와 Gateway의 입력·출력은 Domain Entity 또는 의미가 드러나는 값 타입이어야 한다. SwiftData 모델, API DTO, 파일 포맷을 그대로 노출하지 않는다.

무제한 조회가 비싸질 수 있으면 커서, 페이지 또는 제한을 API에 명시한다.

### R10. 새로운 Manager 타입을 만들지 않는다

책임이 드러나는 이름을 사용한다.

- 데이터 저장·조회: Repository
- 외부 기능 계약: Gateway
- 외부 기능 구현: Adapter
- 사용자 행동 조율: UseCase
- 결정 규칙: Policy
- 시스템 기능: 구체적인 Service
- 메모리 자원 소유: Store

기존 Manager는 자동 리팩터링 범위에 포함하지 않는다. 관련 기능을 마이그레이션할 때 실제 책임에 따라 분리한다.

## 2. 핵심 철학과 의존성 규칙

비즈니스 규칙을 UI, DB, 네트워크, AI 런타임과 같은 외부 도구로부터 보호한다.

- UI가 바뀌어도 Domain은 바뀌지 않는다.
- SwiftData를 다른 저장 기술로 바꿔도 Domain과 Presentation 계약은 유지된다.
- Domain은 UI·DB·외부 프로세스 없이 단독 테스트할 수 있어야 한다.
- 외부 포맷은 경계에서 Domain 값으로 변환한다.

의존성 방향은 안쪽인 Domain을 향한다.

~~~text
View → ViewModel → UseCase(선택) → Repository/Gateway protocol
                                            ↑
                              Repository/Adapter 구현
~~~

소스 코드 의존 방향은 다음과 같다.

~~~text
Presentation ──▶ Domain ◀── Data
       App ──▶ Presentation + Domain + Data
~~~

- Domain은 Presentation과 Data를 모른다.
- Presentation은 Data의 구체 타입을 모른다.
- Data는 Domain의 프로토콜을 구현한다.
- App은 의존성을 생성하고 연결하지만 비즈니스 로직을 갖지 않는다.

## 3. 목표 폴더 구조

최상위는 계층을 드러내고, Presentation 내부는 기능 단위로 응집한다.

~~~text
HorongHorong/
├── App/                         앱 시작과 의존성 조립
│   ├── HorongHorongApp.swift
│   ├── AppState.swift
│   └── DependencyContainer.swift
├── Presentation/                SwiftUI와 ViewModel
│   ├── Features/
│   │   └── <Feature>/
│   │       ├── Views/
│   │       ├── ViewModels/
│   │       └── States/          필요할 때만 생성
│   └── DesignSystem/
├── Domain/                      순수 비즈니스 규칙과 계약
│   ├── Entities/
│   ├── DTOs/
│   ├── Policies/
│   ├── UseCases/
│   ├── Repositories/            Repository protocol
│   └── Gateways/                외부 기능 protocol
└── Data/                        저장소와 외부 기술의 구체 구현
    ├── Repositories/
    ├── Adapters/
    ├── DataSources/
    │   ├── Local/
    │   │   └── SwiftData/
    │   │       └── Models/      @Model
    │   ├── Remote/
    │   └── System/
    ├── DTOs/                    API·DB 전용 포맷
    └── Mappers/
~~~

모든 하위 폴더를 미리 만들지 않는다. 파일이 하나뿐이면 기능 폴더에 평평하게 두고 두 개 이상의 같은 역할이 생길 때 분리한다. 새 추상화와 빈 폴더는 그것 때문에 쉬워지는 구체적 변경이 있을 때만 만든다.

현재 소스는 Features/, Models/, Services/, Utilities/ 중심의 레거시 구조다. 요청받은 기능을 마이그레이션할 때만 목표 구조로 옮긴다. 폴더 정리만을 이유로 요청 범위 밖의 파일을 이동하지 않는다.

### 이전 순서

목표 구조로 한 번에 옮기지 않는다. **공유 기반을 먼저 옮기고, 기능은 손댈 때 하나씩** 옮긴다.

**0단계 — 공유 기반 (기능 이전 전에 1회, 로직 변경 없이 이동만)**

| 옮길 것 | 지금 | 목표 |
|---|---|---|
| `PopoverChrome` | `Features/MenuBar/MenuBarPopover.swift` 안 | `Presentation/DesignSystem/` |
| 순수 규칙 | `Features/Mind/MemoClassifier.swift` 등 | `Domain/Policies/` |
| `@Model` 19종 | `Models/` | `Data/DataSources/Local/SwiftData/Models/` |
| OS 연동 | `Utilities/NotificationManager.swift` 등 | `Data/DataSources/System/` |
| 순수 도구 | `Utilities/KoreanParticle.swift` 등 | `Presentation/DesignSystem/` 또는 `Domain/` |

`PopoverChrome` 이 먼저인 이유: 기능 10개가 쓰는데 한 기능 파일 안에 묻혀 있어, 어느 기능을 옮기든 걸린다.

**1단계 — 파일럿 1개**

`Reward`(1,598 LOC, `@Query` 1곳, 모델 2개)를 View → ViewModel → Repository → Domain Entity 까지 끝까지 옮긴다. 작지만 Repository 경로 전체를 지난다. 여기서 정한 패턴을 이후 기능이 복제한다.

파일럿에서 반드시 결론 낼 것:
- Repository 쓰기 후 ViewModel 갱신 경로 (`@Query` 자동 갱신을 무엇으로 대체하나)
- 페이징 방식 (오프셋 vs 커서)
- Entity ↔ `@Model` Mapper 를 둘 위치

**2단계 이후 — 손대는 기능부터**

정해진 행진표는 없다. §0 의 "요청 범위를 벗어난 마이그레이션을 강행하지 않는다"가 우선한다.
기능을 수정할 일이 생기면 그때 그 기능을 옮긴다. 참고 순서는 다음과 같다.

| 우선 | 기능 | 근거 |
|---|---|---|
| 높음 | `Mind` | `@Query` 4곳으로 최다. 활발히 개발 중 |
| 높음 | `Achievement` | 9,854 LOC 단일 파일. 분할이 선행돼야 함 |
| 중간 | `Timer` · `News` · `Tracker` | 규모가 작고 경계가 뚜렷 |
| 중간 | `Lab` | SwiftData 를 안 쓴다. **Gateway/Adapter 경로의 파일럿**으로 적합 |
| 낮음 | `Stats`(14,266) · `Settings`(9,146) · `Companion`(7,086) | 크고, 지금 성능·정확성 문제가 없음 |
| 보류 | `QuickMemo` · `MenuBar` · `Hub` · `Developer` | 역할이 겹치거나 DEBUG 전용. 정리 여부부터 판단 |

**각 단계의 검증**

파일 이동만 한 단계는 `xcodegen generate` → 빌드 → 관련 테스트. 이동 커밋과 내용 변경 커밋을 분리한다(`git log --follow` 가 끊기고 회귀 원인을 못 가린다).

기능 이전 단계는 §7 검증 매트릭스를 따른다. R1(반쪽 마이그레이션 금지)이 단계 경계를 정한다 — 한 기능을 시작했으면 그 기능의 `@Query` 를 모두 없애고 끝낸다.

### 독립 실행 프로그램

저장소 루트의 현재 Agents/news_report/는 Swift 앱 계층이 아니라 별도로 실행되는 Python sidecar다. 목표 이름은 Sidecars/news_report/이며, 경로 변경은 project.yml, Makefile, 계약과 문서를 함께 수정하는 독립된 이동 작업으로 수행한다. 명시적으로 요청받기 전에는 이름을 바꾸지 않는다.

앱 안의 Agent 관련 위치는 다음 의미로 구분한다.

~~~text
Presentation/Features/Agent/     사용자가 보는 Agent 화면
Domain/Gateways/AgentGateway     AI 실행 계약
Data/Adapters/Agent/             CLI·HorongAI 연결 구현
Sidecars/news_report/            독립 Python 실행 프로그램(목표 경로)
~~~

별도의 최상위 Swift Agent/ 계층은 만들지 않는다.

## 4. 레이어 규칙

### App

앱 진입점, Scene 구성, DI composition root, 스키마 등록과 마이그레이션 시작을 담당한다.

- 모든 계층의 구체 타입을 알고 생성할 수 있다.
- ViewModel 안에서 구체 Repository를 만들지 않고 App에서 주입한다.
- 비즈니스 판단과 데이터 매핑을 넣지 않는다.

### Presentation

View의 책임:

- 렌더링
- 로컬 편집·선택·포커스 같은 임시 UI 상태
- 사용자 상호작용과 내비게이션 트리거

신규·마이그레이션 View의 금지 사항:

- @Query와 ModelContext 사용
- Data 계층 구체 타입 참조
- DB, 파일, 네트워크, AI 호출
- 재사용 가능한 비즈니스 규칙 포함

ViewModel은 @MainActor @Observable final class를 기본으로 하고 생성자 주입을 사용한다.

~~~swift
@MainActor
@Observable
final class TodoListViewModel {
    private let repository: MemoRepository

    init(repository: MemoRepository) {
        self.repository = repository
    }
}
~~~

ViewModel 안에서 구체 Repository를 생성하거나 서비스 로케이터와 불필요한 .shared를 사용하지 않는다. 프로세스 전역 정체성이 필요한 Singleton은 이유를 명시한다.

서로 배타적인 렌더 상태가 3개 이상이면 enum 상태를 사용한다. 두 가지 이하라면 단순 프로퍼티로 충분하다.

### Domain

Domain에는 Entity, 순수 DTO, Policy, UseCase, Repository/Gateway protocol을 둔다.

금지 의존성:

- SwiftUI, AppKit
- SwiftData, CoreData
- UserDefaults, Keychain
- FoundationModels와 구체 AI SDK
- 구체 영속성·네트워크 구현

Date, UUID, Calendar 같은 Foundation 값 타입은 필요할 때 사용할 수 있지만 환경을 내부에서 직접 읽지 않는다.

UseCase는 다음 중 두 개 이상을 만족할 때 도입한다.

- 둘 이상의 Repository 또는 Gateway를 조율
- 둘 이상의 ViewModel에서 재사용
- 세 개 이상의 상태 전이를 포함
- 독립적인 경계 사례 테스트가 필요한 정책 포함

해당하지 않으면 ViewModel이 Repository 또는 Gateway protocol을 직접 사용한다. 의미 없는 CRUD 래퍼를 만들지 않는다.

### Data

Data에는 다음을 둔다.

- Repository 구현
- Gateway Adapter
- SwiftData 모델과 쿼리
- API·파일·시스템 DataSource
- 외부 DTO와 Domain 타입 간 Mapper

Data는 Domain protocol을 구현하고 Presentation 타입을 참조하지 않는다. Repository와 Adapter 밖으로 SwiftData 모델이나 외부 DTO를 노출하지 않는다.

ModelContext를 명확한 생명주기 이유 없이 장기 보유하지 않는다. SwiftData 테스트에서는 컨텍스트를 사용하는 동안 ModelContainer를 살아 있게 유지한다.

### 동시성

경계를 넘는 변경마다 actor isolation, @MainActor, Sendable, Task 수명, 취소, 메인 스레드 블로킹을 점검한다.

CPU 집약 작업, 파일 I/O, DB 작업, AI 추론을 이유 없이 MainActor로 옮기지 않는다. 격리 오류를 숨기려고 Task.detached를 사용하지 않고 소유권 문제를 해결한다.

## 5. 네이밍 규칙

### 공통

- Feature 폴더는 단수형: Agent, Timer, Memo
- 역할 폴더는 복수형: Views, ViewModels, Entities, UseCases
- 타입은 단수형 PascalCase
- View와 ViewModel은 같은 화면 기본 이름을 사용
- Protocol, Interface, Impl, Default 접미사를 사용하지 않음
- 역할이 드러나지 않는 Manager, Helper, 포괄적 Utility 신규 생성 금지

### Presentation

| 책임 | 이름 | 예시 |
|---|---|---|
| 화면 | <Screen>View | AgentExperimentView |
| 화면 상태 소유 | <Screen>ViewModel | AgentExperimentViewModel |
| 화면 상태 | <Screen>ViewState | AgentExperimentViewState |
| 목록 행 | <Entity>RowView | MemoRowView |
| 입력 화면 | <Entity>EditorView | MemoEditorView |
| 상세 화면 | <Entity>DetailView | MemoDetailView |
| 화면 흐름 | <Flow>Coordinator | OnboardingCoordinator |

MemoViewModel처럼 화면이 불분명한 이름보다 MemoListViewModel, MemoDetailViewModel처럼 구체적인 화면 이름을 사용한다.

### Entity와 영속 모델

Domain Entity는 가능하면 접미사 없는 비즈니스 이름을 사용한다.

~~~text
Memo
Achievement
DateRange
~~~

신규 SwiftData 영속 타입은 <Name>Record로 이름 짓는다.

~~~text
Domain/Entities/Memo.swift
Data/DataSources/Local/SwiftData/Models/MemoRecord.swift
~~~

기존 @Model 이름은 이름 정리만을 위해 바꾸지 않는다. SwiftData 타입 이름 변경은 스키마 영향을 확인하고 별도 마이그레이션으로 수행한다. 폴더를 채우기 위해 모든 영속 모델에 대응하는 Domain Entity를 만들지 않는다.

### Repository

| 구분 | 이름 | 예시 |
|---|---|---|
| Domain 계약 | <Entity>Repository | MemoRepository |
| SwiftData 구현 | SwiftData<Entity>Repository | SwiftDataMemoRepository |
| 인메모리 구현 | InMemory<Entity>Repository | InMemoryMemoRepository |
| 파일 구현 | File<Entity>Repository | FileMemoRepository |

Repository 구현을 MemoRepositoryImpl이나 MemoStore로 이름 짓지 않는다. 구현 기술 또는 전략을 이름에 표시한다.

### Gateway와 Adapter

Repository는 앱이 소유하는 데이터의 저장·조회에 사용한다. AI, 알림, OS 기능처럼 외부 능력을 호출하는 경계는 Gateway로 표현한다.

| 구분 | 이름 | 예시 |
|---|---|---|
| Domain 계약 | <Capability>Gateway | AgentGateway |
| 구체 구현 | <Technology><Capability>Adapter | CLIAgentAdapter |
| 테스트 구현 | Fake<Capability>Gateway | FakeAgentGateway |

### UseCase와 Policy

UseCase는 <Verb><Object>UseCase로 이름 짓고 공개 실행 메서드는 execute를 사용한다.

~~~text
GenerateAgentPlanUseCase
RunTodayExperimentUseCase
CompleteTodoUseCase
~~~

입력과 출력이 한 UseCase에서만 쓰이면 Input, Output 중첩 타입으로 둔다.

Policy는 <Concept>Policy로 이름 짓는다.

~~~text
TodoPolicy
AchievementPolicy
FocusScorePolicy
~~~

### DTO, 화면 데이터와 Data 타입

DTO 접미사는 API, 파일, DB 같은 외부 형식에만 사용한다.

~~~text
NewsJobRequestDTO
NewsJobResponseDTO
~~~

Domain과 Presentation에서는 용도를 나타내는 이름을 사용한다.

| 의미 | 이름 예시 |
|---|---|
| 목록용 요약 | MemoSummary |
| 상세 데이터 | MemoDetails |
| 일관된 상태 묶음 | TodoSnapshot |
| 변경 명령 | CompleteTodoCommand |
| 실행 결과 | GenerateAgentPlanResult |
| 화면 상태 | AgentExperimentViewState |

Row는 실제 화면 행인 RowView에 사용한다. Domain 전달 타입을 일괄적으로 ~Row라 부르지 않는다.

| Data 책임 | 이름 | 예시 |
|---|---|---|
| 원본 접근 | <Source><Entity>DataSource | NewsAPIDataSource |
| 저수준 외부 통신 | <Capability>Client | TelemetryClient |
| 형식 변환 | <Entity>Mapper | MemoMapper |
| Gateway 구현 | <Technology><Capability>Adapter | CLIAgentAdapter |

DataSource는 Repository가 여러 원본을 조율하거나 원본 접근을 독립적으로 교체해야 할 때만 만든다. Repository가 SwiftData를 직접 사용해도 충분하다면 추가 계층을 만들지 않는다.

### Store, Service, Controller

- Store: 장기간 유지되는 인메모리 상태나 캐시 자원을 소유할 때만 사용한다. 예: MLXModelStore.
- Service: Repository, Gateway, Adapter, UseCase로 표현되지 않는 구체적인 지속 시스템 기능에 제한한다. 예: FocusTimerService.
- Controller: AppKit 윈도우·이벤트·수명주기를 직접 제어하는 경계에만 사용한다.
- Coordinator: 화면 전환이나 여러 Presentation 흐름의 조율에 사용한다.

기존 TimerManager, AppUpdateManager, HotKeyManager는 이름만 바꾸지 않는다. 각 기능을 마이그레이션할 때 책임을 측정하고 분리한다.

## 6. 작업 흐름

다음 중 하나라도 해당하면 사소하지 않은 변경이다.

- 파일 3개 이상 변경
- 신규 타입 또는 공개 API 추가
- 데이터 모델이나 #Predicate 변경
- 동시성 경계 변경
- 아키텍처 경계 또는 의존 방향 변경

사소하지 않은 변경은 다음 순서로 진행한다.

~~~text
조사 → 실행 경로 파악 → 영향 식별 → 성공 기준 정의
→ 최소 변경 → 좁은 검증 → 관련 회귀 검증 → 아키텍처 점검 → 보고
~~~

수정 전에 다음을 간결하게 명시한다.

~~~text
[대상] [기능] [레이어] [의존성]
[영향받는 동작] [아키텍처 리스크] [회귀 리스크]
~~~

성공 기준은 실행 가능한 형태로 정한다.

| 약한 기준 | 유효한 기준 |
|---|---|
| 정렬이 잘 되게 | 자정 직전·직후 정책 테스트 추가 후 통과 |
| 성능 개선 | 동일 데이터와 절차로 전후 수치 비교 |
| 리팩터링 | 기존 관련 테스트 유지 + 의존성 체크 통과 |

### 반드시 질문할 것

저장소에서 기존 구현, 테스트, 호출부, ADR을 먼저 조사한 뒤에도 다음에 해당하면 진행을 멈추고 묻는다.

- @Model 프로퍼티 추가·삭제·타입 변경 또는 타입 이름 변경
- 파일 삭제나 파괴적 Git 작업
- 요청받은 View 밖으로 마이그레이션 범위가 확장됨
- 핵심 규칙끼리 충돌하고 우선순위로 해소되지 않음
- 요청된 동작이 통과 중인 기존 테스트와 모순됨

다음은 합리적으로 가정하고 완료 보고에 기록한다.

- 신규 내부 타입 이름
- 내부 함수 시그니처
- 테스트 케이스 개수와 선정
- §3과 §5로 결정할 수 있는 파일 위치

### 아키텍처 체크리스트

사소하지 않은 변경 후 다음을 점검한다.

- Presentation이 Data 구현을 직접 참조하지 않는가
- Presentation이 ModelContext 또는 신규 @Query를 사용하지 않는가
- Domain이 SwiftUI, AppKit, SwiftData를 참조하지 않는가
- @Model이나 외부 DTO가 경계를 넘지 않는가
- Repository/Gateway가 구현 세부를 노출하지 않는가
- 새로운 전역 상태나 불필요한 Singleton이 생기지 않았는가
- 순환 의존과 반쪽 View 마이그레이션이 없는가
- 단일 사용을 위한 불필요한 추상화가 없는가

## 7. 검증

### 검증 매트릭스

| 변경 | 필요한 검증 |
|---|---|
| 문서·주석만 변경 | git diff --check, 내용·경로 확인 |
| Domain Policy | 경계 사례를 포함한 유닛 테스트 |
| Repository | 인메모리 컨테이너 기반 Repository 또는 통합 테스트 |
| #Predicate | 실제 런타임 fetch |
| SwiftData 매핑 | 영속성 테스트 |
| ViewModel 동작 | 사소하지 않은 로직의 유닛 테스트 |
| View 렌더링 | 수동 시각 확인 |
| 성능 주장 | 같은 조건의 전후 측정 |
| Swift 파일 이동 | 프로젝트 생성 확인 + 빌드 + 관련 테스트 |
| 아키텍처 경계 | §6 체크리스트 |
| 동시성 변경 | 빌드 + 격리 검토 + 관련 테스트 |

테스트 우선순위는 Domain 유닛 → Repository → ViewModel → 통합 → 수동 UI다. 관련 없는 UI 자동화를 추가하지 않는다.

### 빌드와 테스트

mlx-swift 플러그인 검증 문제를 피하기 위해 두 플래그를 사용한다.

~~~bash
xcodebuild \
  -project HorongHorong.xcodeproj \
  -scheme HorongHorong \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  test
~~~

반복 중에는 좁은 테스트를 먼저 실행하고 완료 전 관련 회귀 스위트를 실행한다. 문서·주석만 변경했다면 Swift 빌드는 필요하지 않다.

빌드나 테스트가 실패하면 실제 에러를 읽고 원인을 수정한다. 같은 명령을 이유 없이 반복하지 않는다. 동일한 원인 가설에 따른 수정이 두 번 실패하면 중단하고 에러, 시도, 남은 가설을 보고한다.

### 성능 작업

~~~text
재현 → 기준 측정 → 가설 → 최소 변경 → 재측정 → 비교
~~~

측정 없이 성능 원인을 단정하지 않는다. let _ = Self._printChanges()와 대표 데이터, 필요하면 1만 건 합성 데이터를 사용한다. 명시적 요청이 없으면 임시 계측 코드는 작업 종료 전에 제거한다.

### 완료 정의

- [ ] 요청한 동작이 구현됨
- [ ] 관련 없는 코드가 변경되지 않음
- [ ] 핵심 규칙과 의존 방향 준수
- [ ] 변경 위험에 맞는 검증 완료
- [ ] predicate 변경 시 런타임 검증 완료
- [ ] 성능 주장 시 전후 측정 완료
- [ ] 임시 디버깅 코드 제거
- [ ] 미검증 항목과 한계 보고

검증하지 못한 항목은 다음 형식으로 보고한다.

~~~text
[미검증] [사유] [회귀 리스크]
~~~

사소하지 않은 변경의 완료 보고는 다음 순서를 사용한다.

~~~text
[변경 내용]
[아키텍처 영향]
[의존성 변경]
[테스트 / 검증]
[회귀 리스크]
[적용한 가정]
[남은 리팩터링]
~~~

작은 변경에는 필요한 항목만 간결하게 보고한다. 정확성에 영향이 없는 관련 없는 후속 리팩터링을 제안하지 않는다.

## 8. 주석

주석은 WHAT이 아니라 WHY를 한국어로 설명한다. Swift/API/타입 이름은 원형을 유지한다.

~~~swift
// GOOD — 프레임워크 함정과 이유를 설명한다.
// @Query는 다음 run loop에 갱신되므로 여기서 balance를 읽으면 이전 값이 나온다.

// BAD — 코드를 반복한다.
// 메모를 필터링한다.
~~~

다음에는 주석을 남길 가치가 있다.

- 더 단순해 보이는 대안을 기각한 이유
- 알려진 프레임워크 함정
- 아키텍처 경계
- 측정에 근거한 성능 결정
- 특정 페이징 크기나 우회책의 이유

해결되지 않은 가정은 [확인 필요]로 표시한다.

## 9. 참조 문서

일반적인 구현에 필요한 규칙은 이 문서에 있다. 다음 문서는 조건부로 읽는다.

| 문서 | 읽는 시점 |
|---|---|
| docs/5. 운영/프로젝트 운영/11. 협업 가이드/Swift 코드 컨벤션.md | 주석 규약, SwiftData 실패 이력, 저장소 고유 패턴의 근거가 필요할 때 |
| docs/2. 설계/3. 시스템 설계서/기술 의사결정/ADR-002-MVVM-Repository-AgentGateway-채택.md | Repository/Gateway 경계나 MVVM 결정을 재검토할 때 |
| docs/5. 운영/프로젝트 운영/12. 기술 문서/Architecture/app-folder-structure-decisions.md | 기존 폴더 결정의 배경을 확인할 때 |
| docs/5. 운영/프로젝트 운영/12. 기술 문서/Refactoring/2026-09-01-app-wide-mvvm-repository-migration.md | 기존 기능의 마이그레이션 상태와 순서를 확인할 때 |

기존 폴더 구조 문서의 App / Features / Domain / Data / Agent / Shared 안은 이 문서 작성 이전 결정이다. §3의 App / Presentation / Domain / Data와 충돌하는 배치는 이 문서가 우선하며, 관련 설계 문서는 별도 문서 정리 작업에서 동기화한다.

## 10. 최종 원칙

다음을 최적화한다.

> 가장 작은 올바른 변경 + 명확한 의존 방향 + 검증 가능한 동작 + 낮은 회귀 리스크

바꾸기 전에 프로젝트와 실행 경로를 이해한다. 광범위한 재작성보다 기능 단위의 완전한 점진적 마이그레이션을 택한다. 아키텍처의 순수성과 더 단순하고 안전한 해법이 충돌하면 안전한 쪽을 택하고 이유를 남긴다.

