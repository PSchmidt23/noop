#if os(iOS)
import SwiftUI

/// Flat primary action INSIDE content (cards, a sheet's body). HIG: a control inside content is not
/// glass. `prominent` is a `.borderedProminent` capsule tinted accent with a white label (5.2:1);
/// `prominent: false` is a `.bordered` capsule (accent on accent @ 0.10). Text-only tertiary actions
/// stay `.plain` buttons in `textSecondary`. Used by: Today's empty state "Pair strap", Devices "Add
/// strap", Import "Choose a file…", Export "Export", Apple Health "Allow" / "Sync now", Journal's empty
/// state "Add a habit" (`prominent: false`). Labels are the visible text verbatim (UI-test anchors).
struct BaselineCTA: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { BaselineCTALabel(title: title, systemImage: systemImage) }
            .baselineCTAStyle(prominent: prominent)
    }
}

/// `BaselineCTA`'s label (headline, full width, 6pt vertical padding), for a control that is not a plain
/// `Button` but must look like one, e.g. a `ShareLink`:
/// `ShareLink(item: text) { BaselineCTALabel(title: "Share code", systemImage: "square.and.arrow.up") }
/// .baselineCTAStyle()`.
struct BaselineCTALabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(BaselineTheme.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

extension View {
    /// `BaselineCTA`'s look on any button-like control: prominent = `.borderedProminent` capsule tinted
    /// accent with a white label; otherwise `.bordered` capsule (accent on accent @ 0.10). The if/else is
    /// required: the two are different `PrimitiveButtonStyle` types.
    @ViewBuilder func baselineCTAStyle(prominent: Bool = true) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(BaselineTheme.accent)
                .foregroundStyle(BaselineTheme.onAccent)
        } else {
            self.buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(BaselineTheme.accent)
        }
    }
}

/// Glass CTA for an action that FLOATS over the background, never inside a card: Welcome's action
/// column (wrap the column in `GlassEffectContainer(spacing: 12)`) and Home's "Journal" button that
/// opens `JournalSheet` for the selected day. `.glassProminent` (tinted accent, white label) for the one
/// primary action, `.glass` for a secondary one. The if/else is mandatory: `GlassButtonStyle` and
/// `GlassProminentButtonStyle` are different `PrimitiveButtonStyle` types, so no ternary.
/// Only `.glass` / `.glassProminent` (iOS 26.0) are used; `GlassButtonStyle.init(_ glass:)` is 26.1.
/// `fullWidth: false` makes a compact capsule that hugs its label (the floating Journal button).
struct GlassCTA: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = true
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(BaselineTheme.accent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .tint(BaselineTheme.accent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
    }

    private var label: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(BaselineTheme.headline)
        .frame(maxWidth: fullWidth ? .infinity : nil)
    }
}

/// A glyph-only toolbar link: the Settings gear in the top-right of every tab root
/// (`ToolbarItem(placement: .topBarTrailing) { BaselineToolbarLink(systemImage: "gearshape",
/// accessibilityLabel: "Settings") { SettingsScreen() } }`). The toolbar supplies the glass; nothing is
/// added inside. The glyph takes the bar's tint (`accent`, set on the TabView).
struct BaselineToolbarLink<Destination: View>: View {
    let systemImage: String
    let accessibilityLabel: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            Image(systemName: systemImage)
                .font(BaselineTheme.symbolAccessory.weight(.medium))
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The one strap readout outside Settings: Today's `ToolbarItem(placement: .topBarTrailing)`. The
/// toolbar supplies the glass, so there is NO `.glassEffect` inside (glass in glass). Paired: a 6pt dot
/// (connected → good, else `inactive`), the battery percentage (and a bolt while charging) and a sync
/// glyph; the whole pill is the sync button, gated exactly as Settings' "Sync now" (connected AND
/// bonded AND not mid-offload). Not paired: a "Pair" text button that opens the chooser Today owns.
/// Hidden entirely under DEBUG `-baseline.marketing YES`. "Paired" is `live.bonded` or an adopted
/// device in the registry (the registry seeds a placeholder row with no peripheral, so non-empty is
/// not the test), observed directly: `AppModel` does not republish the nested registry's changes.
struct StrapStatusPill: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    let onPair: () -> Void

    /// DEBUG-only: `-baseline.marketing YES` (argument domain) hides the pill so the App Store frame of
    /// Today starts with the date, readiness and rings. Never true in Release.
    private static var hiddenForMarketing: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "baseline.marketing")
        #else
        return false
        #endif
    }

    var body: some View {
        if StrapStatusPill.hiddenForMarketing {
            EmptyView()
        } else if let registry = model.deviceRegistry {
            StrapStatusPillObserved(registry: registry, onPair: onPair)
        } else {
            StrapStatusPillContent(paired: live.bonded, onPair: onPair)
        }
    }

    /// Reads the strap's sync state the way the navigation subtitle says it: " · Synced 2h ago",
    /// " · Syncing…" or " · Not synced yet". Today appends this to its date while a strap is paired.
    static func syncStamp(live: LiveState) -> String {
        if live.backfilling { return "Syncing…" }
        if let ts = live.lastSyncedAt { return "Synced \(relativeAgo(ts))" }
        return "Not synced yet"
    }

    /// The same "paired" test the pill makes, for callers that need it (Today's subtitle and empty state).
    static func isPaired(live: LiveState, registry: DeviceRegistry?) -> Bool {
        live.bonded || (registry?.devices.contains { $0.peripheralId != nil && !$0.isImportSource } ?? false)
    }
}

private struct StrapStatusPillObserved: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var live: LiveState
    let onPair: () -> Void

    var body: some View {
        StrapStatusPillContent(paired: StrapStatusPill.isPaired(live: live, registry: registry), onPair: onPair)
    }
}

private struct StrapStatusPillContent: View {
    let paired: Bool
    let onPair: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    /// The same gate Settings' "Sync now" applies.
    private var canSync: Bool { live.connected && live.bonded && !live.backfilling }

    var body: some View {
        if paired {
            Button {
                model.ble.syncNow()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(live.connected ? BaselineTheme.good : BaselineTheme.inactive)
                        .frame(width: 6, height: 6)
                    if live.connected, let pct = live.batteryPct {
                        Text("\(Int(pct.rounded()))%")
                            .font(BaselineTheme.caption.weight(.semibold))
                            .foregroundStyle(BaselineTheme.text)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if live.charging == true {
                            Image(systemName: "bolt.fill").font(BaselineTheme.symbolSmall)
                                .foregroundStyle(BaselineTheme.textSecondary)
                        }
                    }
                    if live.backfilling {
                        ProgressView().controlSize(.small).tint(BaselineTheme.accent)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(BaselineTheme.symbol)
                            .foregroundStyle(canSync ? BaselineTheme.accent : BaselineTheme.inactive)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .animation(.snappy, value: live.batteryPct)
                .animation(.snappy, value: live.connected)
                .animation(.snappy, value: live.backfilling)
            }
            .buttonStyle(.plain)
            .disabled(!canSync)
            .accessibilityLabel(statusText)
            .accessibilityHint("Syncs the strap")
        } else {
            Button("Pair", action: onPair)
                .buttonStyle(.plain)
                .font(BaselineTheme.caption.weight(.semibold))
                .foregroundStyle(BaselineTheme.text)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .accessibilityHint("Opens the strap chooser")
        }
    }

    /// The former status strip's sentence, now the pill's VoiceOver label ("Connected · 84% · Synced 2h ago").
    private var statusText: String {
        var parts: [String] = [live.connected ? "Connected" : "Not connected"]
        if live.connected, let pct = live.batteryPct {
            parts.append("\(Int(pct.rounded()))%" + (live.charging == true ? " charging" : ""))
        }
        parts.append(StrapStatusPill.syncStamp(live: live))
        return parts.joined(separator: " · ")
    }
}
#endif
