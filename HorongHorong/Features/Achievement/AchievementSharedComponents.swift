import AppKit
import HorongAI
import HorongAIMLX
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/*
 성취 화면 여러 곳이 함께 쓰는 조각.
 
  두 곳 이상이 쓰게 된 것만 여기 둔다. 성취 밖에서도 쓰이게 되면
  `Presentation/DesignSystem` 으로 올린다.

 원래 `AchievementViews.swift`(9,854줄) 한 파일에 있었다. 2026-09-03 분할.
 */

struct AchievementSegmentedPicker<Value: CaseIterable & Identifiable & RawRepresentable>: View where Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    @Binding var selection: Value
    let values: Value.AllCases

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values) { value in
                Button {
                    selection = value
                } label: {
                    Text(value.rawValue)
                        .font(.system(size: 12.5, weight: selection.rawValue == value.rawValue ? .bold : .medium, design: .rounded))
                        .foregroundStyle(selection.rawValue == value.rawValue ? PopoverChrome.selectionInk : PopoverChrome.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selection.rawValue == value.rawValue ? PopoverChrome.selectionFill : Color.clear, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(8), style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(PopoverChrome.surfaceAlt, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(12), style: .continuous))
    }
}

struct AchievementMetricCard: View {
    let label: String
    let value: String
    let icon: String
    var valueSize: CGFloat = 18
    var isHighlighted = false
    var infoDetails: [String] = []
    var onTap: (() -> Void)? = nil

    @State private var showsInfo = false
    @State private var isInfoHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isHighlighted ? PopoverChrome.accentInk : PopoverChrome.accent)
                .frame(width: 30, height: 30)
                .background(isHighlighted ? PopoverChrome.accent.opacity(0.92) : PopoverChrome.accentSoft.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isHighlighted ? PopoverChrome.inkSecondary : PopoverChrome.inkTertiary)
                Text(value)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if !infoDetails.isEmpty {
                infoButton
            }
        }
        .padding(14)
        .contentShape(RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous))
        .background(isHighlighted ? PopoverChrome.accentSoft.opacity(0.95) : PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous)
                .stroke(isHighlighted ? PopoverChrome.accent.opacity(0.36) : PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
        )
        .onTapGesture {
            onTap?()
        }
    }

    private var infoButton: some View {
        Button {
            showsInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(isInfoHovering || showsInfo ? PopoverChrome.accent : PopoverChrome.inkTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("\(label) 선정 기준 보기")
        .onHover { isInfoHovering = $0 }
        .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("\(label) 선정 기준")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PopoverChrome.inkTertiary)

                ForEach(Array(infoDetails.enumerated()), id: \.offset) { _, detail in
                    HStack(alignment: .top, spacing: 6) {
                        Text("·")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(PopoverChrome.inkTertiary)
                        Text(detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(PopoverChrome.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .frame(width: 264, alignment: .leading)
            .background(PopoverChrome.card)
        }
    }
}

/// 타임라인 부제목 줄이 곧 정렬 메뉴다. 헤더 오른쪽 필터가 «무엇을 볼지»를 정하고,
/// 이 줄이 «어떤 순서로 볼지»를 정한다.

extension View {
    func achievementDetailCard() -> some View {
        self
            .padding(14)
            .background(PopoverChrome.card, in: RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PopoverChrome.radius(14), style: .continuous)
                    .stroke(PopoverChrome.border, lineWidth: PopoverChrome.borderWidth)
            )
    }
}
