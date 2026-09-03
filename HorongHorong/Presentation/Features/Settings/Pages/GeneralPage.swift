import SwiftUI
import ServiceManagement

struct GeneralPage: View {
    #if DIRECT_DISTRIBUTION
    @ObservedObject private var updater = AppUpdateManager.shared
    #endif
    @State private var launchAtLogin: Bool = false

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.general.label, subtitle: SettingsTab.general.subtitle)

            SettingsGroupCard("동작") {
                SettingsRow(
                    "로그인 시 자동 시작",
                    subtitle: "Mac 로그인 시 호롱호롱을 자동으로 실행합니다."
                ) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = !newValue
                            }
                        }
                }
                updateRow
            }

        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            #if DIRECT_DISTRIBUTION
            updater.refreshState()
            #endif
        }
    }

    @ViewBuilder
    private var updateRow: some View {
        #if DIRECT_DISTRIBUTION
        SettingsRow(
            "자동으로 업데이트 확인",
            subtitle: updater.isConfigured
                ? "새 버전이 있으면 알림창으로 업데이트 여부를 묻습니다."
                : "appcast URL과 Sparkle 공개키를 설정하면 사용할 수 있습니다."
        ) {
            Toggle(
                "",
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .labelsHidden()
            .disabled(!updater.isConfigured)
        }
        #else
        SettingsRow(
            "앱 업데이트",
            subtitle: "Mac App Store에서 자동으로 관리됩니다."
        ) {
            Text("App Store")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        #endif
    }
}
