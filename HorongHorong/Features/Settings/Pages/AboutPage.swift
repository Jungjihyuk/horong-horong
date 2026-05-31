import SwiftUI

struct AboutPage: View {
    #if DIRECT_DISTRIBUTION
    @ObservedObject private var updater = AppUpdateManager.shared
    #endif

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.about.label, subtitle: SettingsTab.about.subtitle)

            heroCard

            SettingsGroupCard("크레딧") {
                SettingsRow(
                    "제작",
                    subtitle: "정지혁 · Made with a small flame."
                ) {
                    Text("@Jungjihyuk")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                SettingsRow(
                    "라이선스",
                    subtitle: "소스 코드 — Apache License 2.0"
                ) {
                    Button("전체 보기") {
                        if let url = URL(string: "https://www.apache.org/licenses/LICENSE-2.0") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                SettingsRow(
                    "제3자 컴포넌트",
                    subtitle: "HotKey (MIT, © Sam Soffes), Pretendard (OFL)"
                ) {
                    Button("NOTICE") {
                        if let url = Bundle.main.url(forResource: "NOTICE", withExtension: nil) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        #if DIRECT_DISTRIBUTION
        .onAppear {
            updater.refreshState()
        }
        #endif
    }

    private var heroCard: some View {
        return HStack(alignment: .top, spacing: 16) {
            Image("HorongLogo")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text("호롱호롱")
                    .font(.title2.bold())
                Text(currentVersionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("호롱은 작은 불빛을 담아 꺼지지 않게 지키는 그릇입니다. 그 불빛은 희망이자 열망이며, 몰입과 목표를 상징합니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                HStack(spacing: 8) {
                    Button {
                        if let url = URL(string: "https://github.com/Jungjihyuk/horong-horong") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                    .controlSize(.small)
                    Button {
                        if let url = URL(string: "https://github.com/Jungjihyuk/horong-horong/blob/main/USER_GUIDE.md") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("사용 가이드", systemImage: "book")
                    }
                    .controlSize(.small)
                }
                .padding(.top, 6)

                #if DIRECT_DISTRIBUTION
                HStack(spacing: 8) {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("업데이트 확인", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.small)
                    .disabled(!updater.canCheckForUpdates)

                    Text(updater.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
                #else
                Text("업데이트는 Mac App Store에서 제공됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                #endif
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SettingsTheme.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SettingsTheme.accent.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var currentVersionText: String {
        #if DIRECT_DISTRIBUTION
        updater.currentVersionText
        #else
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(marketing) (\(build))"
        #endif
    }
}
