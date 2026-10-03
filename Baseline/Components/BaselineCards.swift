#if os(iOS)
import SwiftUI

/// One idea per card. Opaque white, 28pt continuous corners, ONE soft shadow, no stroke, no glass:
/// cards are content, and content stays flat so the glass chrome has something to refract.
struct BaselineCard<Content: View>: View {
    var title: String? = nil
    /// Kept for API compatibility (Data / Devices / Workouts / Compare pass one); restyled screens pass nil.
    var subtitle: String? = nil
    var accessory: AnyView? = nil
    /// 20 by default; ring tiles use 16.
    var padding: CGFloat = BaselineTheme.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil || accessory != nil {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title { Text(title).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary) }
                        if let subtitle { Text(subtitle).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary) }
                    }
                    Spacer(minLength: 8)
                    if let accessory { accessory }
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BaselineTheme.card, in: BaselineTheme.cardShape)
        .shadow(color: BaselineTheme.cardShadow, radius: 16, x: 0, y: 6)
    }
}

/// Section label between cards (`.flat`), or the pinned glass capsule a `Section` header uses inside
/// `BaselineScreen` (`.glass`, Settings only: a pinned header floats over scrolled rows).
struct BaselineSectionLabel: View {
    let text: String
    var style: Style = .flat
    enum Style { case flat, glass }

    var body: some View {
        switch style {
        case .flat:
            Text(text.uppercased())
                .font(BaselineTheme.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(BaselineTheme.textTertiary)
                .padding(.top, 8)
        case .glass:
            HStack {
                Text(text.uppercased())
                    .font(BaselineTheme.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(BaselineTheme.text)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }
}

/// Status of a value against the person's own baseline.
enum BaselineBand {
    case above, inside, below, calibrating

    /// The one phrase for a band position wherever a screen or notification names it ("inside your
    /// band"); nil while calibrating, when there is no band to be inside of.
    var positionPhrase: String? {
        switch self {
        case .inside: return "inside your band"
        case .above: return "above your band"
        case .below: return "below your band"
        case .calibrating: return nil
        }
    }
}

/// A compact stat used in rows of two or three. The value is `BaselineTheme.stat`; pass `dot:` for a
/// colour the value must not carry as text (sleep stages: value in ink, a 6pt stage dot before the label).
struct StatCell: View {
    let label: String
    let value: String
    var unit: String? = nil
    var color: Color = BaselineTheme.text
    var dot: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6).accessibilityHidden(true) }
                Text(label).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                // One line, never "1,25 / 0": a four-digit value with its unit in a quarter-width cell
                // (Calories' Latest / Average / Low / High) shrinks a little instead of breaking.
                Text(value).font(BaselineTheme.stat).monospacedDigit().foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit {
                    Text(unit).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                        .lineLimit(1).fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element: "Efficiency, 92 %", never the label and the value as two swipes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? value)
    }
}

/// A row of three (or more) `StatCell`s: side by side by default, a two-column grid at accessibility
/// Dynamic Type sizes, where a third column (~100pt) would break "132 bpm" between its digits.
struct BaselineStatRow<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      alignment: .leading, spacing: 14) { content }
        } else {
            HStack(alignment: .top, spacing: 12) { content }
        }
    }
}

/// Pill for a readiness tier, a trend, a confidence, a connection or battery state. The text is always
/// INK with a 6pt dot in `color` (coloured text on its own tint measures 4.3–4.5:1; ink keeps ≥ 15:1).
/// `.flat` inside cards (colour @ 0.10 capsule); `.glass` is chrome only, never inside a card.
struct BaselinePill: View {
    let text: String
    var color: Color = BaselineTheme.accent
    var style: Style = .flat
    enum Style { case flat, glass }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch style {
        case .flat:
            label
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(color.opacity(0.10), in: Capsule())
        case .glass:
            label
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassEffect(.regular, in: Capsule())
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(text)
                .font(BaselineTheme.caption.weight(.semibold))
                .foregroundStyle(BaselineTheme.text)
                // Hosts move the pill under the title at accessibility sizes; two lines is the last resort.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
    }
}

/// Explains what will appear once there is data. Used by every screen.
struct BaselineEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(BaselineTheme.accent)
                .frame(width: 56, height: 56)
                .background(BaselineTheme.accent.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
            Text(title).font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
            Text(message).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}

/// A one-line link row at the foot of a card ("All workouts", the Progress headline): caption text, a
/// trailing chevron, the whole row tappable. The visible label is `text` verbatim, so a UI test's
/// `buttons["All workouts"]` still resolves.
struct BaselineChevronRow<Destination: View>: View {
    let text: String
    /// Leading glyph in accent (Readiness → Progress passes "chart.line.uptrend.xyaxis").
    var systemImage: String? = nil
    var dot: Color? = nil
    var accessibilityHint: String? = nil
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(BaselineTheme.symbol).foregroundStyle(BaselineTheme.accent)
                        .accessibilityHidden(true)
                } else if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6).accessibilityHidden(true)
                }
                Text(text)
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(BaselineTheme.symbolSmall)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .modifier(OptionalAccessibilityHint(hint: accessibilityHint))
    }
}

/// `.accessibilityHint` only when one was given.
struct OptionalAccessibilityHint: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint { content.accessibilityHint(hint) } else { content }
    }
}
#endif
