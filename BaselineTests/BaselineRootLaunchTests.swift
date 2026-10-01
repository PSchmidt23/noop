import XCTest
@testable import Baseline

/// `BaselineRoot.LaunchRequest.parse`: the DEBUG `--tab` argument over the three tabs, with the aliases
/// the screenshot harness relies on (`today` → Home; `journal` → Home with the journal sheet; `settings`
/// → Home with Settings pushed).
final class BaselineRootLaunchTests: XCTestCase {

    private func parse(_ args: String...) -> BaselineRoot.LaunchRequest {
        BaselineRoot.LaunchRequest.parse(["Baseline"] + args)
    }

    func testDefaultsToHome() {
        XCTAssertEqual(parse(), .init(tab: .home))
        XCTAssertEqual(parse("--demo-seed"), .init(tab: .home))
        XCTAssertEqual(parse("--tab"), .init(tab: .home), "a missing value is Home")
        XCTAssertEqual(parse("--tab", "nonsense"), .init(tab: .home))
    }

    func testTabs() {
        XCTAssertEqual(parse("--tab", "home"), .init(tab: .home))
        XCTAssertEqual(parse("--tab", "trends"), .init(tab: .trends))
        XCTAssertEqual(parse("--tab", "sleep"), .init(tab: .sleep))
    }

    func testAliases() {
        XCTAssertEqual(parse("--tab", "today"), .init(tab: .home))
        XCTAssertEqual(parse("--tab", "journal"), .init(tab: .home, journal: true))
        XCTAssertEqual(parse("--tab", "settings"), .init(tab: .home, settings: true))
    }

    func testOtherArgumentsAroundItAreIgnored() {
        XCTAssertEqual(parse("--demo-seed", "--skip-onboarding", "--tab", "sleep", "--ui-testing"), .init(tab: .sleep))
    }
}
