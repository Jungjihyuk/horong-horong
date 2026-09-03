import Foundation
import SwiftData

/// `NewsPipelineGateway` 의 구현.
///
/// **화면에서 `ModelContext` 를 걷어내는 것이 이 타입의 목적이다.** 실행을 시작하면
/// 실행 기록(`NewsJob`)이 한 줄 생기는데, 그걸 만들려면 컨텍스트가 필요했다.
@MainActor
struct NewsPipelineAdapter: NewsPipelineGateway {
    private let service: NewsPipelineService
    private let context: ModelContext

    init(service: NewsPipelineService, context: ModelContext) {
        self.service = service
        self.context = context
    }

    func launch() {
        NewsPipelineLaunchConfiguration.current().launch(on: service, context: context)
    }
}
