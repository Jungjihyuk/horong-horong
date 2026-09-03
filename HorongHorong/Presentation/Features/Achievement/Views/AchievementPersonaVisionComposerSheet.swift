import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 페르소나·비전 작성 시트.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementPersonaVisionComposerSheet: View {
    let personas: [AchievementRole]
    let selectedPersonaID: String
    let onClose: () -> Void
    let onSave: (AchievementPersonaVisionDraft) throws -> Void

    @State private var mode = "새 페르소나"
    @State private var selectedPersona = ""
    @State private var personaName = ""
    @State private var personaEmoji = "👤"
    @State private var visionTitle = ""
    @State private var visionEmoji = "🧭"
    @State private var validationMessage: String?
    @FocusState private var isPersonaEmojiFocused: Bool
    @FocusState private var isVisionEmojiFocused: Bool

    private let modes = ["새 페르소나", "기존 페르소나"]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    modePicker

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                    }

                    if mode == "새 페르소나" {
                        fieldLabel("페르소나")
                        HStack(spacing: 8) {
                            emojiChip(emoji: $personaEmoji, isFocused: $isPersonaEmojiFocused, fallback: "👤")
                            TextField("예: AI Engineer", text: $personaName)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                        }
                        quickEmojiRow(selection: $personaEmoji, options: Self.personaQuickEmojis)
                    } else {
                        fieldLabel("페르소나 선택")
                        Menu {
                            ForEach(personas) { persona in
                                Button {
                                    selectedPersona = persona.id
                                } label: {
                                    Text("\(persona.emoji) \(persona.name)")
                                }
                            }
                        } label: {
                            pickerLabel(selectedPersonaLabel)
                        }
                        .buttonStyle(.plain)
                    }

                    fieldLabel("비전")
                    HStack(spacing: 8) {
                        emojiChip(emoji: $visionEmoji, isFocused: $isVisionEmojiFocused, fallback: "🧭")
                        TextField("예: 사람들에게 쓰이는 생산성 제품을 만든다", text: $visionTitle)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
                    }
                    quickEmojiRow(selection: $visionEmoji, options: Self.visionQuickEmojis)
                }
                .padding(14)
            }

            Button {
                save()
            } label: {
                Text("추가")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(PopoverChrome.primaryButtonFill, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.48)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 360, height: 500)
        .background(PopoverChrome.surface)
        .onAppear {
            selectedPersona = selectedPersonaID.isEmpty ? personas.first?.id ?? "" : selectedPersonaID
            if personas.isEmpty {
                mode = "새 페르소나"
            } else if !selectedPersonaID.isEmpty {
                mode = "기존 페르소나"
            }
        }
    }

    private var header: some View {
        HStack {
            Text("페르소나/비전 추가")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
            Spacer()
            Button("닫기") {
                onClose()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(PopoverChrome.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(PopoverChrome.surfaceAlt.opacity(0.7))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PopoverChrome.divider)
                .frame(height: PopoverChrome.borderWidth)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(modes, id: \.self) { item in
                Button {
                    mode = item
                    validationMessage = nil
                } label: {
                    Text(item)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(mode == item ? PopoverChrome.accentInk : PopoverChrome.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(mode == item ? PopoverChrome.accent : Color.clear, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(item == "기존 페르소나" && personas.isEmpty)
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt.opacity(0.84), in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }

    private static let personaQuickEmojis = ["👤", "🧑‍💻", "🎨", "📚", "💪", "✍️"]
    private static let visionQuickEmojis = ["🧭", "🚀", "🌱", "🎯", "⭐", "🔥"]

    /// 미리보기 칸과 입력 칸을 하나로 합친 이모지 칩.
    /// 칩 자체가 입력 필드라 클릭해 바로 타이핑·붙여넣기할 수 있고,
    /// 오른쪽 아래 배지로 시스템 이모지 팔레트를 연다.
    private func emojiChip(emoji: Binding<String>, isFocused: FocusState<Bool>.Binding, fallback: String) -> some View {
        TextField("", text: Binding(
            get: { emoji.wrappedValue },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                emoji.wrappedValue = trimmed.isEmpty ? fallback : String(trimmed.suffix(1))
            }
        ))
        .focused(isFocused)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(.system(size: 19))
        .frame(width: 44, height: 40)
        .background(PopoverChrome.accentSoft, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(9), style: .continuous)
                .stroke(isFocused.wrappedValue ? PopoverChrome.accent : PopoverChrome.border, lineWidth: isFocused.wrappedValue ? 1.6 : PopoverChrome.borderWidth)
        )
        .overlay(alignment: .bottomTrailing) {
            Button {
                isFocused.wrappedValue = true
                DispatchQueue.main.async {
                    NSApplication.shared.orderFrontCharacterPalette(nil)
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(PopoverChrome.accentInk)
                    .frame(width: 17, height: 17)
                    .background(PopoverChrome.accent, in: Circle())
                    .overlay(Circle().stroke(PopoverChrome.surface, lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("이모지 팔레트 열기")
            .offset(x: 6, y: 6)
        }
    }

    private func quickEmojiRow(selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    Text(option)
                        .font(.system(size: 15))
                        .frame(width: 30, height: 28)
                        .background(
                            selection.wrappedValue == option ? PopoverChrome.accentSoft : PopoverChrome.card,
                            in: RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous)
                                .stroke(selection.wrappedValue == option ? PopoverChrome.accent : PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(7), style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var selectedPersonaLabel: String {
        guard let persona = personas.first(where: { $0.id == selectedPersona }) else {
            return "페르소나 선택"
        }
        return "\(persona.emoji) \(persona.name)"
    }

    private var resolvedPersonaName: String {
        if mode == "새 페르소나" {
            return personaName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return personas.first(where: { $0.id == selectedPersona })?.name ?? ""
    }

    private var canSave: Bool {
        !resolvedPersonaName.isEmpty && !visionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        validationMessage = nil
        guard canSave else {
            validationMessage = "페르소나와 비전을 입력해 주세요."
            return
        }
        let personaEmojiValue = mode == "새 페르소나"
            ? personaEmoji
            : personas.first(where: { $0.id == selectedPersona })?.emoji ?? "👤"
        let draft = AchievementPersonaVisionDraft(
            personaName: resolvedPersonaName,
            personaEmoji: personaEmojiValue,
            visionTitle: visionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            visionText: visionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            visionEmoji: visionEmoji
        )
        do {
            try onSave(draft)
        } catch {
            validationMessage = "저장에 실패했습니다: \(error.localizedDescription)"
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(PopoverChrome.inkTertiary)
    }

    private func pickerLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(PopoverChrome.ink)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(PopoverChrome.inkSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous).stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth))
    }
}
