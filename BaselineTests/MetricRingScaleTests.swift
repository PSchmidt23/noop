import XCTest
import StrandAnalytics
@testable import Baseline

/// `MetricRingScale` decides how much of a ring's arc fills and never touches the numeral: a value
/// outside the display domain clamps the fraction to 0 or 1 but still prints exactly, the domain is nil
/// while the fold is not usable and never leaves the metric's physiological range, and the sleep ring
/// spans nine hours or an hour past the 30-night average.
final class MetricRingScaleTests: XCTestCase {

    private let cfg = MetricCfg(minVal: 10, maxVal: 200, floorSpread: 2, halfLifeB: 7, halfLifeS: 14)

    private func state(_ baseline: Double, spread: Double, status: BaselineStatus) -> BaselineState {
        BaselineState(baseline: baseline, spread: spread, nValid: 20, nightsSinceUpdate: 0, status: status)
    }

    func testFractionClampsOutsideTheDomain() {
        XCTAssertEqual(MetricRingScale.fraction(300, in: 40...100), 1)
        XCTAssertEqual(MetricRingScale.fraction(-5, in: 40...100), 0)
        XCTAssertEqual(MetricRingScale.fraction(70, in: 40...100), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MetricRingScale.fraction(50, in: 50...50), 0, "a degenerate domain never divides by zero")
    }

    func testNumeralIsNeverClamped() {
        XCTAssertEqual(MetricRingScale.numeral(value: 300, valueText: nil), "300")
        XCTAssertEqual(MetricRingScale.numeral(value: 64.6, valueText: nil), "65")
        XCTAssertEqual(MetricRingScale.numeral(value: nil, valueText: nil), "–")
        XCTAssertEqual(MetricRingScale.numeral(value: 444, valueText: "7h 24m"), "7h 24m")
    }

    func testDomainIsNilWhileCalibratingAndClampsToTheMetricRange() throws {
        XCTAssertNil(MetricRingScale.domain(state: state(60, spread: 4, status: .calibrating), cfg: cfg))
        XCTAssertNil(MetricRingScale.domain(state: state(60, spread: 4, status: .stale), cfg: cfg))

        // sigma = max(1.253 · 4, 0.05 · 60) = 5.012 → 60 ∓ 15.036.
        let d = try XCTUnwrap(MetricRingScale.domain(state: state(60, spread: 4, status: .trusted), cfg: cfg))
        XCTAssertEqual(d.lowerBound, 60 - 3 * 5.012, accuracy: 1e-6)
        XCTAssertEqual(d.upperBound, 60 + 3 * 5.012, accuracy: 1e-6)

        // A wide spread near the range edge clamps to cfg.minVal…cfg.maxVal.
        let edge = try XCTUnwrap(MetricRingScale.domain(state: state(20, spread: 40, status: .provisional), cfg: cfg))
        XCTAssertEqual(edge.lowerBound, cfg.minVal)
        XCTAssertEqual(edge.upperBound, 20 + 3 * 1.253 * 40, accuracy: 1e-6)
        let top = try XCTUnwrap(MetricRingScale.domain(state: state(190, spread: 40, status: .provisional), cfg: cfg))
        XCTAssertEqual(top.upperBound, cfg.maxVal)

        // The 5% floor keeps a tight baseline from collapsing the arc onto one value.
        let tight = try XCTUnwrap(MetricRingScale.domain(state: state(100, spread: 0.001, status: .trusted), cfg: cfg))
        XCTAssertEqual(tight.lowerBound, 85, accuracy: 1e-6)
        XCTAssertEqual(tight.upperBound, 115, accuracy: 1e-6)
    }

    func testSleepDomain() {
        XCTAssertEqual(MetricRingScale.sleepDomain(average30: 600), 0...660)
        XCTAssertEqual(MetricRingScale.sleepDomain(average30: nil), 0...540)
        XCTAssertEqual(MetricRingScale.sleepDomain(average30: 420), 0...540)
    }
}
