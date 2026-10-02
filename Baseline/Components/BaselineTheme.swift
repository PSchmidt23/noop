#if os(iOS)
import SwiftUI

/// Hex literal for a design token (`Color(baselineHex: 0xF4F5F8)`). Only this file spells a colour;
/// screens and components read `BaselineTheme.*`.
fileprivate extension Color {
    init(baselineHex: UInt32, opacity: Double = 1) {
        self.init(red: Double((baselineHex >> 16) & 0xFF) / 255,
                  green: Double((baselineHex >> 8) & 0xFF) / 255,
                  blue: Double(baselineHex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Baseline's design tokens: flat light paper, white cards carrying the data, glass only on the chrome
/// that floats above content. One teal accent for HRV, a coral for resting HR. Keep every colour here;
/// screens never hard-code hex values. Contrast figures are WCAG 2.1 against white (cards) / #F4F5F8.
enum BaselineTheme {
    // MARK: Surfaces
    /// Cool off-white paper; also the launch screen.
    static let background = Color(baselineHex: 0xF4F5F8)
    /// Top of `BaselineBackground`'s wash (a near-flat gradient so glass chrome has something to refract).
    static let backgroundTop = Color(baselineHex: 0xF7F8FB)
    /// Bottom of `BaselineBackground`'s wash.
    static let backgroundBottom = Color(baselineHex: 0xF2F3F7)
    /// Card surface. Opaque white: text on a card never depends on what sits beneath.
    static let card = Color(baselineHex: 0xFFFFFF)
    /// The ONE shadow a card carries (`.shadow(color: cardShadow, radius: 16, x: 0, y: 6)`). Never on
    /// rows or chips.
    static let cardShadow = Color(baselineHex: 0x111827, opacity: 0.06)
    /// Dividers inside cards. Chart grid lines use `hairline.opacity(0.75)`.
    static let hairline = Color(baselineHex: 0x111827, opacity: 0.08)
    /// Unfilled ring arc: a track, not information.
    static let ringTrack = Color(baselineHex: 0xE9EBF1)
    /// The "no"-state chip fill inside a white card.
    static let chipFill = Color(baselineHex: 0xF4F5F8)
    /// Flat segmented-picker track inside a card.
    static let fill = Color(baselineHex: 0x111827, opacity: 0.04)
    /// Stroke around `fill`.
    static let fillStroke = Color(baselineHex: 0x111827, opacity: 0.08)

    // MARK: Text
    /// Ink. 17.7:1 on white, 16.3:1 on the background.
    static let text = Color(baselineHex: 0x111827)
    /// 7.6:1 / 6.9:1.
    static let textSecondary = Color(baselineHex: 0x4B5563)
    /// ALL caption text, axis labels, section labels, chevrons, footnotes. 5.4:1 / 5.0:1.
    static let textTertiary = Color(baselineHex: 0x5F6B7B)
    /// NON-TEXT ONLY (2.5:1): disabled glyphs, the unanswered-chip stroke, the not-connected dot.
    static let inactive = Color(baselineHex: 0x9CA3AF)
    /// The scrubbed chart point's fill; it takes a 2pt stroke in the metric colour
    /// (`BaselineChartStyle.selectedPoint`).
    static let marker = Color.white
    /// Label on a filled accent control (5.2:1 on `accent`, 5.0:1 on `good`).
    static let onAccent = Color(baselineHex: 0xFFFFFF)

    // MARK: Metric colours (each ≥ 4.5:1 on white; coloured text lives INSIDE white cards only)
    /// Teal. 5.2:1 / 4.8:1. The one accent: it tints the prominent CTA and every selected control.
    static let accent = Color(baselineHex: 0x0D7A72)
    static let hrv = accent
    /// Coral. 5.0:1 / 4.5:1.
    static let rhr = Color(baselineHex: 0xC8412A)
    /// Indigo. 6.3:1 / 5.8:1.
    static let sleep = Color(baselineHex: 0x4A4FD0)
    /// Amber. 5.0:1 / 4.6:1.
    static let effort = Color(baselineHex: 0xB45309)
    /// Violet. 6.9:1 / 6.3:1. The Stress curve's line and area (daytime, not a judgement).
    static let stress = Color(baselineHex: 0x6D28D9)
    /// Slate blue. 6.3:1 / 5.8:1. Steps bars and the steps numeral's dot.
    static let steps = Color(baselineHex: 0x1D4ED8)
    static let good = Color(baselineHex: 0x15803D)      // 5.0 / 4.6
    static let watch = Color(baselineHex: 0xC2410C)     // 5.2 / 4.8
    static let low = Color(baselineHex: 0xB91C1C)       // 6.5 / 5.9

    // MARK: Sleep stages (fills, swatches and 6pt dots only; never text: light 2.1:1, wake 1.8:1)
    static let stageDeep = Color(baselineHex: 0x312E81)
    static let stageRem = Color(baselineHex: 0x6D5BD0)
    static let stageLight = Color(baselineHex: 0x8FB3F2)
    static let stageWake = Color(baselineHex: 0xF0B37E)

    /// The spoken / printed name of a stage key ("deep" -> "Deep", "rem" -> "REM", "wake" -> "Awake").
    static func stageName(_ stage: String) -> String {
        switch stage.lowercased() {
        case "deep": return "Deep"
        case "rem": return "REM"
        case "light": return "Light"
        default: return "Awake"
        }
    }

    static func stageColor(_ stage: String) -> Color {
        switch stage.lowercased() {
        case "deep": return stageDeep
        case "rem": return stageRem
        case "light": return stageLight
        default: return stageWake
        }
    }

    // MARK: Heart-rate zones (Z1 easy → Z5 maximal): one intensity ramp of the effort amber, so a zone
    // bar reads as "more effort" as it darkens. `good` / `watch` / `low` stay judgements and the sleep
    // stages stay stages, so neither can be mistaken for a zone.
    static let zone1 = effort.opacity(0.30)
    static let zone2 = effort.opacity(0.45)
    static let zone3 = effort.opacity(0.60)
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

    // MARK: Type (SF Rounded everywhere; exactly these tokens, nothing ad hoc)
    /// Ring numerals (44 in Today's rings, 36 for a duration numeral); Welcome keeps 54 / 34. Scales with
    /// Dynamic Type on the large-title curve, capped at 1.5x so a numeral still fits its ring (the ring
    /// also grows at accessibility sizes); without the cap AX5 would put a 77pt "7h 24m" in a 168pt ring.
    static func hero(_ size: CGFloat = 44) -> Font {
        .system(size: scaled(size, textStyle: .largeTitle, maxFactor: 1.5), weight: .semibold, design: .rounded)
    }
    /// `size` scaled by the Dynamic Type setting on `textStyle`'s curve, never beyond `maxFactor` x.
    private static func scaled(_ size: CGFloat, textStyle: UIFont.TextStyle, maxFactor: CGFloat) -> CGFloat {
        min(UIFontMetrics(forTextStyle: textStyle).scaledValue(for: size), size * maxFactor)
    }
    /// 22 semibold. Welcome only.
    static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    /// 20 semibold: every StatCell value, the Journal day number, effect deltas, timing-grid values.
    /// Scales with Dynamic Type on the title3 curve, so a value never ends up smaller than its caption.
    static var stat: Font {
        .system(size: scaled(20, textStyle: .title3, maxFactor: 1.6), weight: .semibold, design: .rounded)
    }
    /// 17 semibold.
    static let headline = Font.system(.headline, design: .rounded)
    /// 17.
    static let body = Font.system(.body, design: .rounded)
    /// 15 medium: card titles, chips, row titles.
    static let label = Font.system(.subheadline, design: .rounded).weight(.medium)
    /// 13: every secondary line, axis labels, section labels.
    static let caption = Font.system(.footnote, design: .rounded)

    // SF Symbols beside text take a text style, never a fixed point size, so an icon grows with the
    // label it sits next to under Dynamic Type.
    /// Chevrons, chip marks and stepper glyphs (≈11pt at the default size).
    static let symbolSmall = Font.system(.caption2, design: .rounded).weight(.semibold)
    /// Row icons beside a label (≈13pt).
    static let symbol = Font.system(.footnote, design: .rounded).weight(.medium)
    /// A card's quiet accessory icon (≈15pt).
    static let symbolAccessory = Font.system(.subheadline, design: .rounded).weight(.light)

    // MARK: Layout
    static let gutter: CGFloat = 20
    static let cardRadius: CGFloat = 28
    static let cardPadding: CGFloat = 20
    static let cardSpacing: CGFloat = 14
    static let ringLineWidth: CGFloat = 10
    /// Today's rings; the Sleep hero ring is 168 with a 12pt line.
    static let ringSize: CGFloat = 128
    static var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: cardRadius, style: .continuous) }
}

/// Full-screen background used by every Baseline screen: a near-flat wash from `backgroundTop` to
/// `backgroundBottom`, so the glass chrome above it has a gradient to refract.
struct BaselineBackground: View {
    var body: some View {
        LinearGradient(colors: [BaselineTheme.backgroundTop, BaselineTheme.backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Scroll container with Baseline's background, gutter and spacing. Use for every tab root and pushed
/// screen. The content is a `LazyVStack(pinnedViews: [.sectionHeaders])`, so a `Section { } header: { }`
/// inside it pins its header (Settings). `pinned` is the one-row bar under the navigation bar
/// (`safeAreaBar(edge: .top)`): Home's day switcher, Trends' section control. `subtitle` becomes the
/// navigation subtitle (Home's sync stamp, the journal sheet's night label). No `.toolbarColorScheme`: the bars are the system's glass.
struct BaselineScreen<Content: View, Pinned: View>: View {
    let title: String
    var titleMode: NavigationBarItem.TitleDisplayMode = .large
    var subtitle: String? = nil
    private let hasPinned: Bool
    @ViewBuilder var pinned: () -> Pinned
    @ViewBuilder var content: () -> Content

    init(title: String, titleMode: NavigationBarItem.TitleDisplayMode = .large, subtitle: String? = nil,
         @ViewBuilder pinned: @escaping () -> Pinned, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.titleMode = titleMode
        self.subtitle = subtitle
        self.hasPinned = true
        self.pinned = pinned
        self.content = content
    }

    fileprivate init(title: String, titleMode: NavigationBarItem.TitleDisplayMode, subtitle: String?,
                     hasPinned: Bool, pinned: @escaping () -> Pinned, content: @escaping () -> Content) {
        self.title = title
        self.titleMode = titleMode
        self.subtitle = subtitle
        self.hasPinned = hasPinned
        self.pinned = pinned
        self.content = content
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BaselineTheme.cardSpacing, pinnedViews: [.sectionHeaders]) {
                content()
            }
            .padding(.horizontal, BaselineTheme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(BaselineBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(titleMode)
        .modifier(BaselineNavigationSubtitle(subtitle: subtitle))
        .modifier(BaselinePinnedBar(hasPinned: hasPinned, pinned: pinned))
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollIndicators(.hidden)
    }
}

extension BaselineScreen where Pinned == EmptyView {
    /// A screen with nothing pinned under the bar (every screen but Home and Trends).
    init(title: String, titleMode: NavigationBarItem.TitleDisplayMode = .large, subtitle: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, titleMode: titleMode, subtitle: subtitle, hasPinned: false,
                  pinned: { EmptyView() }, content: content)
    }
}

/// `.navigationSubtitle` only when there is one (an `if` on the chain, never a ternary over two views).
private struct BaselineNavigationSubtitle: ViewModifier {
    let subtitle: String?
    func body(content: Content) -> some View {
        if let subtitle {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

/// The one-row glass bar under the navigation bar, only when the screen asked for it.
private struct BaselinePinnedBar<Pinned: View>: ViewModifier {
    let hasPinned: Bool
    let pinned: () -> Pinned
    func body(content: Content) -> some View {
        if hasPinned {
            content.safeAreaBar(edge: .top, spacing: 0) {
                pinned()
                    .padding(.horizontal, BaselineTheme.gutter)
                    .padding(.vertical, 6)
            }
        } else {
            content
        }
    }
}
#endif
