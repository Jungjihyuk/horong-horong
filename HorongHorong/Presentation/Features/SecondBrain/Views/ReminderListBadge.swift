import SwiftUI

/// 미리알림 목록을 나타내는 태그.
///
/// 할 일 카드와 팝오버 기록 탭이 **같은 모양**을 써야 «같은 것» 으로 읽힌다.
/// 값만 받아 `Equatable` 이므로 목록이 길어도 바뀐 줄만 다시 그린다(R3).
struct ReminderListBadge: View, Equatable {
    let title: String
    let swatch: ReminderListSwatch
    /// 미리알림 앱과 실제로 연동된 할 일에만 종을 붙인다.
    let isLinked: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(swatch.dot)
                .frame(width: 6, height: 6)
            if isLinked {
                Image(systemName: "bell")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
        .foregroundStyle(swatch.ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(swatch.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
