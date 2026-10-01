#if os(iOS)
import SwiftUI

/// Baseline's design tokens. Dark-first, one teal accent for HRV, a warm coral for resting HR.
/// Keep every colour here; screens never hard-code hex values.
enum BaselineTheme {
    // Surfaces
    static let background = Color(red: 0.043, green: 0.063, blue: 0.125)        // deep navy
    static let backgroundTop = Color(red: 0.070, green: 0.100, blue: 0.190)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.10)

    // Text
    static let text = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.55)        // ≥ 4.5:1 on background and cards (caption text)
    /// Disabled controls and off-state indicators (not connected, not answered). Not for readable text.
    static let inactive = Color.white.opacity(0.40)
    /// The selected-point marker on a chart (the scrubbed night): the text colour, so it reads on every
    /// metric colour without a screen reaching for a literal white.
    static let marker = text

    // Metric colours
    static let accent = Color(red: 0.25, green: 0.88, blue: 0.82)              // HRV teal
    static let hrv = accent
    static let rhr = Color(red: 1.00, green: 0.55, blue: 0.45)                 // resting HR coral
    static let sleep = Color(red: 0.56, green: 0.60, blue: 1.00)               // sleep lavender
    static let effort = Color(red: 1.00, green: 0.78, blue: 0.36)              // effort amber
    static let good = Color(red: 0.40, green: 0.87, blue: 0.56)
    static let watch = Color(red: 1.00, green: 0.72, blue: 0.30)
    static let low = Color(red: 1.00, green: 0.42, blue: 0.42)

    // Sleep stages
    static let stageDeep = Color(red: 0.30, green: 0.36, blue: 0.95)
    static let stageRem = Color(red: 0.62, green: 0.55, blue: 1.00)
    static let stageLight = Color(red: 0.45, green: 0.72, blue: 1.00)
    static let stageWake = Color(red: 1.00, green: 0.70, blue: 0.45)

    static func stageColor(_ stage: String) -> Color {
        switch stage.lowercased() {
        case "deep": return stageDeep
        case "rem": return stageRem
        case "light": return stageLight
        default: return stageWake
        }
    }

    // Heart-rate zones (Z1 easy → Z5 maximal): one intensity ramp of the effort amber, so a zone bar
    // reads as "more effort" as it brightens. Dedicated tokens: `good` / `watch` / `low` stay judgements
    // and the sleep-stage colours stay stages, so neither can be mistaken for a zone.
    static let zone1 = effort.opacity(0.35)
    static let zone2 = effort.opacity(0.50)
    static let zone3 = effort.opacity(0.65)
    static let zone4 = effort.opacity(0.80)
    static let zone5 = effort

    static func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return zone1
        case 2: return zone2
        case 3: return zone3
        case 4: return zone4
        default: return zone5
        }
    }

    // Type
    static func hero(_ size: CGFloat = 56) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
    static let label = Font.system(.subheadline, design: .rounded).weight(.medium)

    // SF Symbols beside text take a text style, never a fixed point size, so an icon grows with the
    // label it sits next to under Dynamic Type.
    /// Chevrons, chip marks and stepper glyphs (≈11pt at the default size).
    static let symbolSmall = Font.system(.caption2, design: .rounded).weight(.semibold)
    /// Row icons beside a label (≈13pt).
    static let symbol = Font.system(.footnote, design: .rounded).weight(.medium)
    /// A card's quiet accessory icon (≈15pt).
    static let symbolAccessory = Font.system(.subheadline, design: .rounded).weight(.light)

    // Layout
    static let gutter: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 18
}

/// Full-screen background used by every Baseline screen.
struct BaselineBackground: View {
    var body: some View {
        LinearGradient(colors: [BaselineTheme.backgroundTop, BaselineTheme.background],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Scroll container with Baseline's background, gutter and spacing. Use for every tab root.
struct BaselineScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, BaselineTheme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .background(BaselineBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .scrollIndicators(.hidden)
    }
}
#endif
