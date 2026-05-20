import SwiftUI

struct DataPage: View {
    @State private var iCloudSync: Bool = false
    @State private var autoBackup: Bool = true

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
        }
    }

    private func openDataFolder() {
        if let url = try? SwiftDataStoreLocation.storeURL().deletingLastPathComponent() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
