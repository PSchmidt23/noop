import XCTest
@testable import Baseline

/// The pure text behind Settings › Profile › "Intensity goal" (`SettingsIntensityGoalCard`) and the
/// second accuracy table (`AccuracyExtras`, the rows Settings › About › "How accurate is this?" draws
/// for Intensity minutes and heart rate). What can be wrong in data is pinned: the card quoting a
/// cut-off the engine does not use, a goal text without its unit, a max heart rate quoted for a
/// profile the card above calls "not set", a row whose tier or caveat drifts from the detail screen's
/// badge, a reference number the second review does not carry, a vocabulary slip, or a vendor's
/// feature name in copy.
final class SettingsIntensityGoalTests: XCTestCase {
    private let forbidden = ["strain", "recovery", "coach", "active zone", "exercise ring", "move ring"]

    // MARK: Intensity goal card

    func testGoalTextCarriesTheUnit() {
        XCTAssertEqual(SettingsIntensityGoalCard.goalText(150), "150 min")
        XCTAssertEqual(SettingsIntensityGoalCard.goalText(IntensityMinutes.goalDefault), "150 min")
    }

    func testGoalLineSaysVigorousCountsDouble() {
        XCTAssertEqual(SettingsIntensityGoalCard.goalLine,
                       "Weekly minutes of moderate activity; vigorous minutes count double.")
    }

    /// The card's cut-offs are the engine's constants, so a change to `IntensityMinutes.Thresholds`
    /// shows up here without a copy edit.
    func testBasisTextQuotesTheEnginesCutOffsAndTheProfilesMaxHR() {
        let estimated = SettingsIntensityGoalCard.basisText(hrMax: 182, manual: false)
        XCTAssertEqual(estimated, "Moderate from 40 % and vigorous from 60 % of your heart-rate reserve, against the max heart rate in Profile (182 bpm, estimated from your age).")
        XCTAssertTrue(estimated.contains("\(Int(IntensityMinutes.Thresholds.moderatePctHRR)) %"))
        XCTAssertTrue(estimated.contains("\(Int(IntensityMinutes.Thresholds.vigorousPctHRR)) %"))

        let manual = SettingsIntensityGoalCard.basisText(hrMax: 190, manual: true)
        XCTAssertTrue(manual.contains("190 bpm, set manually"))
        XCTAssertFalse(manual.contains("estimated"))
    }

    /// The line the card draws goes through Home's gate (`TodayDetail.intensityProfile`): a nil max heart
    /// rate (no date of birth, no override) names what the minutes wait for and quotes no number, so this
    /// card cannot claim an age-based estimate while the Profile card above says the age is not set.
    /// With a max it is `basisText`, unchanged.
    func testBasisLineWaitsForAProfileBeforeQuotingAMaxHR() {
        let pending = SettingsIntensityGoalCard.basisLine(hrMax: nil, manual: false)
        XCTAssertEqual(pending, SettingsIntensityGoalCard.basisPending)
        XCTAssertEqual(pending, "Minutes are scored once a date of birth or a max heart rate is set above.")
        XCTAssertFalse(pending.contains("bpm"))
        XCTAssertFalse(pending.contains("estimated"))
        XCTAssertNil(pending.rangeOfCharacter(from: .decimalDigits), "no number without a profile")

        XCTAssertEqual(SettingsIntensityGoalCard.basisLine(hrMax: 182, manual: false),
                       SettingsIntensityGoalCard.basisText(hrMax: 182, manual: false))
        XCTAssertEqual(SettingsIntensityGoalCard.basisLine(hrMax: 190, manual: true),
                       SettingsIntensityGoalCard.basisText(hrMax: 190, manual: true))
        XCTAssertTrue(SettingsIntensityGoalCard.basisLine(hrMax: 190, manual: true).contains("190 bpm, set manually"))
    }

    /// The Profile form's "Estimated from your age" row sits behind the same gate; without a date of
    /// birth it names the missing input and quotes no bpm.
    func testProfileFormEstimateWaitsForADateOfBirth() {
        let pending = SettingsProfileForm.estimatePending
        XCTAssertEqual(pending, "Needs your date of birth")
        XCTAssertFalse(pending.contains("bpm"))
        XCTAssertNil(pending.rangeOfCharacter(from: .decimalDigits))
    }

    /// The stepper's range and step are the engine's, and the default sits inside the range on a step.
    func testGoalRangeIsTheEngines() {
        XCTAssertTrue(IntensityMinutes.goalRange.contains(IntensityMinutes.goalDefault))
        XCTAssertEqual(IntensityMinutes.goalDefault % IntensityMinutes.goalStep, 0)
        XCTAssertEqual(IntensityMinutes.goalRange.lowerBound % IntensityMinutes.goalStep, 0)
        XCTAssertEqual(IntensityMinutes.goalRange.upperBound % IntensityMinutes.goalStep, 0)
    }

    func testGoalCardVocabulary() {
        for text in [SettingsIntensityGoalCard.goalLine,
                     SettingsIntensityGoalCard.basisText(hrMax: 182, manual: false),
                     SettingsIntensityGoalCard.basisPending,
                     SettingsProfileForm.estimatePending] {
            for word in forbidden {
                XCTAssertFalse(text.lowercased().contains(word), "\(text) carries \(word)")
            }
        }
    }

    // MARK: Accuracy rows from the second review

    func testExtrasAreIntensityMinutesAndHeartRate() {
        XCTAssertEqual(AccuracyExtras.keys, [.intensityMinutes, .heartRate])
        XCTAssertEqual(AccuracyExtras.rows.map(\.key), ["intensityMinutes", "heartRate"])
        XCTAssertEqual(AccuracyExtras.rows.map(\.name), ["Intensity minutes", "Heart rate"])
        XCTAssertEqual(AccuracyExtras.rows.map(\.tier), [.medium, .medium])
    }

    /// The row says what the detail screen's badge says, because it is read from the same spec.
    func testExtrasMatchTheDetailBadges() {
        for row in AccuracyExtras.rows {
            guard let key = MetricKey(rawValue: row.key) else {
                XCTFail("\(row.key) is not a MetricKey")
                continue
            }
            let spec = MetricDetailSpec.standard(key)
            XCTAssertNil(spec.accuracyKey, "\(row.key) is rated by the metric review; it needs no extra row")
            XCTAssertEqual(spec.accuracy?.tier, row.tier, row.key)
            XCTAssertEqual(spec.accuracy?.caveat, row.caveat, row.key)
            XCTAssertEqual(spec.title, row.name, row.key)
        }
        XCTAssertEqual(AccuracyExtras.rows.first { $0.key == "intensityMinutes" }?.caveat,
                       BaselineReadouts.IntensityReadout.caveat)
    }

    /// The two tables never share a key, and every row the screen draws has a tier card to land in.
    func testExtrasDoNotOverlapTheMetricReview() {
        let rated = Set(MetricAccuracy.all.map(\.key))
        for row in AccuracyExtras.rows {
            XCTAssertFalse(rated.contains(row.key), "\(row.key) is in both tables")
            XCTAssertNil(MetricAccuracy.lookup(row.key))
        }
        XCTAssertEqual(AccuracyExtras.allRows.count, MetricAccuracy.all.count + AccuracyExtras.rows.count)
        let keys = AccuracyExtras.allRows.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate key across the two tables")
    }

    func testEveryExtraRowHasSourcesFromTheSecondReview() {
        for row in AccuracyExtras.rows {
            let cited = AccuracyCitations.intensityByMetric[row.key] ?? []
            XCTAssertFalse(cited.isEmpty, "no sources for \(row.key)")
            XCTAssertEqual(AccuracyCitations.sources(for: row.key).map(\.number), cited,
                           "\(row.key) cites a number the second review's list does not carry")
            XCTAssertNil(AccuracyCitations.byMetric[row.key], "\(row.key) must not also cite the metric review's numbers")
        }
        XCTAssertEqual(Set(AccuracyCitations.intensityByMetric.keys), Set(AccuracyExtras.rows.map(\.key)))
    }

    /// The second list is numbered as `INTENSITY_MINUTES.md` numbers its references (1–17); 5 (Karvonen
    /// 1957, PMID only) and the vendor pages have no DOI and are deliberately absent.
    func testSecondReviewReferenceNumbersAndLinks() {
        let numbers = AccuracyCitations.intensityReferences.map(\.number)
        XCTAssertEqual(Set(numbers).count, numbers.count, "duplicate reference number")
        XCTAssertTrue(numbers.allSatisfy { (1...17).contains($0) })
        XCTAssertFalse(numbers.contains(5))
        for ref in AccuracyCitations.intensityReferences {
            XCTAssertEqual(ref.url.scheme, "https")
            XCTAssertEqual(ref.url.host, "doi.org", ref.short)
            XCTAssertFalse(ref.short.isEmpty)
            for word in forbidden {
                XCTAssertFalse(ref.short.lowercased().contains(word), "\(ref.short) carries \(word)")
            }
        }
        // The one study at the Karvonen cut-offs leads both rows.
        XCTAssertEqual(AccuracyCitations.sources(for: "intensityMinutes").first?.short, "Ho 2022")
        XCTAssertEqual(AccuracyCitations.sources(for: "heartRate").first?.short, "Ho 2022")
    }

    func testExtraSourcesLineParsesWithOneLinkPerReference() throws {
        for row in AccuracyExtras.rows {
            let markdown = try XCTUnwrap(AccuracyCitations.sourcesMarkdown(for: row.key))
            XCTAssertTrue(markdown.hasPrefix("Sources: "))
            let text = try XCTUnwrap(AccuracyCitations.sourcesText(for: row.key))
            var links = 0
            for run in text.runs where run.link != nil { links += 1 }
            XCTAssertEqual(links, AccuracyCitations.sources(for: row.key).count, row.key)
        }
    }

    func testSecondReviewURL() {
        let url = AccuracyScreen.intensityReviewURL.absoluteString
        XCTAssertTrue(url.hasSuffix("Baseline/Research/INTENSITY_MINUTES.md"))
        XCTAssertFalse(url.lowercased().contains("whoop"))
        XCTAssertNotEqual(AccuracyScreen.intensityReviewURL, AccuracyScreen.reviewURL)
    }
}
