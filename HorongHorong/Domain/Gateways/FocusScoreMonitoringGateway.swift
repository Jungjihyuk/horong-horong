import Foundation

/// 진행 중인 집중 상태를 관찰해 필요한 순간에 넛지를 요청한다.
@MainActor
protocol FocusScoreMonitoringGateway: AnyObject {
    func start()
    func stop()
}
