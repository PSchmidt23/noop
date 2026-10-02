import Foundation

/// The glance the widgets draw, published by the app into the shared App Group as one small JSON file.
///
/// Compiled into BOTH the app and the `BaselineWidgets` extension (listed in both targets' sources in
/// project.yml), so this file imports only Foundation: no NOOP package, no SwiftUI, no engine type. The
/// extension stays tiny and never opens the SQLite store. Everything here is pre-resolved by the app from
/// the SAME funnels Home draws (`TodaySnapshot` over `repo.baselineDays` / `repo.baselineNights()`,
/// `MetricRingScale` for the arc, `BaselineBand.positionPhrase` and `ReadinessTier.baselineLabel` for the
/// words), so a widget and the Home tab behind it cannot disagree. The builder that does that lives in
/// `BaselineWidgetPublisher.swift` (app target only; it needs the engine).
///
/// Every value field is optional so a snapshot written by an older build still decodes (Codable fills a
/// missing optional with nil), the discipline NOOP's `WidgetSnapshot` follows.
struct BaselineWidgetSnapshot: Codable, Equatable {
    /// Bumped when the meaning of a field changes; the widget shows the empty state for an unknown version.
    static let currentVersion = 1
    var version: Int = currentVersion

    /// The local day the snapshot was built for (`Repository.localDayKey(now)`).
    var dayKey: String

    // MARK: HRV (the headline)
    /// Last night's HRV in ms, nil while calibrating-with-no-night or once the night is older than the
    /// carry cap (Home then shows "–" too).
    var hrvMs: Double?
    /// The morning the HRV night is dated to; differs from `dayKey` for a carried value.
    var hrvDay: String?
    var hrvBaselineMs: Double?
    var hrvBandLowMs: Double?
    var hrvBandHighMs: Double?
    /// 0…1 fill of the 270° gauge, `MetricRingScale.fraction` over `MetricRingScale.domain` (baseline ± 3σ),
    /// the same arc Home's HRV tile draws. nil = track only (calibrating or stale).
    var hrvRingFraction: Double?
    /// The ONE context line under the number, Home's words verbatim: "+6 ms vs baseline · above your
    /// band", "On your baseline · inside your band", "Baseline after 4 nights · 2 so far", "No night since
    /// Mon 28 Sep", "Waiting for the first night".
    var hrvDeltaText: String?
    /// "inside" / "above" / "below"; nil while calibrating or stale. The widget tones the context dot with it.
    var hrvBandPosition: String?

    // MARK: Resting HR
    var rhrBpm: Double?
    var rhrBaselineBpm: Double?
    var rhrDeltaText: String?
    var rhrBandPosition: String?

    // MARK: Readiness (the seven-night tier)
    /// `ReadinessTier.baselineLabel` ("Primed" / "On baseline" / "Below your range"); nil while
    /// calibrating or stale.
    var readinessLabel: String?
    /// The `BaselineTheme` token the tier wears on Home: "good" / "accent" / "watch". The extension maps
    /// the name to its own literal copy of the colour (`WidgetPalette`).
    var readinessColorName: String?
    /// While calibrating: valid nights so far out of `HRVReadiness.minNights` (14).
    var readinessCalibratingNights: Int?

    // MARK: Sleep (last night)
    var sleepMinutes: Double?
    /// `BaselineReadouts.sleepAverage30(before:in:)`, the 30 nights before last night; nil until three exist.
    var sleepAverageMinutes: Double?
    var sleepDay: String?

    // MARK: Provenance
    /// `live.lastSyncedAt` as a Date, nil when the strap has never synced in this install.
    var lastSyncedAt: Date?
    var generatedAt: Date

    // MARK: Equality that ignores the clock

    /// Whether anything a widget renders differs. `generatedAt` is excluded on purpose: every build has a
    /// fresh timestamp, and treating it as content would make the publish dedup useless (NOOP's
    /// `renderedContentChanged` rule).
    func rendersSame(as other: BaselineWidgetSnapshot) -> Bool {
        var a = self, b = other
        a.generatedAt = .distantPast
        b.generatedAt = .distantPast
        return a == b
    }

    /// Nothing to draw yet: no night, no readiness. The widgets show "Open Baseline to sync".
    var isEmpty: Bool {
        hrvMs == nil && rhrBpm == nil && sleepMinutes == nil && readinessLabel == nil
    }
}

// MARK: - Store (App Group JSON file)

/// Where the snapshot lives and how both processes reach it. The app writes, the extension reads; each
/// resolves the container from its OWN Info.plist (`AppGroupIdentifier`, injected from the
/// `APP_GROUP_ID` build setting on both targets, NOOP's `WidgetSnapshot.suiteName` pattern), so the group
/// id is spelled in project.yml only. Both targets' entitlements carry the same
/// `com.apple.security.application-groups` value; if either is missing, `containerURL` is nil and the
/// store silently no-ops, which the DEBUG `assertGroupProvisioned` canary catches on the first run.
enum BaselineWidgetStore {
    static let fileName = "baseline-widget-snapshot.json"
    /// Only reached when the Info.plist key is absent; project.yml sets it on both targets.
    static let fallbackGroup = "group.com.patrickschmidt.baseline"

    static let appGroupID: String = {
        resolveAppGroupID(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }()

    static func resolveAppGroupID(infoDictionary: [String: Any]) -> String {
        let configured = (infoDictionary["AppGroupIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? fallbackGroup : configured
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    static func assertGroupProvisioned() {
        assert(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil,
               "App Group '\(appGroupID)' not provisioned on this target; check the entitlement.")
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func encode(_ snapshot: BaselineWidgetSnapshot) throws -> Data { try encoder.encode(snapshot) }
    static func decode(_ data: Data) throws -> BaselineWidgetSnapshot { try decoder.decode(BaselineWidgetSnapshot.self, from: data) }

    /// The last-published snapshot, or nil when none has been written or it does not decode. A snapshot
    /// from a newer `version` than this build understands is treated as absent rather than misread.
    static func load() -> BaselineWidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snap = try? decode(data), snap.version <= BaselineWidgetSnapshot.currentVersion else { return nil }
        return snap
    }

    /// Writes atomically so the extension never reads a half-written file. Returns false when the group
    /// container is unavailable or the write failed.
    @discardableResult
    static func save(_ snapshot: BaselineWidgetSnapshot) -> Bool {
        guard let url = fileURL, let data = try? encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

// MARK: - Deep link

/// The one URL scheme the app registers (`CFBundleURLTypes` in project.yml's Baseline block). Every
/// widget tap opens `home`; `BaselineRoot` consumes it with `.onOpenURL`.
enum BaselineDeepLink {
    static let scheme = "baseline"
    static let home = URL(string: "baseline://home")!

    enum Destination: Equatable { case home, trends, sleep }

    /// `baseline://home` → `.home`, `baseline://trends`, `baseline://sleep`; nil for any other scheme or
    /// host, so a stray URL never moves the tabs.
    static func destination(for url: URL) -> Destination? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        switch url.host?.lowercased() {
        case "home": return .home
        case "trends": return .trends
        case "sleep": return .sleep
        default: return nil
        }
    }
}
