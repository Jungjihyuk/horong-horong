import SwiftUI

struct AppearancePage: View {
    @State private var theme: String = "system"
    @State private var accent: Color = SettingsTheme.accent
    @State private var density: String = "comfortable"
    @State private var appIcon: String = "auto"
    @State private var menubarAnim: Bool = true

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.appearance.label, subtitle: SettingsTab.appearance.subtitle)

            SettingsGroupCard("테마") {
                SettingsRow(
                    "테마",
                    subtitle: "앱 전반의 밝기를 선택합니다.",
                    comingSoon: true
                ) {
                    Picker("", selection: $theme) {
                        Text("시스템").tag("system")
                        Text("라이트").tag("light")
                        Text("다크").tag("dark")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                SettingsRow(
                    "강조 색",
                    subtitle: "버튼·활성 상태·토스트에 사용되는 색입니다.",
                    comingSoon: true
                ) {
                    HStack(spacing: 8) {
                        ForEach(SettingsTheme.accentPalette, id: \.name) { swatch in
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(accent == swatch.color ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                                )
                                .onTapGesture { accent = swatch.color }
                                .help(swatch.name)
                        }
                    }
                }
                SettingsRow(
                    "정보 밀도",
                    subtitle: "목록 항목 간 여백과 폰트 크기를 조절합니다.",
                    comingSoon: true
                ) {
                    Picker("", selection: $density) {
                        Text("촘촘").tag("compact")
                        Text("보통").tag("comfortable")
                        Text("넉넉").tag("comfy")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }

            SettingsGroupCard("아이콘") {
                SettingsRow(
                    "앱 아이콘",
                    subtitle: "Dock 및 앱 전환기에 표시되는 아이콘 스타일.",
                    comingSoon: true
                ) {
                    Picker("", selection: $appIcon) {
                        Text("자동").tag("auto")
                        Text("라이트").tag("light")
                        Text("다크").tag("dark")
                        Text("축제").tag("festival")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                SettingsRow(
                    "메뉴바 아이콘 애니메이션",
                    subtitle: "타이머가 실행 중일 때 호롱불이 깜빡입니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $menubarAnim).labelsHidden()
                }
            }
        }
    }
}
