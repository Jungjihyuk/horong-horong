import SwiftUI

extension DiaryMoodGroup {
    /// 그래프에서 이 감정 영역을 가리키는 색.
    ///
    /// 테마 토큰을 쓰지 않는 이유: 일곱 영역이 서로 구별돼야 하는데 `PopoverChrome` 의 강조색은
    /// 테마마다 하나뿐이라 전부 같은 색이 된다.
    var chartColor: Color {
        switch self {
        case .bright: return Color(red: 0.92, green: 0.62, blue: 0.18)
        case .confident: return Color(red: 0.95, green: 0.40, blue: 0.20)
        case .calm: return Color(red: 0.36, green: 0.64, blue: 0.42)
        case .low: return Color(red: 0.36, green: 0.52, blue: 0.76)
        case .worried: return Color(red: 0.50, green: 0.42, blue: 0.72)
        case .angry: return Color(red: 0.82, green: 0.28, blue: 0.28)
        case .tired: return Color(red: 0.45, green: 0.46, blue: 0.52)
        }
    }
}

extension DiaryMoodSlot {
    /// 타임라인에서 이 칸을 가리키는 색.
    ///
    /// **감정 색과 역할이 겹치지 않는다.** 여기서 색은 «언제»(오전/오후)만 말하고,
    /// «무엇»은 점 위 이모지가 말한다. 둘 다 색으로 표현하면 서로를 가린다.
    var chartHue: Color {
        switch self {
        case .morning: return Color(red: 0.93, green: 0.66, blue: 0.24)
        case .afternoon: return Color(red: 0.38, green: 0.45, blue: 0.78)
        case .wholeDay: return Color(red: 0.45, green: 0.58, blue: 0.55)
        }
    }
}
