import SwiftUI

/// The extension's copy of the few `BaselineTheme` tokens a widget needs. `BaselineTheme` lives in the app
/// target (it pulls SwiftUI views and the engine along), so the literals are repeated here, by name, from
/// `Baseline/Components/BaselineTheme.swift`; a token changed there must be changed here. Light only,
/// like the app: a Home Screen widget sits on a white card, the Lock Screen renders `.vibrant`
/// (`.primary` / `.secondary`, never a tint).
enum WidgetPalette {
    private static func hex(_ v: UInt32, _ opacity: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: opacity)
    }

    /// `BaselineTheme.card`: the widget's container background.
    static let card = hex(0xFFFFFF)
    /// `BaselineTheme.text` / `textSecondary` / `textTertiary`.
    static let text = hex(0x111827)
    static let textSecondary = hex(0x4B5563)
    static let textTertiary = hex(0x5F6B7B)
    /// `BaselineTheme.ringTrack`.
    static let ringTrack = hex(0xE9EBF1)
    /// `BaselineTheme.accent` (= `hrv`), `rhr`, `sleep`.
    static let accent = hex(0x0D7A72)
    static let hrv = accent
    static let rhr = hex(0xC8412A)
    static let sleep = hex(0x4A4FD0)
    /// `BaselineTheme.good` / `watch` / `low`: the three Readiness tones (`ReadinessBar`'s colours).
    static let good = hex(0x15803D)
    static let watch = hex(0xC2410C)
    static let low = hex(0xB91C1C)
    /// `BaselineTheme.onAccent`: the label on a filled readiness pill.
    static let onAccent = hex(0xFFFFFF)

    /// `BaselineWidgetSnapshot.readinessToneName` → colour (the tokens `ReadinessBar` uses for a tone).
    static func named(_ name: String?) -> Color {
        switch name {
        case "good": return good
        case "watch": return watch
        case "low": return low
        case "accent": return accent
        default: return textTertiary
        }
    }

    /// The 6pt dot before a context line, `TodayRingTile.tone`'s rule: inside → good; above / below →
    /// good or watch by the metric's direction; calibrating or stale → tertiary.
    static func tone(bandPosition: String?, higherIsBetter: Bool) -> Color {
        switch bandPosition {
        case "inside": return good
        case "above": return higherIsBetter ? good : watch
        case "below": return higherIsBetter ? watch : good
        default: return textTertiary
        }
    }

    // MARK: Type (SF Rounded, `BaselineTheme`'s tokens at widget sizes)
    static func hero(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static let stat = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let label = Font.system(.subheadline, design: .rounded).weight(.medium)
    static let caption = Font.system(.footnote, design: .rounded)
    static let caption2 = Font.system(.caption2, design: .rounded)
}
