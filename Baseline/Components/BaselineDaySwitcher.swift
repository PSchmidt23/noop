#if os(iOS)
import SwiftUI

/// Home's day-by-day control: "‹  Wednesday 1 October  ›". The selected day is a calendar day (`Date`,
/// normalised to `startOfDay`); the trailing chevron is disabled on `latest` (today: no future days) and
/// the leading one on `earliest` (the first stored night) when one is given. `.glass` is the pinned row
/// under the navigation bar (`BaselineScreen.pinned`): ONE `.glassEffect` capsule around the whole
/// control, text in ink. `.flat` sits on the page or in a card (`fill` track). Pair it with
/// `.baselineDaySwipe(previous:next:)` on the screen so a horizontal swipe over the cards moves a day too.
struct BaselineDaySwitcher: View {
    @Binding var selection: Date
    /// The earliest day that can be shown (nil: no lower bound).
    var earliest: Date? = nil
    /// The latest day that can be shown; defaults to today. Never a future day.
    var latest: Date = Date()
    var style: Style = .glass
    /// The centre text; defaults to `BaselineDaySwitcher.title(for:)` ("Today" / "Yesterday" / "Wednesday 1 October").
    var title: ((Date) -> String)? = nil
    enum Style { case glass, flat }

    private var calendar: Calendar { Calendar.current }
    private var day: Date { calendar.startOfDay(for: selection) }
    private var canGoBack: Bool { earliest.map { day > calendar.startOfDay(for: $0) } ?? true }
    private var canGoForward: Bool { day < calendar.startOfDay(for: latest) }

    var body: some View {
        switch style {
        case .glass:
            GlassEffectContainer(spacing: 4) {
                row.glassEffect(.regular, in: Capsule())
            }
        case .flat:
            row
                .background(BaselineTheme.fill, in: Capsule())
                .overlay(Capsule().strokeBorder(BaselineTheme.fillStroke, lineWidth: 1))
        }
    }

    private var row: some View {
        HStack(spacing: 4) {
            chevron("chevron.left", enabled: canGoBack, label: "Previous day") { step(-1) }
            Text(title?(day) ?? Self.title(for: day))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(BaselineTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)
            chevron("chevron.right", enabled: canGoForward, label: "Next day") { step(1) }
        }
        .padding(4)
        .animation(.snappy(duration: 0.25), value: day)
    }

    private func chevron(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(BaselineTheme.symbol.weight(.semibold))
                .foregroundStyle(enabled ? BaselineTheme.text : BaselineTheme.inactive)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func step(_ days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        if days < 0, !canGoBack { return }
        if days > 0, !canGoForward { return }
        selection = next
    }

    /// The day's name as Home prints it: "Today", "Yesterday", else "Wednesday 1 October" (the weekday,
    /// day and month, the same form Today's date line used). `now` is injectable for tests.
    static func title(for day: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day)
        let today = cal.startOfDay(for: now)
        if d == today { return "Today" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: today), d == yesterday { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// A horizontal swipe over scrolling content: left (finger moves right-to-left) → `next`, right → `previous`.
/// Simultaneous with the scroll view's own drag and ignored unless the gesture is clearly horizontal
/// (|dx| ≥ 48pt and more than twice |dy|), so vertical scrolling and chart scrubbing are untouched. Put it
/// on `BaselineScreen`'s content (Home) beside a `BaselineDaySwitcher`, which stays the discoverable control.
struct BaselineDaySwipe: ViewModifier {
    let previous: () -> Void
    let next: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) >= 48, abs(dx) > abs(dy) * 2 else { return }
                    if dx < 0 { next() } else { previous() }
                }
        )
    }
}

extension View {
    /// See `BaselineDaySwipe`.
    func baselineDaySwipe(previous: @escaping () -> Void, next: @escaping () -> Void) -> some View {
        modifier(BaselineDaySwipe(previous: previous, next: next))
    }
}
#endif
