import Foundation

/// 안내 가능한 목적지를 한곳에서 선언하고, 외부에서 받은 ID를 실행 전에 검증한다.
enum CompanionDestinationRegistry {
    /// 사용자에게 안내할 수 있는 설정 탭과 카드의 완전한 카탈로그다.
    /// 개발자 전용 AI 실험실은 의도적으로 넣지 않는다.
    static let all: [CompanionDestination] = [
        settings("settings.general", section: "general"),
        settings("settings.general.behavior", section: "general", target: "card:동작"),
        settings(.launchAtLogin, section: "general", target: "settings.launchAtLogin"),

        settings("settings.appearance", section: "appearance"),
        settings(.appearanceMode, section: "appearance", target: "settings.appearanceMode"),
        settings(.theme, section: "appearance", target: "settings.theme"),
        settings("settings.appIcon", section: "appearance", target: "settings.appIcon"),

        settings("settings.timer", section: "timer"),
        settings("settings.timer.presets", section: "timer", target: "card:프리셋"),
        settings("settings.timer.presetDurations", section: "timer", target: "card:프리셋 시간 편집"),
        settings("settings.timer.notifications", section: "timer", target: "card:알림"),
        settings("settings.timer.behavior", section: "timer", target: "card:동작"),
        settings("settings.timer.menuBar", section: "timer", target: "card:메뉴바 표시"),

        settings("settings.hotkey", section: "hotkey"),
        settings(.globalHotkeys, section: "hotkey", target: "card:전역"),
        settings("settings.hotkey.settings", section: "hotkey", target: "card:설정"),

        settings("settings.category", section: "category"),
        settings("settings.category.categories", section: "category", target: "card:카테고리"),
        settings("settings.category.apps", section: "category", target: "card:앱 → 카테고리"),
        settings("settings.category.websites", section: "category", target: "card:웹사이트 → 카테고리"),
        settings("settings.category.idleThreshold", section: "category", target: "card:자리 비움 감지 임계값"),
        settings("settings.category.pairs", section: "category", target: "card:짝 카테고리 (전환 무시)"),

        settings("settings.stats", section: "stats"),
        settings("settings.stats.timeline", section: "stats", target: "card:타임라인 표시"),
        settings("settings.stats.retention", section: "stats", target: "card:보관"),
        settings("settings.stats.tracking", section: "stats", target: "card:추적"),
        settings("settings.stats.vacation", section: "stats", target: "card:휴가 기간"),

        settings(.focus, section: "focus"),
        settings("settings.focus.nudge", section: "focus", target: "card:집중 넛지"),
        settings("settings.focus.personalization", section: "focus", target: "card:개인화"),
        settings("settings.focus.reviewBaseline", section: "focus", target: "card:개인 회고 기반"),
        settings("settings.focus.ruleBaseline", section: "focus", target: "card:규칙 기반 기준"),
        settings("settings.focus.repetition", section: "focus", target: "card:반복 방식"),
        settings("settings.focus.message", section: "focus", target: "card:해줄 말"),

        settings(.achievement, section: "achievement"),
        settings("settings.achievement.model", section: "achievement", target: "card:추천 모델"),
        settings("settings.achievement.weekly", section: "achievement", target: "card:주간 목표 추천"),
        settings("settings.achievement.monthly", section: "achievement", target: "card:월간 목표 추천"),
        settings("settings.achievement.journey", section: "achievement", target: "card:여정"),
        settings("settings.achievement.rewards", section: "achievement", target: "card:보상"),
        settings("settings.achievement.application", section: "achievement", target: "card:적용 방식"),

        settings("settings.news", section: "news"),
        settings(.newsSources, section: "news", target: "card:소스"),
        settings("settings.news.interests", section: "news", target: "card:관심 키워드"),
        settings("settings.news.pipeline", section: "news", target: "card:파이프라인"),

        settings("settings.lab", section: "lab"),
        settings("settings.lab.environment", section: "lab", target: "card:실행 환경"),
        settings("settings.lab.safety", section: "lab", target: "card:안전장치"),
        settings("settings.lab.interests", section: "lab", target: "card:관심사"),

        settings("settings.companion", section: "companion"),
        settings(.companionBasics, section: "companion", target: "settings.companionBasics"),
        settings("settings.activity", section: "companion", target: "settings.activity"),
        settings("settings.briefing", section: "companion", target: "settings.briefing"),
        settings("settings.profile", section: "companion", target: "settings.profile"),
        settings("settings.chat", section: "companion", target: "settings.chat"),
        settings("settings.companion.comingSoon", section: "companion", target: "card:준비 중"),

        settings("settings.secondBrain", section: "secondBrain"),
        settings("settings.memoShortcut", section: "secondBrain", target: "settings.memoShortcut"),
        settings("settings.secondBrain.quickLink", section: "secondBrain", target: "card:빠른 링크"),
        settings("settings.secondBrain.todoSchedule", section: "secondBrain", target: "card:Todo 일정"),
        settings("settings.secondBrain.diarySleep", section: "secondBrain", target: "card:일기 수면 기록"),
        settings(.remindersImport, section: "secondBrain", target: "card:미리알림 가져오기"),

        settings(.data, section: "data"),
        settings("settings.data.storage", section: "data", target: "card:저장소"),
        settings("settings.data.backup", section: "data", target: "card:백업"),
        settings("settings.data.telemetry", section: "data", target: "card:개선 데이터"),

        settings("settings.about", section: "about"),
        settings("settings.about.credits", section: "about", target: "card:크레딧"),

        // 팝오버 탭 및 내부 요소
        popover(.popoverTimer, section: "timer"),
        popover(.popoverTimerPreset, section: "timer", target: "timer.preset"),
        popover(.popoverTimerSelectTask, section: "timer", target: "timer.selectTask"),
        popover(.popoverTimerStartFocus, section: "timer", target: "timer.startFocus"),

        popover(.popoverMemo, section: "memo"),
        popover(.popoverMemoNew, section: "memo", target: "memo.new"),

        popover(.popoverStats, section: "stats"),
        popover(.popoverStatsDetail, section: "stats", target: "stats.detail"),

        popover(.popoverNews, section: "news"),
        popover(.popoverLab, section: "lab"),
        popover(.popoverAchievement, section: "achievement"),

        // 허브 창 및 내부 요소
        hub(.hubMemo, section: "memo"),
        hub(.hubMemoQuick, section: "memo", target: "quick"),
        hub(.hubMemoDiary, section: "memo", target: "diary"),
        hub(.hubMemoTodo, section: "memo", target: "todo"),
        hub(.hubMemoRefs, section: "memo", target: "refs"),

        hub(.hubNews, section: "news"),

        hub(.hubStats, section: "stats"),
        hub(.hubStatsFocusToggle, section: "stats", target: "stats.focusToggle"),

        hub(.hubAchievement, section: "achievement"),
    ]

    private static let destinations = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func destination(for id: CompanionDestinationID) -> CompanionDestination? {
        destinations[id]
    }

    /// LLM 등 경계 밖에서 온 문자열은 등록된 값일 때만 목적지로 승격한다.
    static func destination(forRawID rawID: String) -> CompanionDestination? {
        destination(for: CompanionDestinationID(rawValue: rawID))
    }

    private static func settings(
        _ id: CompanionDestinationID,
        section: String,
        target: String? = nil
    ) -> CompanionDestination {
        CompanionDestination(id: id, surface: .settings, sectionID: section, targetID: target)
    }

    private static func settings(
        _ rawID: String,
        section: String,
        target: String? = nil
    ) -> CompanionDestination {
        settings(CompanionDestinationID(rawValue: rawID), section: section, target: target)
    }

    private static func popover(
        _ id: CompanionDestinationID,
        section: String,
        target: String? = nil
    ) -> CompanionDestination {
        CompanionDestination(id: id, surface: .popover, sectionID: section, targetID: target)
    }

    private static func popover(
        _ rawID: String,
        section: String,
        target: String? = nil
    ) -> CompanionDestination {
        popover(CompanionDestinationID(rawValue: rawID), section: section, target: target)
    }

    private static func hub(
        _ id: CompanionDestinationID,
        section: String,
        target: String? = nil
    ) -> CompanionDestination {
        CompanionDestination(id: id, surface: .hub, sectionID: section, targetID: target)
    }

    private static func hub(
        _ rawID: String,
        section: String,
        target: String? = nil
    ) -> CompanionDestination {
        hub(CompanionDestinationID(rawValue: rawID), section: section, target: target)
    }
}
