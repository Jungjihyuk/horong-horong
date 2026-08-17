import Foundation
import OSLog

/// 패키지가 남기는 로그의 단일 창구.
///
/// **`NSLog` 를 걷어낸 이유가 둘이다.**
///
/// ① `NSLog` 는 문자열을 **그대로** 남긴다. 추론 에러 설명에는 입력이 섞여 나오는 일이 있어,
///    사용자의 할 일 제목이나 대화가 그대로 기록될 수 있다. `Logger` 는 리터럴이 아닌 값을
///    기본적으로 가리고(`.private`), 남길 것만 `.public` 으로 골라 내보낸다.
///    앱이 릴리스에서 에러를 타입 이름만 남기는 것과 같은 맥락이다.
///
/// ② 형식이 제각각이면 나중에 모아 볼 수가 없다. `무엇 key=value` 로 통일한다 —
///    앱의 목표 추천 로그(`weekly mlx failure=inferenceFailed …`)가 이미 쓰는 모양이다.
///
/// **여기는 "무슨 일이 있었나"를 남기는 자리가 아니다.** 실행 한 건을 한 줄로 남기는
/// `RunRecord`·`RunLogger` 는 아직 없다 — 왜 미뤘는지는 폴더 결정 문서의 `Logging/` 절 참고.
/// 지금은 흩어져 있던 `NSLog` 를 한 형식으로 모으는 데까지다.
public enum AILog {
    /// 앱 번들 id 에 기대지 않는다. `swift test` 로 돌 때는 번들이 테스트 러너라 값이 달라진다.
    private static let subsystem = "com.horonghorong.ai"

    /// 모델을 부르다 생긴 일. 어느 공급자인지는 메시지 앞머리에 붙인다.
    public static let providers = Logger(subsystem: subsystem, category: "providers")

    /// 기록 자체가 실패한 일. 기록은 부수 작업이라 본래 하려던 일을 죽이지 않고 여기로 남긴다.
    public static let recording = Logger(subsystem: subsystem, category: "recording")
}
