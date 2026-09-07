import XCTest
import AppKit
@testable import 호롱호롱

/// 기록 분류 목록과, 팝오버가 저장값을 읽는 규칙.
///
/// 팝오버와 허브 창이 저장 키(`mind.section`) 하나를 함께 쓰기 때문에,
/// 팝오버가 그리지 못하는 값이 들어왔을 때 어떻게 되는지가 화면이 아니라 여기서 정해진다.
@MainActor
final class SecondBrainSectionTests: XCTestCase {
    func testPopoverSectionsAreFiveInFixedOrder() {
        XCTAssertEqual(
            SecondBrainSection.popoverSections,
            [.quick, .diary, .todo, .knowledge, .works]
        )
    }

    func testKnownSectionIsReadAsIs() {
        XCTAssertEqual(SecondBrainSection.popoverSection(rawValue: "diary"), .diary)
        XCTAssertEqual(SecondBrainSection.popoverSection(rawValue: "knowledge"), .knowledge)
    }

    /// 허브에서 References 를 고른 채 팝오버를 열어도 화면이 비지 않아야 한다.
    func testUnsupportedSectionFallsBackToTodo() {
        XCTAssertEqual(SecondBrainSection.popoverSection(rawValue: "refs"), .todo)
    }

    func testBrokenValueFallsBackToTodo() {
        XCTAssertEqual(SecondBrainSection.popoverSection(rawValue: "쓰레기"), .todo)
        XCTAssertEqual(SecondBrainSection.popoverSection(rawValue: ""), .todo)
    }

    /// 짧은 이름은 360pt 폭에 다섯 칸으로 나뉘어 들어간다. 길어지면 말줄임이 생겨
    /// 무엇인지 알아볼 수 없으므로 길이에 상한을 둔다.
    func testShortLabelsFitInASegment() {
        for section in SecondBrainSection.allCases {
            XCTAssertFalse(section.shortLabel.isEmpty, "\(section) 의 짧은 이름이 비어 있다")
            XCTAssertLessThanOrEqual(
                section.shortLabel.count,
                6,
                "\(section) 의 짧은 이름이 세그먼트 한 칸보다 길다: \(section.shortLabel)"
            )
        }
    }

    /// 없는 이름을 적으면 화면에 빈칸이 뜨는데, 그 시점엔 이미 늦다.
    func testEverySectionHasAnExistingSymbol() {
        for section in SecondBrainSection.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil),
                "\(section) 의 기호가 이 시스템에 없다: \(section.symbol)"
            )
        }
    }

    func testOnlyPlannedSectionsAreMarkedComingSoon() {
        XCTAssertEqual(
            SecondBrainSection.allCases.filter(\.isComingSoon),
            [.knowledge, .works]
        )
    }
}
