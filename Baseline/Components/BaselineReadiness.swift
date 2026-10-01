#if os(iOS)
import SwiftUI
import StrandAnalytics

/// One vocabulary for the HRV readiness tier wherever a screen names it: Today's pill, the Trends strip,
/// its legend and VoiceOver. A screen that wants a full sentence ("HRV is lower than usual…") keeps its
/// own copy; the short label and the colour come from here so the two tabs can never disagree.
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
}
#endif
