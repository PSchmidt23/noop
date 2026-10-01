#if os(iOS)
import SwiftUI

/// One idea per card. Flat content, soft surface, no glass on content.
struct BaselineCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var accessory: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title { Text(title).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary) }
                        if let subtitle { Text(subtitle).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary) }
                    }
                    Spacer()
                    if let accessory { accessory }
                }
            }
            content
        }
        .padding(BaselineTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BaselineTheme.card, in: RoundedRectangle(cornerRadius: BaselineTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BaselineTheme.cardRadius, style: .continuous)
            .strokeBorder(BaselineTheme.cardStroke, lineWidth: 1))
    }
}

/// Section label between cards.
struct BaselineSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(BaselineTheme.textTertiary)
            .padding(.top, 8)
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

/// The hero number: value, unit, and where it sits versus baseline.
struct MetricHero: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    /// e.g. "+6 ms vs baseline · above your band" or "Baseline after 4 nights · 3 so far". Carries the band
    /// position in words; `bandDot` only echoes it in colour.
    let context: String
    let band: BaselineBand
    /// `true` when a higher value is better (HRV); `false` for resting HR.
    var higherIsBetter: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(BaselineTheme.label).foregroundStyle(BaselineTheme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(BaselineTheme.hero()).foregroundStyle(BaselineTheme.text)
                    .contentTransition(.numericText())
                Text(unit).font(BaselineTheme.headline).foregroundStyle(BaselineTheme.textSecondary)
            }
            HStack(spacing: 6) {
                bandDot
                Text(context).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bandDot: some View {
        let good: Bool? = {
            switch band {
            case .inside: return true
            case .calibrating: return nil
            case .above: return higherIsBetter
            case .below: return !higherIsBetter
            }
        }()
        let c: Color = good == nil ? BaselineTheme.textTertiary : (good! ? BaselineTheme.good : BaselineTheme.watch)
        return Circle().fill(c).frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

/// A compact stat used in rows of two or three.
struct StatCell: View {
    let label: String
    let value: String
    var unit: String? = nil
    var color: Color = BaselineTheme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(color)
                if let unit { Text(unit).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pill used for readiness tier, connection state, confidence.
struct BaselinePill: View {
    let text: String
    var color: Color = BaselineTheme.accent
    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Explains what will appear once there is data. Used by every screen.
struct BaselineEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(BaselineTheme.textTertiary)
            Text(title).font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
            Text(message).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}
#endif
