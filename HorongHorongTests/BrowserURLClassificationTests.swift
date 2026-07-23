import XCTest
import SwiftData
@testable import 호롱호롱

final class BrowserURLClassificationTests: XCTestCase {
    func testEntertainmentURLClassification() {
        XCTAssertEqual(AppTracker.entertainmentLabel(for: "https://www.youtube.com/watch?v=abc"), "YouTube")
        XCTAssertEqual(AppTracker.entertainmentLabel(for: "https://youtu.be/abc"), "YouTube")
        XCTAssertEqual(AppTracker.entertainmentLabel(for: "https://www.netflix.com/watch/123"), "Netflix")
        XCTAssertNil(AppTracker.entertainmentLabel(for: "https://developer.apple.com/documentation"))
    }

    func testResearchURLClassification() {
        XCTAssertEqual(AppTracker.researchLabel(for: "https://www.google.com/search?q=swiftdata"), "Google Search")
        XCTAssertEqual(AppTracker.researchLabel(for: "https://developer.mozilla.org/en-US/docs/Web"), "MDN")
        XCTAssertEqual(AppTracker.researchLabel(for: "https://some-team.github.io/project-docs"), "GitHub Pages")
        XCTAssertEqual(AppTracker.researchLabel(for: "https://example.tistory.com/entry/swift"), "Tistory")
        XCTAssertNil(AppTracker.researchLabel(for: "https://www.google.com/maps"))
    }

    func testWebsiteDomainNormalizationAcceptsDomainOrFullURL() {
        XCTAssertEqual(
            WebsiteCategoryRule.normalizedDomain(from: "chatgpt.com"),
            "chatgpt.com"
        )
        XCTAssertEqual(
            WebsiteCategoryRule.normalizedDomain(from: "https://www.ChatGPT.com/codex?tab=tasks"),
            "chatgpt.com"
        )
        XCTAssertEqual(
            WebsiteCategoryRule.normalizedDomain(from: " chatgpt.com:443/path "),
            "chatgpt.com"
        )
        XCTAssertNil(WebsiteCategoryRule.normalizedDomain(from: "not a domain"))
    }

    func testWebsiteRuleMatchesEveryURLOnDomainAndSubdomains() {
        let rules = ["chatgpt.com": "개발"]

        XCTAssertEqual(
            WebsiteCategoryRule.bestMatch(
                for: "https://chatgpt.com/codex",
                rules: rules
            ),
            WebsiteCategoryMatch(domain: "chatgpt.com", category: "개발")
        )
        XCTAssertEqual(
            WebsiteCategoryRule.bestMatch(
                for: "https://team.chatgpt.com/workspace",
                rules: rules
            ),
            WebsiteCategoryMatch(domain: "chatgpt.com", category: "개발")
        )
        XCTAssertNil(
            WebsiteCategoryRule.bestMatch(
                for: "https://fakechatgpt.com",
                rules: rules
            )
        )
    }

    func testMoreSpecificWebsiteRuleWins() {
        let rules = [
            "example.com": "기타",
            "docs.example.com": "조사",
        ]

        XCTAssertEqual(
            WebsiteCategoryRule.bestMatch(
                for: "https://api.docs.example.com/guide",
                rules: rules
            ),
            WebsiteCategoryMatch(domain: "docs.example.com", category: "조사")
        )
    }

    func testWebsiteRuleIdentifierRoundTripsNormalizedDomain() {
        let identifier = WebsiteCategoryRule.bundleIdentifier(for: "chatgpt.com")
        XCTAssertEqual(
            WebsiteCategoryRule.domain(from: identifier),
            "chatgpt.com"
        )
        XCTAssertNil(WebsiteCategoryRule.domain(from: "com.google.Chrome"))
    }

    func testRequestedServicesAreDefaultWebsiteCategoryRules() {
        let rules = Dictionary(
            uniqueKeysWithValues: Constants.defaultWebsiteCategoryRules.map {
                ($0.domain, $0.category)
            }
        )

        XCTAssertEqual(rules["chatgpt.com"], Constants.categoryName("개발"))
        XCTAssertEqual(rules["claude.ai"], Constants.categoryName("개발"))
        XCTAssertEqual(rules["gemini.google.com"], Constants.categoryName("개발"))
        XCTAssertEqual(rules["youtube.com"], Constants.categoryName("엔터"))
        XCTAssertEqual(rules["netflix.com"], Constants.categoryName("엔터"))
    }

    @MainActor
    func testCategoryManagerLoadsPersistedWebsiteRulesSeparately() throws {
        let schema = Schema([
            AppCategoryRule.self,
            AppUsageSegment.self,
            AppUsageRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let identifier = WebsiteCategoryRule.bundleIdentifier(for: "chatgpt.com")
        let rule = AppCategoryRule(
            bundleIdentifier: identifier,
            appName: "chatgpt.com",
            category: "개발",
            isUserDefined: true
        )
        context.insert(rule)
        try context.save()

        CategoryManager.shared.loadUserRules(from: context)
        defer {
            context.delete(rule)
            try? context.save()
            CategoryManager.shared.loadUserRules(from: context)
        }

        XCTAssertEqual(
            CategoryManager.shared.websiteMatch(for: "https://chatgpt.com/codex"),
            WebsiteCategoryMatch(domain: "chatgpt.com", category: "개발")
        )
        XCTAssertEqual(
            CategoryManager.shared.trackingClassification(for: identifier),
            .unclassified
        )
    }
}
