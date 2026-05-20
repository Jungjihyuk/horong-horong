import SwiftUI
import ServiceManagement

struct GeneralPage: View {
    @State private var launchAtLogin: Bool = false
    @State private var autoUpdate: Bool = true
    @State private var telemetry: Bool = false

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
                SettingsRow(
                    "자동 업데이트",
                    subtitle: "새 버전이 있을 때 백그라운드에서 업데이트를 확인합니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $autoUpdate).labelsHidden()
                }
                SettingsRow(
                    "익명 사용 데이터 전송",
                    subtitle: "앱 안정성 향상을 위한 비식별 데이터 전송에 동의합니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $telemetry).labelsHidden()
                }
            }

        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
