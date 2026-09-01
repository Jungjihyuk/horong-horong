import SwiftUI
import AppKit

struct DataPage: View {
    @State private var iCloudSync: Bool = false
    @State private var autoBackup: Bool = true
    @AppStorage(Constants.AppStorageKey.anonymousTelemetryEnabled)
    private var telemetryEnabled: Bool = false
    @AppStorage(Constants.AppStorageKey.secondBrainVaultPath)
    private var vaultPath: String = Constants.defaultSecondBrainVaultPath

    private var telemetryConfigured: Bool {
        TelemetryClient.shared.isConfigured
    }

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.data.label, subtitle: SettingsTab.data.subtitle)

            SettingsGroupCard("저장소") {
                SettingsRow(
                    "데이터 위치",
                    subtitle: "~/Library/Application Support/HorongHorong"
                ) {
                    Button("Finder에서 열기") {
                        openDataFolder()
                    }
                    .controlSize(.small)
                }
                SettingsRow(
                    "Second Brain vault",
                    subtitle: vaultPath
                ) {
                    Button("폴더 선택") {
                        chooseVault()
                    }
                    .controlSize(.small)
                }
            }

            SettingsGroupCard("백업") {
                SettingsRow(
                    "iCloud 동기화",
                    subtitle: "여러 Mac에서 카테고리·기록을 공유합니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $iCloudSync).labelsHidden()
                }
                SettingsRow(
                    "자동 백업",
                    subtitle: "매주 SwiftData 스토어를 압축해 저장합니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $autoBackup).labelsHidden()
                }
                SettingsRow(
                    "지금 백업하기",
                    subtitle: "SwiftData 스토어를 ZIP 으로 내보냅니다.",
                    comingSoon: true
                ) {
                    Button("내보내기") {}
                        .controlSize(.small)
                }
            }

            SettingsGroupCard("개선 데이터") {
                SettingsRow(
                    "익명 개선 데이터 보내기",
                    subtitle: telemetryConfigured
                    ? "현재 익명 설치 ID, 앱/OS 버전, 동의 상태만 전송합니다. 앱 이름, 번들 ID, 작업 기록, 포모도로 회고 내용은 보내지 않습니다."
                    : "Supabase 연결값이 없어 전송할 수 없습니다."
                ) {
                    Toggle("", isOn: $telemetryEnabled)
                        .labelsHidden()
                        .disabled(!telemetryConfigured)
                        .onChange(of: telemetryEnabled) { _, newValue in
                            TelemetryConsentStore.setEnabled(newValue)
                            Task {
                                await TelemetryClient.shared.recordConsent(newValue ? .enabled : .disabled)
                            }
                        }
                }
            }
        }
    }

    private func openDataFolder() {
        if let url = try? SwiftDataStoreLocation.applicationDirectoryURL() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: vaultPath)
        panel.prompt = "선택"
        if panel.runModal() == .OK, let url = panel.url {
            vaultPath = url.path
        }
    }
}
