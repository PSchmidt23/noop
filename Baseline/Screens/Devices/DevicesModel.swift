#if os(iOS)
import Foundation
import WhoopStore

/// Pure helpers behind `DevicesScreen`: which registry rows are straps worth showing, what a card calls
/// them, and the words for a battery level or a last-seen stamp. No store, Bluetooth or SwiftUI, so the
/// rules are unit-tested in `DevicesModelTests`.
enum DevicesModel {

    /// The straps the Devices screen lists, in the registry's order (oldest paired first).
    ///
    /// NOOP's store seeds a placeholder row (`my-whoop`, model "WHOOP", no peripheral) so the engine has a
    /// device id before any strap exists; it is not a strap and must not read as one. A row counts once
    /// the engine has adopted a peripheral for it, or while it is the active row and a bond is live (the
    /// peripheral id lands a beat after the first connect). Removed rows and anything that is not a WHOOP
    /// (an Apple Watch registration, an import source) stay out: Baseline only pairs straps.
    static func visibleStraps(_ devices: [PairedDevice], liveBonded: Bool) -> [PairedDevice] {
        devices.filter { d in
            guard d.status != .archived, SourceIdentity.isWhoop(d), !d.isImportSource else { return false }
            return d.peripheralId != nil || (d.status == .active && liveBonded)
        }
    }

    /// The generation printed after "WHOOP" from the registry's model string ("WHOOP 4.0",
    /// "WHOOP 5.0 / MG", or the seed's bare "WHOOP"). `liveVariant` is `LiveState.whoop5Variant`
    /// ("MG" / "5.0" / "—") for the connected strap, which settles a 5-generation row into the one it
    /// really is; nil (or "—") leaves the pair. nil when the row does not say.
    static func modelLabel(_ model: String, liveVariant: String? = nil) -> String? {
        let m = model.lowercased()
        if m.contains("4.0") { return "4.0" }
        if m.contains("5.0") || m.contains("mg") {
            switch liveVariant {
            case "MG": return "MG"
            case "5.0": return "5.0"
            default: return "5.0 / MG"
            }
        }
        return nil
    }

    /// The card's first line: the nickname when the person gave one, else the model ("WHOOP 4.0"), else
    /// a plain "WHOOP strap" for a row that has not said its generation yet.
    static func cardTitle(_ device: PairedDevice, liveVariant: String? = nil) -> String {
        if let nickname = device.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
            return nickname
        }
        return fullModelName(device, liveVariant: liveVariant) ?? "WHOOP strap"
    }

    /// The model under a nickname ("WHOOP 4.0"); nil when the title already is the model, so a card never
    /// prints the same words twice.
    static func cardSubtitle(_ device: PairedDevice, liveVariant: String? = nil) -> String? {
        guard let nickname = device.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty
        else { return nil }
        return fullModelName(device, liveVariant: liveVariant)
    }

    /// "WHOOP 4.0" / "WHOOP 5.0 / MG" / "WHOOP MG"; nil when the generation is unknown.
    static func fullModelName(_ device: PairedDevice, liveVariant: String? = nil) -> String? {
        modelLabel(device.model, liveVariant: liveVariant).map { "WHOOP \($0)" }
    }

    /// Battery bands for the pill colour: ≤ 20 % low, ≤ 40 % watch, else good. Same edges as the strap
    /// card on Settings, so the two never disagree about one reading.
    enum BatteryLevel { case low, watch, good }

    static func batteryLevel(_ pct: Int) -> BatteryLevel {
        pct <= 20 ? .low : (pct <= 40 ? .watch : .good)
    }

    /// "Charging · 72 %" / "72 %", clamped to 0…100 and rounded; nil without a reading.
    static func batteryText(pct: Double?, charging: Bool?) -> (text: String, level: BatteryLevel)? {
        guard let pct else { return nil }
        let n = max(0, min(100, Int(pct.rounded())))
        let text = charging == true ? "Charging · \(n)%" : "\(n)%"
        return (text, batteryLevel(n))
    }

    /// The one line under a card's name: what the engine knows about when the strap was last heard
    /// from. Connected wins; the active strap's last history pull next; otherwise the registry's
    /// last-seen stamp, which NOOP writes on a real connect or disconnect. A stamp of 0 (never) reads as
    /// "Not connected yet".
    static func lastSeenLine(connected: Bool, lastSyncedAt: TimeInterval?, lastSeenAt: Int) -> String {
        if connected { return "Connected now" }
        if let ts = lastSyncedAt {
            return "Last sync \(relative(Date(timeIntervalSince1970: ts)))"
        }
        guard lastSeenAt > 0 else { return "Not connected yet" }
        return "Last seen \(relative(Date(timeIntervalSince1970: TimeInterval(lastSeenAt))))"
    }

    /// The straps that could take over once `removed` is forgotten: every other visible strap. Empty
    /// when nothing remains, in which case no prompt is shown and no strap is active.
    static func nextActiveCandidates(after removed: PairedDevice, in visible: [PairedDevice]) -> [PairedDevice] {
        visible.filter { $0.id != removed.id }
    }

    /// Relative phrase ("2 hr. ago", "yesterday"), the same style the Settings strap card prints.
    private static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}
#endif
