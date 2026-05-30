import Foundation

enum TelemetryConsentStatus: String, Codable {
    case enabled
    case disabled
}

struct TelemetryConsentPayload: Encodable {
    let anonymous_install_id: String
    let app_version: String
    let os_version: String
    let consent_scope: String
    let consent_status: String
}

enum TelemetryConsentStore {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.AppStorageKey.anonymousTelemetryEnabled)
    }

    static var hasPromptedForConsent: Bool {
        UserDefaults.standard.bool(forKey: Constants.AppStorageKey.anonymousTelemetryPrompted)
    }

    static var shouldPromptForConsent: Bool {
        !hasPromptedForConsent && TelemetryClient.shared.isConfigured
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Constants.AppStorageKey.anonymousTelemetryEnabled)
        UserDefaults.standard.set(true, forKey: Constants.AppStorageKey.anonymousTelemetryPrompted)
    }

    static func declineInitialPrompt() {
        UserDefaults.standard.set(false, forKey: Constants.AppStorageKey.anonymousTelemetryEnabled)
        UserDefaults.standard.set(true, forKey: Constants.AppStorageKey.anonymousTelemetryPrompted)
    }

    static func payload(status: TelemetryConsentStatus) -> TelemetryConsentPayload {
        TelemetryConsentPayload(
            anonymous_install_id: AnonymousInstallID.current(),
            app_version: TelemetryRuntimeInfo.appVersion,
            os_version: TelemetryRuntimeInfo.osVersion,
            consent_scope: "anonymous_feedback",
            consent_status: status.rawValue
        )
    }
}
