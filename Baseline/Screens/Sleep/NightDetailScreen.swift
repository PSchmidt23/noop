#if os(iOS)
import SwiftUI

/// One night, pushed from the Nights list: the same hero, stages and vitals the tab shows for last night.
struct NightDetailScreen: View {
    let night: SleepNight
    /// Average asleep minutes over the latest 30 nights, for the hero's comparison pill.
    let average: Double?

    var body: some View {
        BaselineScreen(title: SleepFormat.dayLabel(night.dayDate)) {
            SleepHeroCard(title: "Night", night: night, average: average)
            SleepHypnogramCard(night: night)
            if night.hasVitals {
                SleepVitalsCard(night: night)
            }
        }
    }
}
#endif
