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

    /// `end` 는 포함하지 않는 범위 조회. 달력 밖의 최근 기록과 인사이트 기간에 사용한다.
    func entries(from start: Date, to end: Date) throws -> [DiaryDay]

    func entry(on day: Date) throws -> DiaryDay?

    @discardableResult func setBody(on day: Date, body: String) throws -> DiaryDay

    /// 감정은 **칸(오전·오후·하루)마다 따로** 적는다. 하루에 한 칸뿐이면 오전에 기뻤고
    /// 오후에 화난 날을 적을 방법이 없어, 고르다 말고 아무것도 안 남기게 된다.
    ///
    /// 감정을 지우면 그 칸의 원인·강도도 함께 지운다 — 무엇이었는지 모르는 채 남은
    /// «강도 4 · 일 때문» 은 읽을 수 없는 기록이다.
    @discardableResult func setMood(on day: Date, slot: DiaryMoodSlot, mood: DiaryMood?) throws -> DiaryDay
    @discardableResult func setCause(on day: Date, slot: DiaryMoodSlot, cause: DiaryCause?) throws -> DiaryDay
    @discardableResult func setIntensity(on day: Date, slot: DiaryMoodSlot, intensity: Int?) throws -> DiaryDay

    @discardableResult func setStress(on day: Date, stress: Int?) throws -> DiaryDay

    /// 수면 구간과 그 출처를 함께 정한다. 출처를 따로 두면 «직접 입력» 을 건강 앱 값이
    /// 덮어쓰는 사고가 난다 — 둘은 항상 같이 바뀐다.
    ///
    /// `window` 가 `nil` 이면 그날 수면 기록을 지운다. 지우는 길이 없으면 잘못 찍은 시각을
    /// 되돌릴 방법이 없어 «0시간» 같은 거짓 기록이 남는다.
    @discardableResult
    func setSleep(on day: Date, window: DiarySleepWindow?, source: DiarySleepSource) throws -> DiaryDay
}
