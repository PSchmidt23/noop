import XCTest
@testable import Baseline

/// The pure data behind Settings › About › "How accurate is this?" (`AccuracyCitations`) and the Sleep
/// window card's span text. The screen itself is SwiftUI; what can be wrong in data is pinned here:
/// a metric with no study behind it, a stale key, a reference number the review does not have, a
/// vocabulary slip, or a sources line whose links do not survive Markdown parsing.
final class AccuracyScreenTests: XCTestCase {
    private let forbidden = ["strain", "recovery", "coach"]

    func testEveryRatedMetricHasAtLeastOneSource() {
        for metric in MetricAccuracy.all {
            XCTAssertFalse(AccuracyCitations.sources(for: metric.key).isEmpty, "no sources for \(metric.key)")
        }
    }

    func testCitationKeysMatchTheAccuracyTable() {
        let rated = Set(MetricAccuracy.all.map(\.key))
        for key in AccuracyCitations.byMetric.keys {
            XCTAssertTrue(rated.contains(key), "citations for an unrated key: \(key)")
        }
        XCTAssertEqual(Set(AccuracyCitations.byMetric.keys), rated)
    }

    func testReferenceNumbersAreTheReviewsAndEveryCitedNumberResolves() {
        let numbers = AccuracyCitations.references.map(\.number)
        XCTAssertEqual(Set(numbers).count, numbers.count, "duplicate reference number")
        XCTAssertTrue(numbers.allSatisfy { (1...31).contains($0) })
        // 23, 24 (vendor documents) and 30 (preprint duplicate) are deliberately absent.
        XCTAssertFalse(numbers.contains(23)); XCTAssertFalse(numbers.contains(24)); XCTAssertFalse(numbers.contains(30))
        for (key, cited) in AccuracyCitations.byMetric {
            XCTAssertEqual(AccuracyCitations.sources(for: key).map(\.number), cited,
                           "\(key) cites a number the reference list does not carry")
        }
        for ref in AccuracyCitations.references {
            XCTAssertEqual(ref.url.scheme, "https")
            XCTAssertEqual(ref.url.host, "doi.org", ref.short)
            XCTAssertFalse(ref.short.isEmpty)
        }
    }

    func testSourcesLineParsesWithOneLinkPerReference() throws {
        for metric in MetricAccuracy.all {
            let markdown = try XCTUnwrap(AccuracyCitations.sourcesMarkdown(for: metric.key))
            XCTAssertTrue(markdown.hasPrefix("Sources: "))
            let text = try XCTUnwrap(AccuracyCitations.sourcesText(for: metric.key))
            var links = 0
            for run in text.runs where run.link != nil { links += 1 }
            XCTAssertEqual(links, AccuracyCitations.sources(for: metric.key).count, metric.key)
            XCTAssertTrue(String(text.characters).hasPrefix("Sources: "))
        }
        XCTAssertNil(AccuracyCitations.sourcesMarkdown(for: "nope"))
        XCTAssertNil(AccuracyCitations.sourcesText(for: "nope"))
    }

    func testVocabularyGuardrail() {
        for ref in AccuracyCitations.references {
            for word in forbidden {
                XCTAssertFalse(ref.short.lowercased().contains(word), "\(ref.short) carries \(word)")
            }
        }
        XCTAssertFalse(AccuracyScreen.reviewURL.absoluteString.lowercased().contains("whoop"))
    }

    func testSleepWindowSpanText() {
        XCTAssertEqual(SettingsSleepWindowCard.spanText(480), "8h")
        XCTAssertEqual(SettingsSleepWindowCard.spanText(450), "7h 30m")
        XCTAssertEqual(SettingsSleepWindowCard.spanText(0), "0h")
        XCTAssertEqual(SettingsSleepWindowCard.spanText(BaselineReadouts.SleepWindow.default.spanMinutes), "8h")
    }
}
