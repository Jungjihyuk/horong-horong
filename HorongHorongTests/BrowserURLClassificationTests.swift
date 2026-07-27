import XCTest
import SwiftData
@testable import 호롱호롱

final class BrowserURLClassificationTests: XCTestCase {
    func testWebsiteURLInspectionRespectsExplicitNonBrowserMappings() {
        XCTAssertFalse(
            AppTracker.shouldInspectWebsiteURL(
                isKnownBrowser: false,
                classification: .category("개발"),
                hasWebsiteRules: true
            )
        )
        XCTAssertTrue(
            AppTracker.shouldInspectWebsiteURL(
                isKnownBrowser: false,
                classification: .unclassified,
                hasWebsiteRules: true
            )
        )
        XCTAssertFalse(
            AppTracker.shouldInspectWebsiteURL(
                isKnownBrowser: false,
                classification: .unclassified,
                hasWebsiteRules: false
            )
        )
        XCTAssertTrue(
            AppTracker.shouldInspectWebsiteURL(
                isKnownBrowser: true,
                classification: .category("개발"),
                hasWebsiteRules: false
            )
        )
        XCTAssertFalse(
            AppTracker.shouldInspectWebsiteURL(
                isKnownBrowser: true,
                classification: .excluded,
                hasWebsiteRules: true
            )
        )
    }

    func testUnmappedNonBrowserAppHandlingModes() {
        XCTAssertEqual(
            AppTracker.categoryForNonBrowserApp(
                classification: .unclassified,
                unmappedAppHandling: .pendingClassification
            ),
            Constants.unclassifiedAppCategory
        )
        XCTAssertEqual(
            AppTracker.categoryForNonBrowserApp(
                classification: .unclassified,
                unmappedAppHandling: .recordAsOther
            ),
            Constants.categoryName("기타")
        )
        XCTAssertNil(
            AppTracker.categoryForNonBrowserApp(
                classification: .unclassified,
                unmappedAppHandling: .doNotRecord
            )
        )
    }

    func testExplicitNonBrowserAppRulesOverrideUnmappedHandling() {
        for handling in Constants.UnmappedAppHandling.allCases {
            XCTAssertEqual(
                AppTracker.categoryForNonBrowserApp(
                    classification: .category("개발"),
                    unmappedAppHandling: handling
                ),
                "개발"
            )
            XCTAssertNil(
                AppTracker.categoryForNonBrowserApp(
                    classification: .excluded,
                    unmappedAppHandling: handling
                )
            )
        }
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
        XCTAssertNil(
            WebsiteCategoryRule.bestMatch(
                for: "https://example.com/?next=https://chatgpt.com",
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

    func testWebsiteRuleMatchesTrackedDomainAcrossBrowsers() {
        XCTAssertTrue(
            WebsiteCategoryRule.matchesTrackedBundleIdentifier(
                "com.google.Chrome.website.chatgpt.com",
                domain: "chatgpt.com"
            )
        )
        XCTAssertTrue(
            WebsiteCategoryRule.matchesTrackedBundleIdentifier(
                "com.apple.Safari.website.chatgpt.com",
                domain: "https://www.chatgpt.com/codex"
            )
        )
        XCTAssertFalse(
            WebsiteCategoryRule.matchesTrackedBundleIdentifier(
                "com.apple.Safari.website.fakechatgpt.com",
                domain: "chatgpt.com"
            )
        )
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

    func testYouTubeDefaultWebsiteRuleIncludesShortLinkAlias() {
        XCTAssertEqual(
            Constants.websiteRuleDomains(for: "youtube.com"),
            ["youtube.com", "youtu.be"]
        )
        XCTAssertEqual(
            Constants.canonicalWebsiteRuleDomain(for: "https://youtu.be/abc"),
            "youtube.com"
        )
        XCTAssertTrue(Constants.websiteAliases(for: "netflix.com").isEmpty)
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

    @MainActor
    func testYouTubeCategoryChangeAppliesToRootSubdomainsAndShortLinkAlias() throws {
        let schema = Schema([
            AppCategoryRule.self,
            AppUsageSegment.self,
            AppUsageRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let identifier = WebsiteCategoryRule.bundleIdentifier(for: "youtube.com")
        let rule = AppCategoryRule(
            bundleIdentifier: identifier,
            appName: "youtube.com",
            category: "공부",
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

        let expected = WebsiteCategoryMatch(domain: "youtube.com", category: "공부")
        XCTAssertEqual(
            CategoryManager.shared.websiteMatch(
                for: "https://youtube.com/watch?v=abc"
            ),
            expected
        )
        XCTAssertEqual(
            CategoryManager.shared.websiteMatch(
                for: "https://music.youtube.com/watch?v=abc"
            ),
            expected
        )
        XCTAssertEqual(
            CategoryManager.shared.websiteMatch(for: "https://youtu.be/abc"),
            WebsiteCategoryMatch(domain: "youtu.be", category: "공부")
        )
        XCTAssertNil(
            CategoryManager.shared.websiteMatch(
                for: "https://notyoutube.com/?next=youtu.be"
            )
        )
    }
}
