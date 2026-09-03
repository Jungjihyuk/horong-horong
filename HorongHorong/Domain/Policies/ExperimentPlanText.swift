import Foundation

/// 실험 계획 파일의 이름 규칙과 본문 파싱.
///
/// **순수 함수만 둔다** — 파일을 열지도, `Date()` 를 안에서 부르지도 않는다(CLAUDE.md R8).
/// 예전에는 이 규칙이 뷰 파일 안 `private static func` 들이라 검사할 방법이 없었다.
enum ExperimentPlanText {
    /// 계획 파일 이름. 이 접두사로 나중에 파일을 다시 찾으므로 형식이 곧 약속이다.
    static func outputFileName(on date: Date, dayCount: Int) -> String {
        "\(isoDate(date))_experiment_plan_\(dayCount)d.md"
    }

    /// 파일 이름·본문에 쓰는 날짜 표기.
    static func isoDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// 이 파일이 오늘 계획을 담고 있는지. 이름에 오늘 날짜가 있거나 본문에 오늘 날짜 줄이 있으면 맞다.
    static func containsPlan(for today: String, fileName: String, content: @autoclosure () -> String?) -> Bool {
        if fileName.hasPrefix("\(today)_experiment_plan_") { return true }
        return content()?.contains(dateLine(for: today)) ?? false
    }

    /// 오늘 날짜 줄이 속한 `## Day N` 섹션을 통째로 잘라 온다.
    ///
    /// 날짜 줄에서 **위로 올라가며** 머리말을 찾는 이유: 날짜 줄이 섹션 제목 바로 아래가
    /// 아니라 몇 줄 밑에 있을 수 있다(빈 줄·체크박스가 끼어든다).
    /// 다음 `## Day` 를 만나면 거기까지가 오늘 몫이고, 없으면 파일 끝까지다.
    ///
    /// 머리말을 끝내 못 찾으면 **파일 첫 줄부터** 잘라 온다. 계획 파일 형식이 깨졌을 때
    /// 빈 프롬프트를 보내느니 앞부분이라도 보내는 편이 낫다 — 이전 구현과 같은 선택이다.
    static func todaySection(in content: String, today: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard let dateLineIndex = lines.firstIndex(where: { $0.contains(dateLine(for: today)) }) else {
            return nil
        }

        var startIndex = dateLineIndex
        while startIndex > 0 {
            if lines[startIndex].hasPrefix(dayHeadingPrefix) { break }
            startIndex -= 1
        }

        var endIndex = lines.count
        var cursor = startIndex + 1
        while cursor < lines.count {
            if lines[cursor].hasPrefix(dayHeadingPrefix) {
                endIndex = cursor
                break
            }
            cursor += 1
        }

        let section = lines[startIndex..<endIndex]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? nil : section
    }

    /// 터미널이 시작할 폴더. 아이디어·출력이 같은 부모 아래면 그 부모에서 시작해야
    /// Agent 가 양쪽을 상대 경로로 볼 수 있다.
    static func workspaceDirectory(ideaDirectoryPath: String, outputDirectoryPath: String) -> String {
        let ideaParent = parentDirectory(of: ideaDirectoryPath)
        let outputParent = parentDirectory(of: outputDirectoryPath)
        return ideaParent == outputParent ? ideaParent : ideaDirectoryPath
    }

    static func parentDirectory(of path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    private static let dayHeadingPrefix = "## Day "

    private static func dateLine(for today: String) -> String { "> 날짜: \(today)" }

    /// 행마다 새로 만들면 로케일 데이터 로드가 반복된다.
    /// `en_US_POSIX` 인 이유: 사용자 달력 설정이 바뀌어도 파일 이름 형식이 흔들리면 안 된다.
    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
