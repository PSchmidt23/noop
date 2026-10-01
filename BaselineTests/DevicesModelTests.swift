import XCTest
import WhoopStore
@testable import Baseline

/// `DevicesModel`: which registry rows the Devices screen shows (NOOP's `my-whoop` placeholder is not a
/// strap until a peripheral is adopted or a bond is live), how a card names a strap, and the battery and
/// last-seen wording. Pure value tests; no store, Bluetooth or SwiftUI.
final class DevicesModelTests: XCTestCase {

    private func device(_ id: String, brand: String = "WHOOP", model: String = "WHOOP 4.0",
                        nickname: String? = nil, peripheralId: String? = nil,
                        sourceKind: SourceKind = .liveBLE, status: DeviceStatus = .paired,
                        lastSeenAt: Int = 1_700_000_000) -> PairedDevice {
        PairedDevice(id: id, brand: brand, model: model, nickname: nickname, peripheralId: peripheralId,
                     sourceKind: sourceKind, capabilities: [], status: status,
                     addedAt: 1_700_000_000, lastSeenAt: lastSeenAt)
    }

    // MARK: Visible straps

    func testPlaceholderRow_isHiddenUntilAdoptedOrBonded() {
        let seed = device("my-whoop", model: "WHOOP", status: .active)
        XCTAssertTrue(DevicesModel.visibleStraps([seed], liveBonded: false).isEmpty)
        XCTAssertEqual(DevicesModel.visibleStraps([seed], liveBonded: true).map(\.id), ["my-whoop"])
        var adopted = seed
        adopted.peripheralId = "0F0E0D0C-0000-0000-0000-000000000001"
        XCTAssertEqual(DevicesModel.visibleStraps([adopted], liveBonded: false).map(\.id), ["my-whoop"])
    }

    func testBond_onlyVouchesForTheActiveRow() {
        let pairedNoPeripheral = device("whoop-2", status: .paired)
        XCTAssertTrue(DevicesModel.visibleStraps([pairedNoPeripheral], liveBonded: true).isEmpty)
    }

    func testArchivedImportAndNonWhoopRows_areHidden() {
        let removed = device("whoop-old", peripheralId: "A", status: .archived)
        let csv = device("whoop-csv", peripheralId: "B", sourceKind: .fileImport)
        let watch = device("apple-watch", brand: "Apple", model: "Watch", peripheralId: "C", sourceKind: .liveAppleWatch)
        let strap = device("whoop-5", model: "WHOOP 5.0 / MG", peripheralId: "D")
        let shown = DevicesModel.visibleStraps([removed, csv, watch, strap], liveBonded: true)
        XCTAssertEqual(shown.map(\.id), ["whoop-5"])
    }

    func testVisibleStraps_keepRegistryOrder() {
        let a = device("a", peripheralId: "1")
        let b = device("b", peripheralId: "2", status: .active)
        XCTAssertEqual(DevicesModel.visibleStraps([a, b], liveBonded: false).map(\.id), ["a", "b"])
    }

    // MARK: Model label

    func testModelLabel_readsTheGenerationFromTheRegistryString() {
        XCTAssertEqual(DevicesModel.modelLabel("WHOOP 4.0"), "4.0")
        XCTAssertEqual(DevicesModel.modelLabel("WHOOP 5.0 / MG"), "5.0 / MG")
        XCTAssertNil(DevicesModel.modelLabel("WHOOP"))
        XCTAssertNil(DevicesModel.modelLabel(""))
    }

    func testModelLabel_liveVariantSettlesAFiveGenerationRow() {
        XCTAssertEqual(DevicesModel.modelLabel("WHOOP 5.0 / MG", liveVariant: "MG"), "MG")
        XCTAssertEqual(DevicesModel.modelLabel("WHOOP 5.0 / MG", liveVariant: "5.0"), "5.0")
        XCTAssertEqual(DevicesModel.modelLabel("WHOOP 5.0 / MG", liveVariant: "—"), "5.0 / MG")
        // A 4.0 row never takes a 5-generation variant.
        XCTAssertEqual(DevicesModel.modelLabel("WHOOP 4.0", liveVariant: "MG"), "4.0")
    }

    // MARK: Card title and subtitle

    func testCardTitle_isNicknameThenModelThenGeneric() {
        XCTAssertEqual(DevicesModel.cardTitle(device("a", nickname: "Left wrist")), "Left wrist")
        XCTAssertEqual(DevicesModel.cardTitle(device("a", nickname: "  ")), "WHOOP 4.0")
        XCTAssertEqual(DevicesModel.cardTitle(device("a")), "WHOOP 4.0")
        XCTAssertEqual(DevicesModel.cardTitle(device("a", model: "WHOOP")), "WHOOP strap")
    }

    func testCardSubtitle_onlyUnderANickname() {
        XCTAssertEqual(DevicesModel.cardSubtitle(device("a", nickname: "Left wrist")), "WHOOP 4.0")
        XCTAssertNil(DevicesModel.cardSubtitle(device("a")))
        XCTAssertNil(DevicesModel.cardSubtitle(device("a", model: "WHOOP", nickname: "Mine")))
    }

    // MARK: Battery

    func testBatteryText_clampsRoundsAndBands() {
        XCTAssertNil(DevicesModel.batteryText(pct: nil, charging: true))
        let full = DevicesModel.batteryText(pct: 100.4, charging: false)
        XCTAssertEqual(full?.text, "100%")
        XCTAssertEqual(full?.level, .good)
        let charging = DevicesModel.batteryText(pct: 71.6, charging: true)
        XCTAssertEqual(charging?.text, "Charging · 72%")
        XCTAssertEqual(DevicesModel.batteryText(pct: 40, charging: nil)?.level, .watch)
        XCTAssertEqual(DevicesModel.batteryText(pct: 20, charging: nil)?.level, .low)
        XCTAssertEqual(DevicesModel.batteryText(pct: -3, charging: nil)?.text, "0%")
        XCTAssertEqual(DevicesModel.batteryText(pct: 140, charging: nil)?.text, "100%")
    }

    // MARK: Last seen

    func testLastSeenLine_prefersConnectedThenSyncThenSeen() {
        let twoDaysAgo = Date().timeIntervalSince1970 - 2 * 86_400
        XCTAssertEqual(DevicesModel.lastSeenLine(connected: true, lastSyncedAt: twoDaysAgo, lastSeenAt: 1),
                       "Connected now")
        XCTAssertTrue(DevicesModel.lastSeenLine(connected: false, lastSyncedAt: twoDaysAgo, lastSeenAt: 1)
            .hasPrefix("Last sync "))
        XCTAssertTrue(DevicesModel.lastSeenLine(connected: false, lastSyncedAt: nil, lastSeenAt: Int(twoDaysAgo))
            .hasPrefix("Last seen "))
        XCTAssertEqual(DevicesModel.lastSeenLine(connected: false, lastSyncedAt: nil, lastSeenAt: 0),
                       "Not connected yet")
    }

    func testLastSeenLine_withinAMinuteReadsJustNow() {
        let now = Date().timeIntervalSince1970
        XCTAssertEqual(DevicesModel.lastSeenLine(connected: false, lastSyncedAt: now - 5, lastSeenAt: 0),
                       "Last sync just now")
    }

    // MARK: Next active

    func testNextActiveCandidates_excludeTheForgottenStrap() {
        let a = device("a", peripheralId: "1", status: .active)
        let b = device("b", peripheralId: "2")
        XCTAssertEqual(DevicesModel.nextActiveCandidates(after: a, in: [a, b]).map(\.id), ["b"])
        XCTAssertTrue(DevicesModel.nextActiveCandidates(after: a, in: [a]).isEmpty)
    }
}
