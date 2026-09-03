import Foundation

enum PomodoroFocusExperience: String, CaseIterable, Identifiable, Sendable {
    case deeplyFocused = "deeply_focused"
    case mostlyFocused = "mostly_focused"
    case frequentlyDistracted = "frequently_distracted"
    case difficultToFocus = "difficult_to_focus"
    case unsure = "unsure"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deeplyFocused: return "깊게 몰입했어요"
        case .mostlyFocused: return "대체로 집중했어요"
        case .frequentlyDistracted: return "자주 흐트러졌어요"
        case .difficultToFocus: return "집중하기 어려웠어요"
        case .unsure: return "잘 모르겠어요"
        }
    }
}

enum PomodoroProgressResult: String, CaseIterable, Identifiable, Sendable {
    case completedAsPlanned = "completed_as_planned"
    case meaningfulProgress = "meaningful_progress"
    case littleProgress = "little_progress"
    case goalChanged = "goal_changed"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .completedAsPlanned: return "계획한 만큼 끝냈어요"
        case .meaningfulProgress: return "의미 있게 진행했지만 남았어요"
        case .littleProgress: return "거의 진행하지 못했어요"
        case .goalChanged: return "진행 중 목표가 바뀌었어요"
        }
    }

    var requiresReason: Bool {
        self != .completedAsPlanned
    }

    func label(recordsLinkedTaskCompletion: Bool) -> String {
        if self == .completedAsPlanned, recordsLinkedTaskCompletion {
            return "이 할 일을 모두 끝냈어요"
        }
        return label
    }
}

enum PomodoroIncompleteReason: String, CaseIterable, Identifiable, Sendable {
    case insufficientTime = "insufficient_time"
    case underestimatedScope = "underestimated_scope"
    case continuedForQuality = "continued_for_quality"
    case blocked = "blocked"
    case switchedTask = "switched_task"
    case distracted = "distracted"
    case externalInterruption = "external_interruption"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .insufficientTime: return "설정한 시간이 짧았어요"
        case .underestimatedScope: return "예상보다 작업이 컸어요"
        case .continuedForQuality: return "원하는 수준까지 더 다듬고 싶었어요"
        case .blocked: return "막힌 부분이 있었어요"
        case .switchedTask: return "다른 작업으로 옮겼어요"
        case .distracted: return "방해 요소에 집중이 흐트러졌어요"
        case .externalInterruption: return "외부 요청이나 일정이 생겼어요"
        }
    }
}
