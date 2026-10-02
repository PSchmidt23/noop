import WidgetKit
import SwiftUI

/// One entry backed by the last `BaselineWidgetSnapshot` the app wrote into the App Group.
struct BaselineWidgetEntry: TimelineEntry {
    let date: Date
    /// nil = nothing published yet (the "Open Baseline to sync" state); never sample numbers outside the gallery.
    let snapshot: BaselineWidgetSnapshot?
}

/// Shared by both widgets. A single-entry timeline: the app reloads every timeline when it publishes, so
/// no schedule is needed, but `.after(6h)` stays as a safety net for a snapshot that lands while the app is
/// backgrounded (its publisher is foreground-only). A `.never` policy would leave such a glance stale until
/// the next foreground visit.
struct BaselineWidgetProvider: TimelineProvider {
    static let safetyReloadHours = 6

    func placeholder(in context: Context) -> BaselineWidgetEntry {
        BaselineWidgetEntry(date: Date(), snapshot: .gallery)
    }

    func getSnapshot(in context: Context, completion: @escaping (BaselineWidgetEntry) -> Void) {
        let fallback: BaselineWidgetSnapshot? = context.isPreview ? .gallery : nil
        completion(BaselineWidgetEntry(date: Date(), snapshot: BaselineWidgetStore.load() ?? fallback))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BaselineWidgetEntry>) -> Void) {
        let entry = BaselineWidgetEntry(date: Date(), snapshot: BaselineWidgetStore.load())
        let next = Calendar.current.date(byAdding: .hour, value: Self.safetyReloadHours, to: Date())
            ?? Date().addingTimeInterval(TimeInterval(Self.safetyReloadHours * 3600))
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension BaselineWidgetSnapshot {
    /// Gallery / placeholder stand-in only (`context.isPreview`): plausible numbers so the arcs preview
    /// filled. Never shown as real data.
    static var gallery: BaselineWidgetSnapshot {
        var s = BaselineWidgetSnapshot(dayKey: "2026-02-18", generatedAt: Date())
        s.hrvMs = 64; s.hrvDay = s.dayKey; s.hrvBaselineMs = 60; s.hrvBandLowMs = 54; s.hrvBandHighMs = 66
        s.hrvRingFraction = 0.58; s.hrvDeltaText = "+4 ms vs baseline · inside your band"; s.hrvBandPosition = "inside"
        s.rhrBpm = 52; s.rhrBaselineBpm = 53; s.rhrDeltaText = "−1 bpm vs baseline · inside your band"; s.rhrBandPosition = "inside"
        s.readinessLabel = "On baseline"; s.readinessColorName = "accent"
        s.sleepMinutes = 432; s.sleepAverageMinutes = 414; s.sleepDay = s.dayKey
        return s
    }
}

// MARK: - Shared formatting (the extension's copies of `BaselineReadouts.durationText` / `signedDurationText`)

enum WidgetFormat {
    static func whole(_ v: Double?) -> String {
        guard let v else { return "–" }
        return "\(Int(v.rounded()))"
    }

    /// "6h 42m"; "42 min" under an hour (`BaselineReadouts.durationText(minutes:)`).
    static func duration(minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        return m < 60 ? "\(m) min" : "\(m / 60)h " + String(format: "%02d", m % 60) + "m"
    }

    /// "+22 min vs average" / "−1h 05m vs average" / "On your average" (`SleepFormat.deltaText`, steady
    /// inside ±5 min as `BaselineReadouts.durationSteadyMin`).
    static func sleepDelta(minutes: Double, average: Double?) -> String? {
        guard let average else { return nil }
        let m = Int((minutes - average).rounded())
        guard abs(m) >= 5 else { return "On your average" }
        return (m < 0 ? "\u{2212}" : "+") + duration(minutes: Double(abs(m))) + " vs average"
    }
}

/// The honest empty state every family shows before the first publish.
struct WidgetEmptyView: View {
    var compact = false
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: compact ? 14 : 20, weight: .light, design: .rounded))
                .foregroundStyle(compact ? AnyShapeStyle(.secondary) : AnyShapeStyle(WidgetPalette.textTertiary))
            Text("Open Baseline to sync")
                .font(compact ? WidgetPalette.caption2 : WidgetPalette.caption)
                .foregroundStyle(compact ? AnyShapeStyle(.primary) : AnyShapeStyle(WidgetPalette.textSecondary))
                .multilineTextAlignment(.center)
        }
    }
}
