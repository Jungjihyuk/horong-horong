import SwiftUI

struct HotkeyPage: View {
    @State private var store = HotkeyStore.shared

    private var quickMemoBinding: Binding<HotkeyCombo> {
        Binding(get: { store.quickMemo }, set: { store.quickMemo = $0 })
    }

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.hotkey.label, subtitle: SettingsTab.hotkey.subtitle)

            Text("단축키 박스를 클릭하면 새 조합을 입력할 수 있어요. ⌃ / ⌥ / ⌘ 중 하나 이상이 함께 눌린 조합만 인정하고, Esc 로 취소합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .padding(.top, -10)

            SettingsGroupCard("전역") {
                SettingsRow(
                    "퀵 메모 띄우기",
                    subtitle: "어디서든 플로팅 메모 패널을 호출합니다. 클릭해서 단축키를 변경할 수 있습니다."
                ) {
                    HotkeyRecorderField(combo: quickMemoBinding)
                    if store.quickMemo != .defaultQuickMemo {
                        Button {
                            store.resetQuickMemoToDefault()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("기본값(⌘⇧N) 으로 되돌리기")
                    }
                }
                SettingsRow(
                    "호롱호롱 팝오버 열기",
                    subtitle: "메뉴바 팝오버를 호출합니다.",
                    comingSoon: true
                ) {
                    HotkeyField(keys: ["⌃", "⌥", "Space"])
                }
                SettingsRow(
                    "타이머 시작 / 일시정지",
                    comingSoon: true
                ) {
                    HotkeyField(keys: ["⌃", "⌥", "P"])
                }
            }

            SettingsGroupCard("설정") {
                SettingsRow(
                    "설정 창 열기",
                    subtitle: "macOS 기본 단축키. 메뉴바에서 호롱호롱 → Settings…"
                ) {
                    HotkeyField(keys: ["⌘", ","])
                }
            }

        }
    }
}
