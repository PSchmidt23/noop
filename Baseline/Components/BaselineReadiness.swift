#if os(iOS)
import SwiftUI
import StrandAnalytics

/// One vocabulary for the HRV readiness tier wherever a screen names it: Today's pill and sentence, the
/// Trends strip, its legend, the morning summary's subtitle and VoiceOver. The tier is a SEVEN-night
/// reading (`HRVReadiness.baseline7Ms` against the longer normal range), so every phrase here says
/// "week": a week "on baseline" and a single night "above your band" (the hero tile) are then two facts
/// about two spans, not a contradiction.
extension ReadinessTier {
    /// Pill and legend label.
    var baselineLabel: String {
        switch self {
        case .primed: return "Primed"
        case .normal: return "On baseline"
        case .suppressed: return "Below your range"
        }
    }

    var baselineColor: Color {
        switch self {
        case .primed: return BaselineTheme.good
        case .normal: return BaselineTheme.accent
        case .suppressed: return BaselineTheme.watch
        }
    }

    /// The sentence under Today's pill: explicitly about the last seven nights, so it cannot read against
    /// the one-night delta on the HRV tile.
    var baselineWeekSentence: String {
        switch self {
        case .primed: return "Your week is primed. The last seven nights of HRV run above your usual range; a good day to push."
        case .normal: return "Your week is on baseline. The last seven nights of HRV sit where they usually do."
        case .suppressed: return "Your week is below your normal range. The last seven nights of HRV run low; go gently today."
        }
    }

    /// The morning summary's subtitle: the tier never appears without its noun.
    var baselineNotificationSubtitle: String { "Readiness · \(baselineLabel)" }
}
#endif
