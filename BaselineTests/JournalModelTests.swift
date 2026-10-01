import XCTest
import StrandAnalytics
@testable import Baseline

/// The Journal screen's separable pieces: how a question is matched to a dosed behaviour, the chip
/// labels and delta formatting, and the dose card's sentence for each engine state. The behaviours /
/// controls day sets themselves are built inside `JournalScreenModel.reloadJournal(repo:)` from a
/// live `Repository`, so they are not covered here.
@MainActor
final class JournalModelTests: XCTestCase {

    // MARK: Dosed-behaviour matching

    func testQuestionMatchesDosedBehaviour() {
        XCTAssertTrue(JournalScreenModel.matches(.alcohol, "Did you drink any alcohol?"))
        XCTAssertTrue(JournalScreenModel.matches(.caffeine, "Did you have caffeine late in the day?"))
        XCTAssertTrue(JournalScreenModel.matches(.caffeine, "Coffee after lunch"), "custom habits match on the keyword")
        XCTAssertFalse(JournalScreenModel.matches(.alcohol, "Did you use a sauna?"))
        XCTAssertFalse(JournalScreenModel.matches(.caffeine, "Did you drink any alcohol?"))
    }

    // MARK: Labels and deltas

    func testShortLabels() {
        XCTAssertEqual(JournalLabels.short("Did you drink any alcohol?"), "Alcohol")
        XCTAssertEqual(JournalLabels.short("did you  drink any alcohol?"), "Alcohol", "starter lookup is whitespace- and case-insensitive")
        XCTAssertEqual(JournalLabels.short("Did you meditate?"), "Meditate", "the question frame is stripped")
        XCTAssertEqual(JournalLabels.short("Cold plunge"), "Cold plunge")
    }

    func testSignedDeltaAndMagnitude() {
        XCTAssertEqual(JournalLabels.signedDelta(5.4, unit: "ms"), "+5 ms")
        XCTAssertEqual(JournalLabels.signedDelta(-7.2, unit: "bpm"), "\u{2212}7 bpm")
        XCTAssertEqual(JournalLabels.signedDelta(0.3, unit: "ms"), "0 ms")
        XCTAssertEqual(JournalLabels.signedDelta(2, unit: ""), "+2")
        XCTAssertEqual(JournalLabels.magnitude(4.0), "4")
        XCTAssertEqual(JournalLabels.magnitude(4.46), "4.5")
    }

    func testOutcomeVocabulary() {
        XCTAssertEqual(JournalOutcome.hrv.label, "HRV")
        XCTAssertEqual(JournalOutcome.hrv.unit, "ms")
        XCTAssertTrue(JournalOutcome.hrv.higherIsBetter)
        XCTAssertEqual(JournalOutcome.rhr.label, "Resting HR")
        XCTAssertEqual(JournalOutcome.rhr.unit, "bpm")
        XCTAssertFalse(JournalOutcome.rhr.higherIsBetter)
    }

    // MARK: Dose cards

    private func response(_ behavior: DosedBehavior, perUnit: Double, priorSlope: Double, nUser: Int,
                          priorDominated: Bool, contradictsPrior: Bool) -> DoseResponse {
        DoseResponse(behavior: behavior, outcome: behavior == .alcohol ? "Charge" : "HRV", perUnit: perUnit,
                     userSlope: nil, priorSlope: priorSlope, weight: 0.5, nUser: nUser,
                     priorDominated: priorDominated, contradictsPrior: contradictsPrior,
                     confidence: .building, curve: [])
    }

    func testAlcoholCard_isDirectionalAndNamesThePrior() {
        let prior = JournalDose(behavior: .alcohol, response: response(.alcohol, perUnit: -3, priorSlope: -3, nUser: 3,
                                                                        priorDominated: true, contradictsPrior: false))
        XCTAssertEqual(prior.title, "Alcohol")
        XCTAssertNil(prior.perUnitStat, "the alcohol prior is in an engine score no Baseline screen shows")
        XCTAssertTrue(prior.sentence.contains("the lower the next morning reads"))
        XCTAssertTrue(prior.sentence.contains("not yet yours (3 nights)"))

        let own = JournalDose(behavior: .alcohol, response: response(.alcohol, perUnit: -2, priorSlope: -3, nUser: 12,
                                                                      priorDominated: false, contradictsPrior: false))
        XCTAssertTrue(own.sentence.hasSuffix("for you (12 nights)."))
        XCTAssertFalse(own.sentence.contains("typical pattern"))
    }

    func testCaffeineCard_carriesPerStepShiftInMs() {
        let dose = JournalDose(behavior: .caffeine, response: response(.caffeine, perUnit: -2.5, priorSlope: -2, nUser: 9,
                                                                        priorDominated: false, contradictsPrior: false))
        XCTAssertEqual(dose.title, "Caffeine timing")
        XCTAssertEqual(dose.perUnitStat?.unit, "ms")
        XCTAssertEqual(dose.perUnitStat?.label, "Per later step")
        XCTAssertTrue(dose.sentence.contains("about 2.5 ms lower HRV"))
        XCTAssertTrue(dose.sentence.hasSuffix("for you (9 nights)."))
        // The stat cell prints the same tenth the sentence states, never a whole-number rounding of it.
        XCTAssertEqual(dose.perUnitText, "\u{2212}2.5")
        let up = JournalDose(behavior: .caffeine, response: response(.caffeine, perUnit: 2.04, priorSlope: -2, nUser: 9,
                                                                      priorDominated: false, contradictsPrior: false))
        XCTAssertEqual(up.perUnitText, "+2")
        let flat = JournalDose(behavior: .caffeine, response: response(.caffeine, perUnit: -0.04, priorSlope: -2, nUser: 9,
                                                                        priorDominated: false, contradictsPrior: false))
        XCTAssertEqual(flat.perUnitText, "0")

        let one = JournalDose(behavior: .caffeine, response: response(.caffeine, perUnit: 1, priorSlope: -2, nUser: 1,
                                                                       priorDominated: false, contradictsPrior: true))
        XCTAssertTrue(one.sentence.contains("doesn't move your HRV"))
        XCTAssertTrue(one.sentence.hasSuffix("(1 night)."), "singular night count")
    }

    func testNoForbiddenVocabulary() {
        // The fork's rule: never "Strain", "Recovery" or "Coach" in UI copy.
        let doses = [
            JournalDose(behavior: .alcohol, response: response(.alcohol, perUnit: -3, priorSlope: -3, nUser: 3,
                                                               priorDominated: true, contradictsPrior: false)),
            JournalDose(behavior: .caffeine, response: response(.caffeine, perUnit: -2, priorSlope: -2, nUser: 3,
                                                                priorDominated: true, contradictsPrior: false)),
        ]
        for d in doses {
            for word in ["Strain", "Recovery", "Coach", "Charge"] {
                XCTAssertFalse((d.title + d.subtitle + d.sentence).contains(word), "\(word) leaked into \(d.id) copy")
            }
        }
    }
}
