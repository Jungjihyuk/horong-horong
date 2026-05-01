import Foundation
import SwiftData

@Model
final class NewsJob {
    var jobId: String
    var status: String          // queued, running, partial_success, success, failed
    var provider: String
    var requestedAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var errorCode: String?
    var errorMessage: String?
    var logPath: String?

    init(jobId: String, provider: String) {
        self.jobId = jobId
        self.status = "queued"
        self.provider = provider
        self.requestedAt = Date()
    }
}
