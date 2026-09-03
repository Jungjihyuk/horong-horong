import Foundation

/// 루미롱(Luminous + 호롱의 '롱') — 호롱호롱 AI 컴패니언의 공통 모델.
/// 캐릭터를 추가할 때는 스프라이트 폴더와 대사 카탈로그만 새로 정의해
/// `CompanionRegistry.all` 에 등록하면 된다.
struct CompanionCharacter: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let tagline: String
    /// 앱 번들 Resources 안의 스프라이트 루트 폴더 이름.
    /// 이 폴더 아래에 `CompanionAnimation.directoryName` 별 하위 폴더가 있다.
    let spriteRoot: String
    let lines: CompanionLineCatalog
}

/// 상황별 대사 묶음. 같은 상황에서도 매번 다른 말을 고르도록 배열로 둔다.
struct CompanionLineCatalog: Hashable, Sendable {
    var greeting: [String]
    var focusFarewell: [String]
    var breakInvitation: [String]
    var play: [String]
    var rest: [String]
    var briefingIntro: [String]
    var briefingEmpty: [String]

    func pick(
        _ keyPath: KeyPath<CompanionLineCatalog, [String]>,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        self[keyPath: keyPath].randomElement(using: &generator) ?? ""
    }
}

extension CompanionCharacter {
    static let hororong = CompanionCharacter(
        id: "hororong",
        displayName: "호로롱",
        tagline: "호롱호롱의 첫 번째 루미롱. 화면 아래를 거닐며 집중을 함께합니다.",
        spriteRoot: "companion",
        lines: CompanionLineCatalog(
            greeting: [
                "호로롱! 오늘도 같이 해봐요.",
                "여기 있어요. 필요하면 불러주세요.",
                "좋은 하루예요. 천천히 시작해볼까요?",
            ],
            focusFarewell: [
                "집중 시간이네요. 조용히 있을게요!",
                "방해 안 할게요. 다녀올게요.",
            ],
            breakInvitation: [
                "쉬는 시간이에요. 뭐 할까요?",
                "잠깐 숨 돌려요. 같이 있을까요?",
            ],
            play: [
                "좋아요, 신나게 놀아봐요!",
                "폴짝! 몸도 좀 풀어야죠.",
            ],
            rest: [
                "눈 좀 감고 쉬어요. 옆에 있을게요.",
                "조용히 있을게요. 푹 쉬어요.",
            ],
            briefingIntro: [
                "오늘 일정 정리해왔어요!",
                "오늘 할 일, 같이 볼까요?",
            ],
            briefingEmpty: [
                "오늘 등록된 일정이 없네요. 하나 정해볼까요?",
                "오늘은 비어 있어요. 여유롭게 시작해요.",
            ]
        )
    )
}

enum CompanionRegistry {
    static let all: [CompanionCharacter] = [.hororong]

    /// 등록되지 않은 식별자는 기본 컴패니언으로 되돌린다.
    static func character(for identifier: String) -> CompanionCharacter {
        all.first { $0.id == identifier } ?? .hororong
    }
}
