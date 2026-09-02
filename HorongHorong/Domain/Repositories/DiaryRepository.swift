import Foundation

/// 일기를 읽고 쓴다. 구현은 `Data/Repositories/` 에 있다.
///
/// **쓰기는 모두 «그날 한 장» 을 만들거나 고친다(upsert).** 화면이 «없으면 만들고 있으면
/// 고쳐라» 를 스스로 하면 그 사이에 같은 날짜가 두 장 생길 틈이 열린다 —
/// `DiaryEntry.day` 에는 유일 제약이 없다(`#Unique` 는 macOS 15+).
@MainActor
protocol DiaryRepository {
    /// `date` 가 속한 달의 기록만. 달력이 그 달만 그리므로 전량을 가져올 이유가 없다.
    func entries(inMonthOf date: Date) throws -> [DiaryDay]

    func entry(on day: Date) throws -> DiaryDay?

    @discardableResult func setBody(on day: Date, body: String) throws -> DiaryDay
    @discardableResult func setMood(on day: Date, mood: DiaryMood?) throws -> DiaryDay
    @discardableResult func setStress(on day: Date, stress: Int?) throws -> DiaryDay

    /// 수면 시간과 그 출처를 함께 정한다. 출처를 따로 두면 «직접 입력» 을 건강 앱 값이
    /// 덮어쓰는 사고가 난다 — 둘은 항상 같이 바뀐다.
    @discardableResult
    func setSleep(on day: Date, hours: Double, source: DiarySleepSource) throws -> DiaryDay
}
