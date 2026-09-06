import Foundation

/// 일기에 기록하는 세부 감정. `DiaryEntry.moodRaw` 로 저장된다.
/// 예전 5단계 값은 기존 일기를 잃지 않도록 남겨 두고, `allCases`에는 새 감정만 노출한다.
enum DiaryMood: String, Identifiable, Sendable {
    // 이전 버전 호환 값
    case great = "최고"
    case good = "좋음"
    case ok = "보통"
    case low = "별로"
    case bad = "나쁨"

    // 1. 밝고 벅차요
    case moved = "감동"
    case happy = "행복"
    case grateful = "감사"
    case joy = "기쁨"
    case hope = "희망"
    case excited = "설렘"
    // 2. 자신 있고 힘이 났어요
    case passion = "열정"
    case achievement = "성취감"
    case confidence = "자신감"
    case pride = "자부심"
    case motivation = "의욕"
    case interest = "흥미"
    // 3. 편안하고 마음이 놓였어요
    case stable = "안정"
    case relieved = "안도"
    case comfort = "편안함"
    case peaceful = "평온함"
    case satisfaction = "만족감"
    case supported = "든든함"
    // 4. 마음이 가라앉아요
    case discouraged = "낙심"
    case disappointed = "실망감"
    case lonely = "외로움"
    case sad = "슬픔"
    case worthless = "무가치함"
    case hurt = "서운함"
    case sorrow = "안타까움"
    // 5. 걱정되고 복잡해요
    case anxious = "불안"
    case rushed = "조급함"
    case sensitive = "예민"
    case fear = "공포"
    case pressured = "압박감"
    case confused = "혼란"
    case cluttered = "어수선함"
    case inferior = "열등감"
    case uncomfortable = "불편함"
    case shabby = "초라함"
    case withdrawn = "위축됨"
    // 6. 화나고 답답해요
    case irritated = "짜증"
    case angry = "분노"
    case frustrated = "답답함"
    case resentful = "억울함"
    // 7. 기운이 없고 지쳤어요
    case helpless = "무기력"
    case exhausted = "피곤함"
    case drained = "지침"
    case unmotivated = "의욕 없음"
    case burnout = "번아웃"

    var id: String { rawValue }

    static let allCases: [DiaryMood] = [
        .moved, .happy, .grateful, .joy, .hope, .excited,
        .passion, .achievement, .confidence, .pride, .motivation, .interest,
        .stable, .relieved, .comfort, .peaceful, .satisfaction, .supported,
        .discouraged, .disappointed, .lonely, .sad, .worthless, .hurt, .sorrow,
        .anxious, .rushed, .sensitive, .fear, .pressured, .confused, .cluttered,
        .inferior, .uncomfortable, .shabby, .withdrawn,
        .irritated, .angry, .frustrated, .resentful,
        .helpless, .exhausted, .drained, .unmotivated, .burnout
    ]

    var group: DiaryMoodGroup {
        switch self {
        case .great, .good, .ok, .moved, .happy, .grateful, .joy, .hope, .excited: return .bright
        case .passion, .achievement, .confidence, .pride, .motivation, .interest: return .confident
        case .stable, .relieved, .comfort, .peaceful, .satisfaction, .supported: return .calm
        case .low, .bad, .discouraged, .disappointed, .lonely, .sad, .worthless, .hurt, .sorrow: return .low
        case .anxious, .rushed, .sensitive, .fear, .pressured, .confused, .cluttered, .inferior, .uncomfortable, .shabby, .withdrawn: return .worried
        case .irritated, .angry, .frustrated, .resentful: return .angry
        case .helpless, .exhausted, .drained, .unmotivated, .burnout: return .tired
        }
    }

    var emoji: String {
        switch self {
        case .great: return "😄"; case .good: return "🙂"; case .ok: return "😐"; case .low: return "😕"; case .bad: return "😞"
        case .moved: return "🥹"; case .happy: return "😆"; case .grateful: return "🙏"; case .joy: return "😊"; case .hope: return "🌅"; case .excited: return "🥰"
        case .passion: return "🏃🏻"; case .achievement: return "💪🏻"; case .confidence: return "💪"; case .pride: return "😤"; case .motivation: return "🔥"; case .interest: return "👀"
        case .stable: return "🍃"; case .relieved: return "😮‍💨"; case .comfort: return "😌"; case .peaceful: return "🧘"; case .satisfaction: return "🙂"; case .supported: return "🫶"
        case .discouraged: return "😞"; case .disappointed: return "😔"; case .lonely: return "🌧️"; case .sad: return "😭"; case .worthless: return "🧸"; case .hurt: return "🥺"; case .sorrow: return "😢"
        case .anxious: return "😨"; case .rushed: return "⏳"; case .sensitive: return "😬"; case .fear: return "😱"; case .pressured: return "🫣"; case .confused: return "😵‍💫"; case .cluttered: return "🌫️"; case .inferior: return "😔"; case .uncomfortable: return "😟"; case .shabby: return "😣"; case .withdrawn: return "🫥"
        case .irritated: return "😫"; case .angry: return "😡"; case .frustrated: return "😮‍💨"; case .resentful: return "😤"
        case .helpless: return "🤐"; case .exhausted: return "😴"; case .drained: return "🫠"; case .unmotivated: return "😪"; case .burnout: return "🪫"
        }
    }
}

/// 세부 감정을 고르기 전에 선택하는 감정 영역.
enum DiaryMoodGroup: String, CaseIterable, Identifiable, Sendable {
    case bright, confident, calm, low, worried, angry, tired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bright: return "밝고 벅차요"
        case .confident: return "자신 있고 힘이 났어요"
        case .calm: return "편안하고 마음이 놓였어요"
        case .low: return "마음이 가라앉아요"
        case .worried: return "걱정되고 복잡해요"
        case .angry: return "화나고 답답해요"
        case .tired: return "기운이 없고 지쳤어요"
        }
    }

    /// 칩 한 칸에 들어가는 짧은 이름. `title` 은 «밝고 벅차요» 처럼 문장이라 칩에 넣으면 줄이 접힌다.
    var shortTitle: String {
        switch self {
        case .bright: return "밝음"
        case .confident: return "자신감"
        case .calm: return "편안"
        case .low: return "가라앉음"
        case .worried: return "걱정"
        case .angry: return "화남"
        case .tired: return "지침"
        }
    }

    var subtitle: String {
        switch self {
        case .bright: return "기쁘거나 의욕이 올라오는 느낌"
        case .confident: return "무언가 해낼 수 있고 에너지가 솟는 느낌"
        case .calm: return "긴장이 풀리고 마음이 잔잔한 느낌"
        case .low: return "마음이 상하거나 처지는 느낌"
        case .worried: return "긴장되거나 머릿속이 정리되지 않는 느낌"
        case .angry: return "무언가 거슬리거나 부당해서 감정이 올라오는 느낌"
        case .tired: return "몸이나 마음의 에너지가 떨어진 느낌"
        }
    }

    var emoji: String {
        switch self { case .bright: return "☀️"; case .confident: return "🚀"; case .calm: return "🌿"; case .low: return "🌧️"; case .worried: return "🌪️"; case .angry: return "🔥"; case .tired: return "🪫" }
    }

    var moods: [DiaryMood] { DiaryMood.allCases.filter { $0.group == self } }
}
