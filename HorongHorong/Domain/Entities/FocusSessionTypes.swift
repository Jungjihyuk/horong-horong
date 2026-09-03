import Foundation

enum FocusSessionEndKind: String, Sendable {
    case timerCompleted = "timer_completed"
    case recordedEarly = "recorded_early"
}

/// 포모도로가 실제로 멈춰 있던 벽시계 구간.
struct FocusSessionPauseInterval: Codable, Equatable, Sendable {
    let startedAt: Date
    let endedAt: Date
}

enum FocusSessionTaskLinkUpdateError: LocalizedError, Equatable, Sendable {
    case pendingChanges
    case sessionNotFound
    case taskCompletionExists

    var errorDescription: String? {
        switch self {
        case .pendingChanges:
            "저장되지 않은 다른 변경사항이 있어 할 일 연결을 수정할 수 없습니다."
        case .sessionNotFound:
            "수정할 포모도로 세션을 찾을 수 없습니다."
        case .taskCompletionExists:
            "할 일 완료 기록이 있는 세션은 연결을 변경할 수 없습니다."
        }
    }
}
