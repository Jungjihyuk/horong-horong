import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case timer
    case hotkey
    case category
    case stats
    case news
    case agent
    case memo
    case data
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:    return "일반"
        case .appearance: return "외관"
        case .timer:      return "타이머"
        case .hotkey:     return "단축키"
        case .category:   return "카테고리 매핑"
        case .stats:      return "통계"
        case .news:       return "뉴스"
        case .agent:      return "AI Agent"
        case .memo:       return "메모"
        case .data:       return "데이터"
        case .about:      return "정보"
        }
    }

    /// 콘텐츠 헤더 부제.
    var subtitle: String {
        switch self {
        case .general:    return "앱의 기본 동작과 표시 방식을 설정합니다."
        case .appearance: return "화면 모드와 팝오버 테마, 강조 색 등 시각 옵션을 조정합니다."
        case .timer:      return "집중·휴식 사이클의 기본값과 동작 방식을 설정합니다."
        case .hotkey:     return "전역 단축키를 확인하고 변경합니다."
        case .category:   return "카테고리·앱 매핑·자리 비움 임계값을 한 곳에서 관리합니다."
        case .stats:      return "타임라인 표시와 데이터 보관 정책을 설정합니다."
        case .news:       return "관심사 키워드와 뉴스 큐레이션 옵션을 설정합니다."
        case .agent:      return "AI Agent 실험에 사용할 기본값을 설정합니다."
        case .memo:       return "퀵 메모 동작을 설정합니다."
        case .data:       return "백업·복원과 데이터 초기화를 관리합니다."
        case .about:      return "호롱호롱 소개와 버전 정보."
        }
    }

    var systemIcon: String {
        switch self {
        case .general:    return "switch.2"
        case .appearance: return "paintpalette"
        case .timer:      return "timer"
        case .hotkey:     return "keyboard"
        case .category:   return "square.grid.2x2"
        case .stats:      return "chart.bar"
        case .news:       return "newspaper"
        case .agent:      return "bolt.horizontal.circle"
        case .memo:       return "note.text"
        case .data:       return "externaldrive"
        case .about:      return "info.circle"
        }
    }

    /// 사이드바 검색에서 매칭될 *해당 탭 안의 설정 행 제목·키워드* 목록.
    /// 새 행을 페이지에 추가하면 여기에도 같이 더해야 검색에 잡힌다.
    var searchKeywords: [String] {
        switch self {
        case .general:
            return ["로그인 시 자동 시작", "자동 업데이트", "익명 사용 데이터 전송"]
        case .appearance:
            return ["모드", "화면 모드", "라이트", "다크", "시스템",
                    "강조 색", "정보 밀도", "앱 아이콘", "메뉴바 아이콘 애니메이션",
                    "테마", "팝오버 테마", "따뜻한 등불", "편안한 풀", "게임 픽셀"]
        case .timer:
            return ["프리셋", "포모도로", "긴 집중", "커스텀",
                    "프리셋 시간 편집", "집중 완료 시 자동으로 휴식 시작", "종료 알림 사운드",
                    "메뉴바 표시", "라벨 형식", "시간 형식"]
        case .hotkey:
            return ["퀵 메모 띄우기", "호롱호롱 팝오버 열기", "타이머 시작", "일시정지",
                    "설정 창 열기", "단축키"]
        case .category:
            return ["카테고리", "앱 카테고리", "앱 규칙", "자리 비움 감지 임계값",
                    "짝 카테고리", "전환 무시"]
        case .stats:
            return ["타임라인 표시", "시작 시간", "종료 시간", "시간 간격",
                    "앱 사용 시간 추적", "민감 작업 모드", "전체 추적 상태",
                    "휴가 기간", "데이터 보관 기간", "주간 리포트 자동 생성"]
        case .news:
            return ["소스", "YouTube", "Google News", "Hacker News", "RSS", "YOZM IT",
                    "관심 키워드", "관심사", "파이프라인",
                    "자동 수집 스케줄", "요약 에이전트", "일일 리포트 저장 위치", "LLM"]
        case .agent:
            return ["실행 환경", "실험 루트 폴더", "기본 Agent",
                    "계획 일수", "관심사", "터미널 명령 실행 전 확인",
                    "Codex", "Claude", "Gemini"]
        case .memo:
            return ["퀵 메모 단축키", "포커스 잃을 때 자동 저장", "저장 후 자동으로 닫기"]
        case .data:
            return ["데이터 위치", "iCloud 동기화", "자동 백업", "지금 백업하기", "내보내기"]
        case .about:
            return ["호롱호롱", "버전", "GitHub", "사용 가이드", "라이선스",
                    "Apache", "제3자 컴포넌트", "HotKey", "Pretendard", "크레딧"]
        }
    }

    /// label / subtitle / searchKeywords 합쳐서 검색에 쓰이는 텍스트 풀.
    var searchableHaystack: String {
        ([label, subtitle] + searchKeywords).joined(separator: " ")
    }
}

enum SettingsGroup: String, CaseIterable, Identifiable {
    case preferences = "환경설정"
    case features = "기능"
    case advanced = "고급"

    var id: String { rawValue }

    var tabs: [SettingsTab] {
        switch self {
        case .preferences: return [.general, .appearance, .timer, .hotkey]
        case .features:    return [.category, .stats, .news, .agent, .memo]
        case .advanced:    return [.data, .about]
        }
    }
}
