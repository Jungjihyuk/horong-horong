import Foundation
import OSLog

enum TelemetryError: Error {
    case notConfigured
    case invalidResponse
    case requestFailed(statusCode: Int, body: String)
}

struct FeedbackEventPayload: Encodable {
    let id: String
    let anonymous_install_id: String
    let app_version: String
    let os_version: String
    let event_name: String
    let feedback_location: String
    let source_feature: String
}

struct AttentionFeedbackPayload: Encodable {
    let feedback_event_id: String
    let flow_state: String?
    let signal_type: String?
    let verdict: String
    let threshold_preset: String?
    let score_bucket: String?
    let comment_present: Bool
    let sanitized_comment: String?
}

final class TelemetryClient: @unchecked Sendable {
    static let shared = TelemetryClient()

    private let configProvider: () -> TelemetryConfig?
    private let session: URLSession
    private let encoder: JSONEncoder

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.horonghorong",
        category: "Telemetry"
    )

    init(
        configProvider: @escaping () -> TelemetryConfig? = { TelemetryConfig.load() },
        session: URLSession = .shared
    ) {
        self.configProvider = configProvider
        self.session = session
        self.encoder = JSONEncoder()
    }

    var isConfigured: Bool {
        configProvider()?.isConfigured == true
    }

    func recordConsent(_ status: TelemetryConsentStatus) async {
        do {
            try await insert(
                TelemetryConsentStore.payload(status: status),
                into: "telemetry_consents"
            )
            Self.logger.notice("Telemetry consent recorded status=\(status.rawValue, privacy: .public)")
        } catch {
            Self.logger.error("Telemetry consent record failed: \(String(describing: error), privacy: .public)")
        }
    }

    func submitAttentionFeedback(
        eventName: String,
        feedbackLocation: String,
        flowState: String?,
        signalType: String?,
        verdict: String,
        thresholdPreset: String?,
        scoreBucket: String?,
        sanitizedComment: String?
    ) async -> Bool {
        guard TelemetryConsentStore.isEnabled else { return false }

        do {
            let eventID = UUID().uuidString
            let event = FeedbackEventPayload(
                id: eventID,
                anonymous_install_id: AnonymousInstallID.current(),
                app_version: TelemetryRuntimeInfo.appVersion,
                os_version: TelemetryRuntimeInfo.osVersion,
                event_name: eventName,
                feedback_location: feedbackLocation,
                source_feature: "attention"
            )
            try await insert(
                event,
                into: "feedback_events"
            )

            let comment = sanitizedComment?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = AttentionFeedbackPayload(
                feedback_event_id: eventID,
                flow_state: flowState,
                signal_type: signalType,
                verdict: verdict,
                threshold_preset: thresholdPreset,
                score_bucket: scoreBucket,
                comment_present: comment?.isEmpty == false,
                sanitized_comment: comment?.isEmpty == false ? comment : nil
            )
            try await insert(
                detail,
                into: "attention_feedback_details"
            )
            Self.logger.notice("Attention feedback submitted location=\(feedbackLocation, privacy: .public) verdict=\(verdict, privacy: .public)")
            return true
        } catch {
            Self.logger.error("Attention feedback submit failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func insert<Payload: Encodable>(
        _ payload: Payload,
        into table: String
    ) async throws {
        guard let config = configProvider() else {
            throw TelemetryError.notConfigured
        }

        let endpoint = config.supabaseURL
            .appending(path: "rest")
            .appending(path: "v1")
            .appending(path: table)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TelemetryError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TelemetryError.requestFailed(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}
