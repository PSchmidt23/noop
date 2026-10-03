#if os(iOS)
import SwiftUI

/// Small display helpers the Friends screens share: day keys and the week they sit in, the words a
/// metric's value is printed with, the neutral trend sentence for physiology, and "Updated …".
/// Nothing here ranks or scores: boards come from `FriendsBoard`, competition scores from the server
/// (or `FriendsScoring` inside the demo backend). Physiology is only ever printed as a person's change
/// against their OWN baseline, never as a raw HRV / heart-rate value.
enum FriendsUI {

    // MARK: Day keys (all through `FriendsDates`, the contract's one day-key calendar)

    /// Today's local day key ("yyyy-MM-dd" in the device's zone).
    static func today(_ now: Date = Date()) -> String { FriendsDates.localKey(now) }

    /// The seven day keys Monday…Sunday of the week containing `now`.
    static func weekKeys(containing now: Date = Date()) -> [String] { FriendsDates.week(containing: today(now)) }

    /// The `n` day keys ending today, oldest first (the "4 weeks" scope is 28).
    static func lastDays(_ n: Int, endingOn now: Date = Date()) -> [String] {
        let end = today(now)
        return FriendsDates.days(from: FriendsDates.adding(-(n - 1), to: end), to: end)
    }

    /// "M", "T", … for a day key.
    static func weekdayLetter(_ key: String) -> String {
        guard let d = FriendsDates.date(key) else { return "" }
        let i = FriendsDates.calendar.component(.weekday, from: d) - 1
        return ["S", "M", "T", "W", "T", "F", "S"][max(0, min(6, i))]
    }

    /// "Mon 6 Oct".
    static func shortDay(_ key: String) -> String {
        guard let d = FriendsDates.date(key) else { return key }
        return FriendsDates.shortDate(d, timeZone: FriendsDates.calendar.timeZone)
    }

    /// "Mon 6 – Sun 12 Oct".
    static func range(_ start: String, _ end: String) -> String { FriendsDates.rangeText(start: start, end: end) }

    /// "Updated today" / "Updated yesterday" / "Updated 3 days ago" from a friend's newest shared day.
    static func updated(lastDay: String?, now: Date = Date()) -> String {
        FriendsDates.updatedText(lastDay: lastDay, today: today(now)) ?? "Nothing shared yet"
    }

    // MARK: Values

    static func number(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    /// A metric's colour in bars and dots (the card text stays ink).
    static func color(_ metric: FriendsMetric) -> Color {
        switch metric {
        case .steps: return BaselineTheme.steps
        case .intensity, .active: return BaselineTheme.effort
        case .sleepGoal, .bedtime: return BaselineTheme.sleep
        case .hrv, .rhr, .readiness: return BaselineTheme.textTertiary   // neutral ink: never a judgement
        }
    }

    /// Chip label (short).
    static func chip(_ metric: FriendsMetric) -> String {
        switch metric {
        case .steps: return "Steps"
        case .intensity: return "Intensity minutes"
        case .active: return "Active days"
        case .sleepGoal: return "Sleep goal"
        case .bedtime: return "Bedtime consistency"
        case .hrv: return "HRV"
        case .rhr: return "Resting HR"
        case .readiness: return "Readiness"
        }
    }

    /// The SF Symbol a metric leads with in rows.
    static func symbol(_ metric: FriendsMetric) -> String {
        switch metric {
        case .steps: return "figure.walk"
        case .intensity: return "flame"
        case .active: return "calendar"
        case .sleepGoal: return "moon.zzz"
        case .bedtime: return "bed.double"
        case .hrv: return "waveform.path.ecg"
        case .rhr: return "heart"
        case .readiness: return "gauge.with.dots.needle.33percent"
        }
    }

    /// One day's value as printed under a bar: "9,010 steps", "42 min", "At goal" / "Missed".
    static func dayValue(_ metric: FriendsMetric, _ value: Int) -> String {
        switch metric {
        case .steps: return "\(number(value)) steps"
        case .intensity: return "\(value) min"
        case .active: return value > 0 ? "Active" : "Not active"
        case .sleepGoal: return value > 0 ? "At sleep goal" : "Under sleep goal"
        case .bedtime: return value > 0 ? "On time" : "Not on time"
        case .hrv, .rhr, .readiness: return ""
        }
    }

    /// A window's total as printed: "52,310 steps", "112 min", "5 of 7 days", "4 of 7 nights".
    static func total(_ metric: FriendsMetric, _ value: Int, days: Int) -> String {
        switch metric {
        case .steps: return "\(number(value)) steps"
        case .intensity: return "\(number(value)) min"
        case .active: return "\(value) of \(days) days"
        case .sleepGoal, .bedtime: return "\(value) of \(days) nights"
        case .hrv, .rhr, .readiness: return ""
        }
    }

    /// A day at the person's OWN goal (`FriendsBoard.dailyGoal`: daily steps, weekly intensity ÷ 7, 1).
    static func atGoal(_ metric: FriendsMetric, value: Int, profile: FriendsProfile) -> Bool {
        value >= FriendsBoard.dailyGoal(metric: metric, profile: profile)
    }

    /// Where a bar block's goal tick sits; nil for the 0/1 metrics, whose bars are simply full or empty.
    static func dailyGoal(_ metric: FriendsMetric, profile: FriendsProfile) -> Double? {
        metric.isDayCount ? nil : Double(FriendsBoard.dailyGoal(metric: metric, profile: profile))
    }

    /// The trend glyph for a pill: an arrow for direction only, never a judgement colour.
    static func trendArrow(_ t: TrendShare) -> String {
        guard t.status == .ready, let d = t.delta else { return "hourglass" }
        return d > 0 ? "arrow.up.right" : (d < 0 ? "arrow.down.right" : "arrow.right")
    }

    /// The newest row per physiology metric, in the fixed order HRV, Resting HR, Readiness: never by value.
    static func latestTrends(_ trends: [TrendShare]) -> [TrendShare] {
        let latest = FriendsBoard.latestTrends(trends)
        return FriendsMetric.physiology.compactMap { latest[$0] }
    }
}

// MARK: - Small shared views

/// An initials circle (no photos in Friends): accent @ 0.10 fill, ink letters.
struct FriendsInitials: View {
    let name: String
    var highlighted = false
    var body: some View {
        Text(DisplayName.initials(name).isEmpty ? "?" : DisplayName.initials(name))
            .font(BaselineTheme.caption.weight(.semibold))
            .foregroundStyle(BaselineTheme.text)
            .frame(width: 32, height: 32)
            .background(BaselineTheme.accent.opacity(highlighted ? 0.22 : 0.10), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Seven (or 28) thin bars with an optional goal tick, flat, hidden from VoiceOver (the row says it).
struct FriendsDayBars: View {
    let values: [Int?]
    let color: Color
    /// The daily goal the tick sits at; nil for 0/1 metrics.
    var goal: Double? = nil
    /// The top of the scale (defaults to the larger of the goal × 1.5 and the biggest value).
    var height: CGFloat = 36
    var capped: Set<Int> = []

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(goal.map { $0 * 1.5 } ?? 1, Double(values.compactMap { $0 }.max() ?? 0), 1)
            let gap: CGFloat = values.count > 10 ? 2 : 4
            let w = max(2, (geo.size.width - gap * CGFloat(values.count - 1)) / CGFloat(max(values.count, 1)))
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        let h = v.map { CGFloat(Double($0) / maxValue) * geo.size.height } ?? 0
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(v == nil ? BaselineTheme.ringTrack : color.opacity(0.90))
                                .frame(width: w, height: v == nil ? 3 : max(3, h))
                                .overlay(alignment: .top) {
                                    if capped.contains(i) {
                                        Capsule().fill(BaselineTheme.watch).frame(width: w, height: 2)
                                    }
                                }
                        }
                    }
                }
                if let goal {
                    let y = geo.size.height - CGFloat(goal / maxValue) * geo.size.height
                    Rectangle()
                        .fill(BaselineTheme.text.opacity(0.35))
                        .frame(height: 1)
                        .offset(y: -(geo.size.height - y))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Mon–Sun goal-day dots: filled = at own goal, hollow = missed, faint = future or no data.
struct FriendsGoalDots: View {
    /// One entry per day: true at goal, false missed, nil no data / future.
    let days: [Bool?]
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                Group {
                    switch d {
                    case true?: Circle().fill(color)
                    case false?: Circle().strokeBorder(color, lineWidth: 1.5)
                    case nil: Circle().fill(BaselineTheme.ringTrack)
                    }
                }
                .frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A neutral physiology pill: direction arrow + "HRV +8 % vs own baseline". Ink on `chipFill`, no
/// judgement colour, never sorted.
struct FriendsTrendPill: View {
    let trend: TrendShare
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: FriendsUI.trendArrow(trend))
                .font(BaselineTheme.symbolSmall)
                .foregroundStyle(BaselineTheme.textTertiary)
                .accessibilityHidden(true)
            Text(FriendsBoard.trendPill(trend))
                .font(BaselineTheme.caption.weight(.medium))
                .foregroundStyle(BaselineTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(BaselineTheme.chipFill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A flat in-card selectable chip (metric / mode / scope choices). Selected = accent @ 0.14 with ink text.
struct FriendsChoiceChip: View {
    let title: String
    let selected: Bool
    var systemImage: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(BaselineTheme.symbolSmall).accessibilityHidden(true)
                }
                Text(title).font(BaselineTheme.label)
            }
            .foregroundStyle(selected ? BaselineTheme.text : BaselineTheme.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(selected ? BaselineTheme.accent.opacity(0.14) : BaselineTheme.chipFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A calm inline error line under a field or an action.
struct FriendsErrorLine: View {
    let error: FriendsError?
    var body: some View {
        if let error {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle").font(BaselineTheme.symbolSmall)
                    .foregroundStyle(BaselineTheme.watch).accessibilityHidden(true)
                Text(error.message).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
#endif
