import Foundation
import SwiftData

@Model
final class NewsReportIndex {
    var jobId: String
    var reportDate: Date
    var reportPath: String
    var metaPath: String
    var topTitle: String
    var itemCount: Int
    var createdAt: Date

    init(
        jobId: String,
        reportDate: Date,
        reportPath: String,
        metaPath: String,
        topTitle: String,
        itemCount: Int
    ) {
        self.jobId = jobId
        self.reportDate = reportDate
        self.reportPath = reportPath
        self.metaPath = metaPath
        self.topTitle = topTitle
        self.itemCount = itemCount
        self.createdAt = Date()
    }
}
