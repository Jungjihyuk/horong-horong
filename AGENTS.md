# 저장소 작업 규칙

이 문서는 호롱호롱(HorongHorong) 저장소에서 작업하는 AI 코딩 에이전트와 엔지니어를 위한 실행 가이드다.  
목표는 불필요한 형식주의가 아니라 **정확하고, 군더더기 없으며, 검증 가능하고, 회귀에 안전한 변경**이다.

앱은 **MVVM + Clean Architecture**(Presentation / Domain / Data) 구조로 전환을 완료했다.  
모든 화면에서 `@Query`가 완전히 제거(0개)되었으며, `View → ViewModel → Repository` 단방향 파이프라인으로 일관되게 동작한다.

`AGENTS.md`와 `CLAUDE.md`는 항상 동일한 내용으로 유지한다. 규칙을 변경할 때는 두 파일을 함께 갱신하고 `cmp -s AGENTS.md CLAUDE.md`로 일치 여부를 확인한다.

---

## 0. 작업 우선순위 & 기본 원칙

지시가 충돌할 때는 다음 순서를 따른다:
1. 사용자의 명시적 요청
2. 핵심 규칙 (§1)
3. 아키텍처 및 레이어 규칙 (§2~§3)
4. 검증 요구사항 (§5)
5. 기존 코드베이스 구현 스타일

충돌 시 선호 순서:
> **정확성 → 회귀 안전성 → 가독성 → 아키텍처 일관성 → 성능 → 추상화**

### 안드레 카파시 (Karpathy) 기본 원칙

| 원칙 | 실천 지침 |
|---|---|
| **Think Before Coding** | 임의로 추측하거나 넘겨짚지 않는다. 요구사항이 모호하면 질문하고 대안과 영향도를 제시한다. |
| **Simplicity First (YAGNI)** | 문제를 해결하는 가장 작고 단순한 코드만 작성한다. 미래를 가정한 과도한 추상화나 불필요한 보일러플레이트를 만들지 않는다. |
| **Surgical Changes (정밀 타격)** | 필요한 라인만 정밀하게 수정한다. 요청과 무관한 주변 코드, 스타일, 주석을 건드리지 않는다. |
| **Goal-Driven Execution** | 구현 전 검증 가능한 성공 기준(테스트/빌드)을 먼저 정하고, 통과할 때까지 검증 루프를 반복한다. |
| **Don't Hallucinate Success** | 실제로 실행하지 않은 빌드나 테스트를 완료했다고 거짓 보고하지 않는다. 실패나 잠재 위험을 솔직하게 보고한다. |

---

## 1. 핵심 아키텍처 규칙 (Critical Rules)

### R1. MVVM + Repository 아키텍처 준수 (@Query 직접 사용 금지)
SwiftUI View에서 **`@Query` 및 `ModelContext`를 직접 사용할 수 없다** (전체 뷰 0개 유지).  
View는 오직 `@Observable` ViewModel만 관찰하고, ViewModel은 Domain 계층의 `Repository` 프로토콜을 통해서만 데이터를 다룬다.

```swift
// BAD: View가 SwiftData @Query나 ModelContext를 직접 소유
struct TodoView: View {
    @Query private var todos: [Todo] // 금지
    @Environment(\.modelContext) private var modelContext // 금지
}

// GOOD: View는 ViewModel만 관찰, ViewModel이 Repository를 주입받아 처리
struct TodoView: View {
    @State private var viewModel: TodoViewModel

    init(viewModel: TodoViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
}
```

### R2. 시간에 따라 변하는 파생 값은 저장하지 않는다
> "쓰기 작업 없이 자정이 지나는 것만으로 이 값이 틀릴 수 있는가?"  
그렇다면 저장하지 않고 저장된 원본 데이터로부터 실시간 계산한다.

| 저장하는 원본 데이터 | 저장하지 않는 파생 해석 |
|---|---|
| `createdAt`, `deadline`, `completedAt` | `isToday`, `isOverdue`, 현재 버킷 상태 |

### R3. 대량 목록은 렌더링 최적화를 유지한다
- `@ViewBuilder` 헬퍼 메서드는 렌더링 경계를 만들지 않는다.
- 데이터 크기에 비례하는 컬렉션 행은 값 타입을 받는 독립 View 구조체로 분리하고 `Equatable`을 적용한다.
- `LazyVStack` 등 지연 컨테이너 중간에 크기를 즉시 계산하는 eager 컨테이너가 끼어들지 않도록 주의한다.

```swift
struct TodoRowView: View, Equatable {
    let item: TodoItem
}
```

### R4. @Model은 Data 계층 내부에서만 생존한다
SwiftData `@Model` 객체는 Data 계층 내부(DB 저장/조회/매핑)에서만 사용한다.

- Repository 인터페이스가 계층 밖으로 `@Model`을 직접 반환할 수 없다.
- ViewModel이 `@Model` 프로퍼티를 보유할 수 없다.
- 계층 경계를 넘을 때는 항상 불변 값 타입(`Sendable`, `Equatable` 준수 Struct: `TodoItem`, `DiaryDay` 등)을 사용한다.

```swift
// BAD: Repository가 SwiftData @Model을 계층 밖으로 노출
protocol TodoRepository: Sendable {
    func fetchTodos() async throws -> [Todo] // @Model 노출 금지
}

// GOOD: Domain 값 타입(Sendable Struct) 반환
protocol TodoRepository: Sendable {
    func fetchTodos() async throws -> [TodoItem]
}
```

### R5. Swift 6 동시성 우회 편법 금지 (Strict Concurrency)
- 컴파일러 경고나 에러를 끄기 위해 `nonisolated(unsafe)`를 무분별하게 사용하지 않는다. (불가피한 경우 명확한 사유 주석 필수)
- 격리 에러를 회피하려고 `Task.detached`를 남발하지 않는다.
- 동시성 이슈는 편법이 아니라 **데이터 소유권 정리와 `Sendable` 불변 값 타입 설계**로 해결한다.

```swift
// BAD: 동시성 경고를 피하기 위해 unsafe 키워드로 무마
nonisolated(unsafe) var currentItem: TodoItem?

// GOOD: 격리 컨텍스트(@MainActor)를 명시하거나 Sendable 값 타입으로 해결
@MainActor var currentItem: TodoItem?
```

### R6. 단방향 데이터 흐름 (UDF) 준수
UI 상태 변경과 영속화는 예측 가능한 단방향 파이프라인으로 흐른다:
```text
[사용자 액션] ➔ [ViewModel 의도/메서드] ➔ [Repository 영속화] ➔ [ViewModel 상태 갱신] ➔ [View 렌더링]
```
- View body 내부에서 비즈니스 계산이나 직접적인 쓰기 부수 효과를 일으키지 않는다.
- 데이터 무효화 및 재적재는 쓰기 작업 완료 후 ViewModel의 명시적 `reload()`를 통해 일관되게 동기화한다.

### R7. 무거운 재사용 객체는 static 인스턴스로 캐싱한다
`DateFormatter`, `RelativeDateTimeFormatter`, `NumberFormatter`, 정규식 객체를 View body나 반복문 내부에서 매번 생성하지 않는다.

### R8. #Predicate 변경은 런타임 검증이 필수다
컴파일 성공이 SwiftData 변환 성공을 보장하지 않는다. 추가·수정한 predicate는 인메모리 또는 실제 컨테이너에서 fetch 런타임 동작을 반드시 확인한다.

### R9. Domain 정책은 결정적이어야 한다 (외부 환경 주입)
Domain 로직 내부에서 `Date()`, `UserDefaults.standard` 등을 직접 읽지 않고 매개변수로 주입받아 독립 테스트가 가능하게 만든다.

```swift
static func resolve(
    deadline: Date?,
    now: Date,
    calendar: Calendar = .current
) -> TodoBucket
```

### R10. 무분별한 Manager 타입 신규 생성 금지
역할이 불분명한 Manager 대신 책임이 명확한 이름을 부여한다:
- 데이터 저장/조회: `Repository`
- 외부 시스템/OS 연동 인터페이스: `Gateway`
- Gateway 구체 구현: `Adapter`
- 복합 비즈니스 흐름 조율: `UseCase`
- 규칙 및 정책: `Policy`
- 인메모리 캐시 소유: `Store`

---

## 2. 계층 및 의존성 규칙

의존성 방향은 항상 안쪽(Domain)을 향한다:
```text
Presentation ──▶ Domain ◀── Data
       App ──▶ Presentation + Domain + Data
```

- **Domain**: 순수 비즈니스 규칙과 계약 (SwiftUI, SwiftData, AppKit 등 외부 프레임워크 의존 절대 금지).
- **Presentation**: View와 ViewModel (Data 계층 구체 구현을 알지 못하며, Domain 인터페이스에만 의존).
- **Data**: Repository 구현체, SwiftData `@Model`, 시스템 어댑터 (Domain 인터페이스를 구현).
- **App**: 의존성 조립(DI) 및 앱 수명주기 관리.

---

## 3. 폴더 구조

```text
HorongHorong/
├── App/                         # 앱 진입점 및 의존성 조립 (DI)
├── Presentation/                # UI 및 화면 상태
│   ├── Features/                # 기능별 화면 (SecondBrain, Timer, News, Stats, Settings 등)
│   │   └── <Feature>/
│   │       ├── Views/
│   │       └── ViewModels/
│   └── DesignSystem/            # 공용 컴포넌트, 스타일, 테마
├── Domain/                      # 순수 비즈니스 로직 및 계약
│   ├── Entities/                # 도메인 모델 값 타입
│   ├── Policies/                # 도메인 결정 규칙
│   ├── UseCases/                # 비즈니스 흐름 조율
│   ├── Repositories/            # 저장소 프로토콜
│   └── Gateways/                # 외부 연동 프로토콜
└── Data/                        # 구체 구현 계층
    ├── Repositories/            # Repository 구현체 (SwiftData 등)
    ├── Adapters/                # Gateway 어댑터 (AI, OS 연동 등)
    └── DataSources/             # 데이터 소스
        ├── Local/SwiftData/     # SwiftData @Model 및 스키마
        └── System/              # 알림, 핫키 등 시스템 연동
```

---

## 4. 네이밍 컨벤션

### 영속 모델 (`@Model`)
인위적인 접미사(`Record`, `Entry`)를 붙이지 않고 **고유 명사 단수형**을 사용한다. SQLite 테이블명(`ZTODO`, `ZQUICKNOTE`, `ZREFERENCE`, `ZDIARY`)과 직관적으로 일치시킨다.
- `@Model final class Todo` ➔ `ZTODO`
- `@Model final class QuickNote` ➔ `ZQUICKNOTE`
- `@Model final class Reference` ➔ `ZREFERENCE`
- `@Model final class Diary` ➔ `ZDIARY`
- `@Model final class FocusSession` ➔ `ZFOCUSSESSION`

### Domain / Presentation 값 타입
영속 모델과의 이름 충돌을 방지하고 역할이 드러나도록 명명한다.
- `TodoItem` (또는 `TodoSummary`)
- `DiaryDay`
- `NoteText`

### Repository
- Domain 프로토콜: `<Entity>Repository` (예: `TodoRepository`)
- Data 구현체: `<Technology><Entity>Repository` (예: `SwiftDataTodoRepository`, `InMemoryTodoRepository`)

---

## 5. 검증 파이프라인 & 테스트 원칙

### 에이전트 표준 검증 절차
코드 변경 후 완료를 보고하기 전 다음 순서로 검증을 마쳐야 한다:

1. `xcodegen generate` — 파일 추가/삭제/이동 시 Xcode 프로젝트(`.xcodeproj`) 동기화
2. `make build` — 컴파일 및 Swift 6 동시성 에러 검증
3. `make app-test` — **전체 단위/통합 테스트 통과 (802개 이상, 0 failures)** 확인
4. `#Predicate` 검증 — SwiftData 쿼리 변경 시 인메모리/실제 컨테이너 fetch 런타임 확인
5. `cmp -s AGENTS.md CLAUDE.md` — 규칙 문서 일치 검증
6. `git status` — 작업 트리 정돈 상태 확인

### 테스트 퇴보 방지 원칙 (Regression Shield)
- 현재 전체 테스트는 **802개**이며 0 failures 상태다.
- 테스트 개수는 기능 추가에 따라 증가해야 하며, **임의로 기존 테스트를 삭제하거나 스킵(`@Test(.disabled)`)하여 개수를 줄이는 행위를 엄격히 금지**한다.
- 테스트가 실패할 경우 테스트 검증 조건을 완화하지 않고 실제 구현 코드를 수정한다.

### 버그 수정 원칙 (Red-Green-Refactor)
- 버그 수정 시 **버그를 재현하는 실패 테스트(Red)를 먼저 작성**한다.
- 버그를 해결하는 최소 코드를 작성하여 테스트를 통과(Green)시킨다.
- 전체 테스트 스위트를 실행하여 회귀가 없음을 입증한다.

---

## 6. 주석 및 커뮤니케이션

- 주석은 코드가 '무엇(WHAT)'을 하는지가 아니라 **'왜(WHY)' 그렇게 작성했는지(의도와 배경)**를 한국어로 명확히 설명한다.
- 알려진 프레임워크 함정, 성능상의 이유로 선택한 우회책, 아키텍처 경계에 대한 근거를 주석으로 남긴다.
- 작업 완료 보고 시에는 변경 내용, 아키텍처 영향, 검증 결과(통과 테스트 수)를 군더더기 없이 간결하게 보고한다.

