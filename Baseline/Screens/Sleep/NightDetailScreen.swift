#if os(iOS)
import SwiftUI

/// One night, pushed from the Nights list: the same ring and stages the tab shows for last night, the
/// strap's heart rate while asleep (`SleepHeartRateCard`, absent for a night without times), plus the
/// night's vitals (resting HR, HRV, breathing, skin temperature), which live here only.
struct NightDetailScreen: View {
    let night: SleepNight
    /// `BaselineReadouts.sleepAverage30(before:in:)` for this night, for the ring's context line.
    let average: Double?

    var body: some View {
        BaselineScreen(title: SleepFormat.dayLabel(night.dayDate)) {
            // The navigation title already names the day, so the hero does not repeat it.
            SleepHeroCard(title: "Night", night: night, average: average, showsDayLabel: false)
            SleepHypnogramCard(night: night)
            SleepHeartRateCard(night: night)
            if night.hasVitals {
                SleepVitalsCard(night: night)
            }
        }
    }
}
#endif
