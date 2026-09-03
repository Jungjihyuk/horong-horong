import Foundation

/// 외부 Agent 에게 보낼 프롬프트를 조립한다.
///
/// **순수 함수만 둔다.** 기준 날짜는 `now` 로 받는다 — 자정 경계에서 날짜 목록이 어떻게
/// 나오는지 검사할 수 있어야 한다(CLAUDE.md R8).
enum AgentPrompt {
    static func plan(
        ideaDirectoryPath: String,
        outputFilePath: String,
        interestKeywords: String,
        agent: AgentKind,
        dayCount: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let dayLines = (0..<dayCount).compactMap { offset -> String? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            return "- \(dayFormatter.string(from: date))"
        }.joined(separator: "\n")

        return """
        다음 요구사항으로 오늘 기준 \(dayCount)일치 실험 계획 markdown 파일을 생성하세요.
        - 기준 시작일은 오늘입니다.
        - 연속된 날짜로 \(dayCount)일 분량을 작성하세요.
        - 포함할 날짜 목록:
        \(dayLines)
        - 아이디어 참고 폴더: \(ideaDirectoryPath)
        - 관심사 키워드: \(interestKeywords)
        - 출력 파일 경로: \(outputFilePath)
        - 반드시 출력 파일에 직접 저장하고, 완료 후 저장한 경로를 한 줄로 출력하세요.
        - 아래 템플릿 형식을 최대한 그대로 따르세요(항목명/순서/마크다운 스타일 유지).
        - 각 Day 섹션 제목은 실험 주제를 짧게 붙이세요.
        - 형식:
          # \(dayCount)일 실험 계획
          생성일: YYYY-MM-DD
          관심사: \(interestKeywords)
          Agent: \(agent.rawValue)

          ## Day 1 (토) - 개인 작업 흐름의 반복 단계 자동화 후보 탐색
          > 날짜: YYYY-MM-DD

          - [ ] 완료
          **목표**: ...
          **작업**: ...
          **산출물**: ...
          **세부 실행 단계**: ...
          **검증 기준**: ...
          **리스크/대응**: ...
          `한줄 회고`:
          `개선점`:

        - Day 2부터 Day N까지도 동일 포맷 반복
        - 요일 표기는 한국어 한 글자(월/화/수/목/금/토/일)로 작성
        - `세부 실행 단계`, `검증 기준`, `리스크/대응`은 기존 형식을 깨지 않는 선에서 상세화를 위해 추가한 필수 항목입니다.
        """
    }

    static func todayExperiment(
        interestKeywords: String,
        today: String,
        todaySection: String
    ) -> String {
        """
        아래는 오늘 실험 계획입니다.
        이 계획을 바로 실행 시작할 수 있도록:
        1) 지금 바로 할 첫 액션 3개
        2) 실행 체크리스트
        3) 결과 기록 방식(한줄 회고/개선점 작성 가이드)
        를 제시하고 진행하세요.

        관심사 키워드: \(interestKeywords)
        오늘 날짜: \(today)

        [오늘 계획 섹션]
        \(todaySection)
        """
    }

    /// 프롬프트 안의 날짜 목록 표기. 사용자 로케일이 바뀌어도 형식이 흔들리면 안 된다.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEE)"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
