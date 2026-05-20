import SwiftUI

struct MemoPage: View {
    @State private var store = HotkeyStore.shared
    @State private var autoClose: Bool = true
    @State private var autoSave: Bool = true

    private var quickMemoBinding: Binding<HotkeyCombo> {
        Binding(get: { store.quickMemo }, set: { store.quickMemo = $0 })
    }

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.memo.label, subtitle: SettingsTab.memo.subtitle)

            SettingsGroupCard("퀵 메모") {
                SettingsRow(
                    "퀵 메모 단축키",
                    subtitle: "단축키로 어디서든 플로팅 메모 패널을 호출해 빠르게 메모할 수 있어요. 같은 단축키를 다시 누르면 패널이 닫힙니다. 박스를 클릭해 단축키를 바꿀 수 있습니다."
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
                    "포커스 잃을 때 자동 저장",
                    subtitle: "패널이 닫힐 때 내용이 비어있지 않으면 저장합니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $autoSave).labelsHidden()
                }
                SettingsRow(
                    "저장 후 자동으로 닫기",
                    subtitle: "Enter ↵ 로 저장 시 패널을 자동으로 닫습니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $autoClose).labelsHidden()
                }
            }
        }
    }
}
