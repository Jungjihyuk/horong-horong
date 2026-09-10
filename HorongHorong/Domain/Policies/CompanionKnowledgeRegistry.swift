import Foundation

/// 앱의 전체 기능 설명, 사용 가이드 및 목적지 연결 정보를 단일 출처로 관리한다.
enum CompanionKnowledgeRegistry {
    /// 사용자 가이드(USER_GUIDE.md)와 앱 기능에 대한 완전한 지식 카탈로그다.
    /// 개발자 전용 AI 실험실은 제외한다.
    static let all: [CompanionKnowledge] = [
        CompanionKnowledge(
            id: .cliSetup,
            keywords: ["cli", "설치", "claude", "codex", "opencode", "uv", "터미널 권한", "외부 cli"],
            summary: "뉴스와 Agent 기능은 외부 AI CLI(claude, codex, opencode)를 터미널에서 호출합니다. uv sync로 의존성을 준비하고 macOS 자동화 권한을 허용해야 합니다.",
            path: "터미널 / 시스템 설정 → 개인정보 보호 및 보안 → 자동화"
        ),
        CompanionKnowledge(
            id: .popover,
            keywords: ["탭", "무슨 탭", "탭 목록", "어떤 탭", "팝오버 탭", "상단 탭", "메뉴바 탭", "메뉴바 아이콘", "메뉴바 팝오버", "팝오버"],
            summary: "메뉴바 아이콘을 누르면 타이머, 기록, 통계, 뉴스, 실험실, 성취 탭이 있는 팝오버가 열립니다.",
            path: "메뉴바 팝오버",
            destinationID: .popoverTimer
        ),
        CompanionKnowledge(
            id: .newsReport,
            keywords: ["뉴스", "리포트", "뉴스 리포트", "리포트 생성", "최근 리포트", "뉴스 탭"],
            summary: "선택한 AI CLI로 YouTube, 구글 뉴스, IT 매체 등의 관심 정보를 수집·요약하여 일일 마크다운 리포트를 생성합니다.",
            path: "메뉴바 팝오버 → 뉴스",
            destinationID: .popoverNews
        ),
        CompanionKnowledge(
            id: .newsSettings,
            keywords: ["뉴스 설정", "뉴스 소스", "관심 키워드", "뉴스 키워드", "리포트 저장 위치", "요약 에이전트"],
            summary: "뉴스 소스(YouTube, Google News, RSS 등)와 관심 키워드 필터, 요약 Provider, 일일 리포트 저장 위치를 설정합니다.",
            path: "설정 → 뉴스 → 소스",
            destinationID: .newsSources
        ),
        CompanionKnowledge(
            id: .newsArchive,
            keywords: ["뉴스 보관함", "리포트 보관함", "월간 타임라인", "뉴스 전체 보기", "리포트 검색"],
            summary: "뉴스 보관함에서는 지난 리포트를 검색하고 읽을 수 있으며, 월간 타임라인으로 주요 사건의 흐름을 종합해 볼 수 있습니다.",
            path: "뉴스 허브 → 보관함",
            destinationID: .hubNews
        ),
        CompanionKnowledge(
            id: .agentLab,
            keywords: ["agent", "에이전트", "실험실", "실험 계획", "오늘 실험", "실험실 탭"],
            summary: "아이디어 파일과 관심사를 바탕으로 며칠짜리 실험 계획을 만들고, 오늘 할 날짜 섹션만 CLI로 실행합니다.",
            path: "메뉴바 팝오버 → 실험실",
            destinationID: .popoverLab
        ),
        CompanionKnowledge(
            id: .agentSettings,
            keywords: ["agent 설정", "실험 루트 폴더", "기본 agent", "계획 일수", "실험실 설정"],
            summary: "실험 루트 폴더(ideas, outputs)와 기본 Agent(Codex, Claude 등), 계획 일수 및 관심사 키워드를 설정합니다.",
            path: "설정 → 실험실",
            destinationID: CompanionDestinationID(rawValue: "settings.lab")
        ),
        CompanionKnowledge(
            id: .timer,
            keywords: ["타이머", "포모도로", "집중 시간", "휴식 시간", "집중 시작", "타이머 탭"],
            summary: "집중과 휴식 사이클을 관리하는 타이머입니다. 포모도로(50/5), 긴 집중(100/10), 커스텀 프리셋을 제공합니다.",
            path: "메뉴바 팝오버 → 타이머",
            destinationID: .popoverTimer
        ),
        CompanionKnowledge(
            id: .timerTask,
            keywords: ["할 일 선택", "작업 선택", "할일 선택", "같은 작업 계속", "할 일 연동"],
            summary: "오늘 시작할 일이나 목표에 연결된 할 일을 골라 집중 세션을 시작하면 작업별 소요 시간이 따로 기록됩니다.",
            path: "메뉴바 팝오버 → 타이머 → 작업 선택",
            destinationID: .popoverTimerSelectTask
        ),
        CompanionKnowledge(
            id: .timerSettings,
            keywords: ["타이머 설정", "프리셋 편집", "종료 알림", "완료 알림", "타이머 알림"],
            summary: "프리셋 시간, 타이머 완료 알림 방식(시스템 알림, 토스트 등), 메뉴바 표시 형식을 설정합니다.",
            path: "설정 → 타이머",
            destinationID: CompanionDestinationID(rawValue: "settings.timer")
        ),
        CompanionKnowledge(
            id: .popoverMemo,
            keywords: ["기록 탭", "메모 탭", "팝오버 메모", "팝오버 기록", "빠른 메모 탭"],
            summary: "메뉴바에서 할 일을 빠르게 확인하고, 새 메모 작성 및 일기·투두의 요약을 볼 수 있는 기록 탭입니다.",
            path: "메뉴바 팝오버 → 기록",
            destinationID: .popoverMemo
        ),
        CompanionKnowledge(
            id: .secondBrainHub,
            keywords: ["기록", "기록 허브", "second brain", "세컨드 브레인", "기록 전체 보기", "기록 창", "메모 창"],
            summary: "Quick Note, Diary, Todo, References 등 생각과 일정을 한곳에서 통합 관리하는 기록 허브입니다.",
            path: "기록 허브",
            destinationID: .hubMemo
        ),
        CompanionKnowledge(
            id: .quickNote,
            keywords: ["퀵 메모", "퀵메모", "quick note", "짧은 메모", "단축키"],
            summary: "짧은 생각이나 쪽지를 빠르게 남기는 메모입니다. 기본 전역 단축키 ⌘⇧N으로 어디서든 열 수 있습니다.",
            path: "기록 허브 → Quick Note",
            destinationID: .hubMemoQuick
        ),
        CompanionKnowledge(
            id: .diary,
            keywords: ["일기", "diary", "감정", "수면 기록", "기상 시각", "취침 시각", "회고"],
            summary: "날짜별 일기와 하루 여러 시점의 감정, 취침·기상 시각을 기록하고 달력과 인사이트에서 회고합니다.",
            path: "기록 허브 → Diary",
            destinationID: .hubMemoDiary
        ),
        CompanionKnowledge(
            id: .todo,
            keywords: ["todo", "할 일", "할일", "일정 입력", "자연어 일정", "일정 관리", "할일 등록"],
            summary: "자연어로 날짜·시각·소요 시간을 간편히 입력하고 일정 배치, 완료, 보관, 목표 연결을 관리합니다.",
            path: "기록 허브 → Todo",
            destinationID: .hubMemoTodo
        ),
        CompanionKnowledge(
            id: .references,
            keywords: ["references", "레퍼런스", "빠른 링크", "스티키 노트", "웹 링크"],
            summary: "자주 찾는 웹 링크를 모아 검색하고 화면 위 스티키 노트로 띄워 둘 수 있습니다. 기본 단축키는 ⌘⇧L입니다.",
            path: "기록 허브 → References",
            destinationID: .hubMemoRefs
        ),
        CompanionKnowledge(
            id: .obsidianVaults,
            keywords: ["knowledge", "works", "옵시디언", "obsidian", "vault", "보관함", "지식", "지식 관리", "노리지", "웍스"],
            summary: "지정한 Obsidian 보관함의 마크다운 문서를 폴더 트리로 탐색하고 읽거나 편집하는 기능입니다. 현재 준비 중입니다.",
            path: "기록 허브 → Knowledge / Works (준비 중)",
            destinationID: nil
        ),
        CompanionKnowledge(
            id: .remindersImport,
            keywords: [
                "미리알림", "미리 알림", "reminders", "리마인더",
                "미리알림 가져오기", "동기화", "미리알림 연동",
            ],
            summary: "선택한 Apple 미리알림 목록의 미완료 항목을 Todo로 가져오고, 변경 사항을 다시 Apple 미리알림에 양방향 동기화합니다.",
            directGuidance: "미리알림 연동 설정을 열어 안내해 드릴게요.",
            path: "설정 → 기록 → 미리알림 가져오기",
            destinationID: .remindersImport
        ),
        CompanionKnowledge(
            id: .stats,
            keywords: ["통계", "사용 시간", "앱 사용량", "통계 탭", "오늘 통계", "주간 통계"],
            summary: "오늘과 이번 주의 앱 사용 시간을 카테고리별로 자동 집계하고 요약해 보여줍니다.",
            path: "메뉴바 팝오버 → 통계",
            destinationID: .popoverStats
        ),
        CompanionKnowledge(
            id: .statsDetail,
            keywords: ["통계 상세", "상세 보기", "타임라인", "통계 편집", "사용량 편집"],
            summary: "일간·주간·월간 통계 창에서 타임라인, 카테고리 분포, 앱별 사용량을 보고, 수동으로 세그먼트를 수정·편집할 수 있습니다.",
            path: "통계 → 상세 보기",
            destinationID: .hubStats
        ),
        CompanionKnowledge(
            id: .categoryMapping,
            keywords: ["카테고리", "카테고리 매핑", "분류 규칙", "앱 분류", "웹사이트 분류", "자리 비움", "미분류"],
            summary: "앱 및 웹사이트별 카테고리 분류 규칙과 미분류 앱 처리 방식, 자리 비움 감지 임계값을 설정합니다.",
            path: "설정 → 카테고리 매핑",
            destinationID: CompanionDestinationID(rawValue: "settings.category")
        ),
        CompanionKnowledge(
            id: .categoryPairs,
            keywords: [
                "짝 카테고리", "짝카테고리", "전환 무시", "카테고리 쌍",
                "짝으로 묶기", "짝", "전환무시", "카테고리 전환",
            ],
            summary: "자주 함께 쓰는 두 카테고리(예: 개발과 문서, 디자인과 기획)를 짝으로 등록하면, 두 작업 사이를 빈번히 오가더라도 주의 분산(맥락 전환)으로 보지 않고 연속된 집중으로 인정하여 주의 신호에서 제외합니다.",
            directGuidance: "짝 카테고리 설정을 열어 안내해 드릴게요.",
            path: "설정 → 카테고리 매핑 → 짝 카테고리 (전환 무시)",
            destinationID: CompanionDestinationID(rawValue: "settings.category.pairs")
        ),
        CompanionKnowledge(
            id: .vacation,
            keywords: ["휴가", "휴가 기간", "휴식 기간", "기록 중단"],
            summary: "휴가 기간으로 지정한 날짜에는 앱 사용 시간 추적이 중단되고, 통계 화면에 휴가로 표시됩니다.",
            path: "설정 → 통계 → 휴가 기간",
            destinationID: CompanionDestinationID(rawValue: "settings.stats.vacation")
        ),
        CompanionKnowledge(
            id: .focusNudge,
            keywords: ["몰입", "몰입도", "집중 넛지", "잔소리", "기준선", "개인화 기준선"],
            summary: "집중 세션의 앱·웹 사용 패턴으로 몰입도를 계산하고, 기준선 아래로 떨어지면 호로롱이가 집중 넛지를 건넵니다.",
            path: "설정 → 몰입",
            destinationID: .focus
        ),
        CompanionKnowledge(
            id: .appearance,
            keywords: [
                "외관", "테마", "팝오버 테마", "화면 모드", "다크 모드",
                "라이트 모드", "다크", "라이트", "등불", "랜턴", "픽셀",
            ],
            summary: "라이트·다크·시스템 화면 모드와 따뜻한 등불·와인 랜턴·게임 픽셀 팝오버 디자인 테마를 설정합니다.",
            path: "설정 → 외관 → 테마",
            destinationID: .theme
        ),
        CompanionKnowledge(
            id: .launchAtLogin,
            keywords: [
                "로그인 시 자동 시작", "자동 시작", "로그인할 때", "부팅할 때", "시작 프로그램",
                "컴퓨터 켜지면", "컴퓨터가 켜졌을 때", "맥이 켜졌을 때", "직접 켜지 않고",
            ],
            summary: "Mac에 로그인하면 호롱호롱을 자동으로 실행하도록 설정합니다.",
            directGuidance: "로그인 시 자동 시작 설정을 열어 안내해 드릴게요.",
            path: "설정 → 일반 → 로그인 시 자동 시작",
            destinationID: .launchAtLogin
        ),
        CompanionKnowledge(
            id: .settingsOverview,
            keywords: ["설정", "설정 창", "설정창", "설정 페이지", "기본값 복원"],
            summary: "앱의 모든 동작을 조정하는 14개 설정 탭을 제공하며, 사이드바 검색 및 페이지별 기본값 복원을 지원합니다.",
            path: "설정",
            destinationID: CompanionDestinationID(rawValue: "settings.general")
        ),
        CompanionKnowledge(
            id: .companionBasics,
            keywords: [
                "루미롱", "컴패니언", "호로롱", "캐릭터", "활동 영역",
                "활동영역", "돌아다니기", "위치 이동", "재우기",
            ],
            summary: "화면 위를 돌아다니는 온디바이스 AI 컴패니언입니다. 마우스로 활동 영역을 그려 지정할 수 있고 드래그로 옮길 수 있습니다.",
            path: "설정 → 루미롱",
            destinationID: .companionBasics
        ),
        CompanionKnowledge(
            id: .companionChat,
            keywords: ["대화", "루미롱 대화", "온디바이스 ai", "말 걸기", "채팅", "ai 대화"],
            summary: "캐릭터를 클릭해 대화창을 엽니다. 모든 추론은 기기 안에서만 실행되며, Apple Intelligence 또는 로컬 모델이 답합니다.",
            path: "설정 → 루미롱 → AI 대화",
            destinationID: CompanionDestinationID(rawValue: "settings.chat")
        ),
        CompanionKnowledge(
            id: .scheduleBriefing,
            keywords: ["일정 브리핑", "오늘 일정", "브리핑", "일정 보기", "오늘 일정 보기"],
            summary: "정해둔 시각에 호로롱이가 찾아와 오늘 할 일을 브리핑해 주며, 캐릭터 우클릭 메뉴에서 언제든 다시 볼 수 있습니다.",
            path: "설정 → 루미롱 → 일정 브리핑",
            destinationID: CompanionDestinationID(rawValue: "settings.briefing")
        ),
        CompanionKnowledge(
            id: .achievement,
            keywords: ["성취 탭", "성취", "목표", "주간 목표", "월간 목표", "여정", "보상", "포인트"],
            summary: "할 일을 주간·월간 목표로 묶어 페르소나·비전과 연결하고, 달성 포인트로 사용자가 직접 만든 보상을 교환합니다.",
            path: "메뉴바 팝오버 → 성취",
            destinationID: .popoverAchievement
        ),
        CompanionKnowledge(
            id: .achievementSettings,
            keywords: ["성취 설정", "목표 설정", "추천 모델", "주간 목표 추천", "월간 목표 추천", "보상 설정", "여정 설정"],
            summary: "목표 추천에 사용할 모델과 주간·월간 목표 자동 생성 규칙, 여정 및 보상 시스템을 설정합니다.",
            path: "설정 → 성취",
            destinationID: .achievement
        ),
        CompanionKnowledge(
            id: .dataBackup,
            keywords: ["데이터", "백업", "복원", "내보내기", "데이터 위치", "저장 위치", "swiftdata"],
            summary: "로컬 SwiftData 저장소 상태를 확인하고 백업·복원·내보내기를 관리합니다. Obsidian 보관함 경로도 여기서 지정합니다.",
            path: "설정 → 데이터",
            destinationID: .data
        ),
    ]

    private static let items = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func knowledge(for id: CompanionKnowledgeID) -> CompanionKnowledge? {
        items[id]
    }

    static func knowledge(forRawID rawID: String) -> CompanionKnowledge? {
        knowledge(for: CompanionKnowledgeID(rawValue: rawID))
    }

    struct ScoredKnowledge {
        let item: CompanionKnowledge
        let maxMatchedKeywordLength: Int
        let matchedKeywordCount: Int
    }

    /// 사용자 질문과 일치하는 지식 항목들을 점수(최장 키워드 길이 및 일치 개수) 순으로 계산한다.
    static func scoredMatches(_ message: String) -> [ScoredKnowledge] {
        let normalized = message.lowercased()

        let scored: [ScoredKnowledge] = all.compactMap { item in
            let matchedKeywords = item.keywords.filter { keyword in
                normalized.contains(keyword.lowercased())
            }
            guard !matchedKeywords.isEmpty else { return nil }
            let maxLength = matchedKeywords.map(\.count).max() ?? 0
            return ScoredKnowledge(
                item: item,
                maxMatchedKeywordLength: maxLength,
                matchedKeywordCount: matchedKeywords.count
            )
        }

        return scored.sorted { lhs, rhs in
            if lhs.maxMatchedKeywordLength != rhs.maxMatchedKeywordLength {
                return lhs.maxMatchedKeywordLength > rhs.maxMatchedKeywordLength
            }
            return lhs.matchedKeywordCount > rhs.matchedKeywordCount
        }
    }

    /// 사용자 질문 메시지와 키워드가 일치하는 지식 항목들을 구체도(가장 긴 일치 키워드 길이 및 일치 개수) 순으로 정렬하여 반환한다.
    static func matches(_ message: String) -> [CompanionKnowledge] {
        scoredMatches(message).map(\.item)
    }

    /// 사용자 질문에 맞는 첫 번째 확정 안내 문구를 반환한다.
    static func directGuidance(for message: String) -> String? {
        matches(message).compactMap(\.directGuidance).first
    }

    /// 사용자 질문에 맞는 목적지 ID를 반환한다.
    ///
    /// 질문에서 가장 구체적으로 일치한 최상위 지식 항목이 목적지를 갖지 않는 경우(예: 준비 중인 기능, 설명 전용 항목),
    /// 질문 문장에 우연히 포함된 덜 구체적인 상위 키워드(예: "기록에서 knowledge가 뭐야"의 "기록")의 목적지로 잘못 이동하지 않도록 nil을 반환한다.
    static func destinationID(for message: String) -> CompanionDestinationID? {
        let scored = scoredMatches(message)
        guard let top = scored.first else { return nil }

        // 최상위 구체도(가장 긴 일치 키워드 길이)를 가진 항목들 중에서만 목적지를 탐색한다.
        for entry in scored {
            guard entry.maxMatchedKeywordLength == top.maxMatchedKeywordLength else { break }
            if let destID = entry.item.destinationID {
                return destID
            }
        }
        return nil
    }

    /// 사용자 질문과 일치하는 명시적 지식 항목이 존재하는지 여부.
    /// 설명이 이미 지식 레지스트리에 정의되어 있다면 목적지가 없더라도 후속 설정 색인 폴백으로 넘어가지 않아야 한다.
    static func hasMatchedKnowledge(for message: String) -> Bool {
        !matches(message).isEmpty
    }
}
