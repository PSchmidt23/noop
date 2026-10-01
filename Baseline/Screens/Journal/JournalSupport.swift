#if os(iOS)
import SwiftUI

// Small, view-free helpers shared by the Journal screen: day arithmetic for the picker, short chip
// labels for the catalog's long question strings, and the wrapping chip layout.

/// Day keys and labels for the journal picker. Follows NOOP's convention: an answer stored under
/// day D describes the evening and night leading into morning D, so today's key is "last night".
enum JournalDay {
    /// Oldest → newest, today at the trailing end.
    static let offsets: [Int] = Array((0...6).reversed())

    /// `now` is the screen's held "today" (`JournalScreen.today`, rolled on `.NSCalendarDayChanged`), so
    /// every chip, key and caption on one render agrees about which day is offset 0.
    static func date(offset: Int, now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -offset, to: now) ?? now
    }

    static func key(offset: Int, now: Date = Date()) -> String { Repository.localDayKey(date(offset: offset, now: now)) }

    /// Chip headline: the weekday ("Tue"). The chips are equal-width, so the longer "Last night" /
    /// "Yesterday" words live in `caption(offset:)` under the strip instead.
    static func title(offset: Int, now: Date = Date()) -> String { weekday.string(from: date(offset: offset, now: now)) }

    static func dayNumber(offset: Int, now: Date = Date()) -> String { dayOfMonth.string(from: date(offset: offset, now: now)) }

    /// One line under the picker naming the selected night and the morning its answers lead into.
    static func caption(offset: Int, now: Date = Date()) -> String {
        let morning = long.string(from: date(offset: offset, now: now))
        switch offset {
        case 0: return "Last night \u{00B7} the evening and night leading into \(morning)."
        case 1: return "Yesterday \u{00B7} the evening and night leading into \(morning)."
        default: return "The evening and night leading into \(morning)."
        }
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE"); return f
    }()
    private static let dayOfMonth: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d"); return f
    }()
    private static let long: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE d MMM"); return f
    }()
}

/// Short chip labels. The catalog's canonical strings are full questions ("Did you drink any
/// alcohol?") and must stay verbatim as engine keys; the chips show a short form instead.
enum JournalLabels {
    private static let starters: [String: String] = [
        "Did you drink any alcohol?": "Alcohol",
        "Did you have caffeine late in the day?": "Late caffeine",
        "Did you view a screen in bed?": "Screen in bed",
        "Did you eat close to bedtime?": "Late meal",
        "Did you feel stressed?": "Stressed",
        "Did you use a sauna?": "Sauna",
        "Did you share your bed?": "Shared bed",
        "Did you feel sick or ill?": "Sick",
        "Did you take magnesium?": "Magnesium",
        "Did you read before bed?": "Read in bed",
    ]

    private static let normalisedStarters: [String: String] = {
        var out: [String: String] = [:]
        for (k, v) in starters { out[JournalCatalogStore.norm(k)] = v }
        return out
    }()

    /// Short label for a canonical question: the starter table, else the question with its
    /// "Did you …?" frame stripped.
    static func short(_ canonical: String) -> String {
        if let s = normalisedStarters[JournalCatalogStore.norm(canonical)] { return s }
        var t = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("?") || t.hasSuffix(".") { t.removeLast() }
        for prefix in ["did you ", "have you ", "were you ", "do you "] where t.lowercased().hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
            break
        }
        guard let first = t.first else { return canonical }
        return first.uppercased() + t.dropFirst()
    }

    /// "4" for whole numbers, "4.5" otherwise.
    static func magnitude(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    /// Signed whole-number delta with a real minus sign: "+5 ms", "−7 bpm", "0 ms".
    static func signedDelta(_ delta: Double, unit: String) -> String {
        let n = Int(delta.rounded())
        if n == 0 { return unit.isEmpty ? "0" : "0 \(unit)" }
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return (n > 0 ? "+" : "\u{2212}") + "\(abs(n))" + suffix
    }
}

/// A left-aligned wrapping row of chips. Each subview keeps its natural size; rows break when the
/// next chip would overflow the proposed width.
struct BaselineFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                              proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            widest = max(widest, x - spacing)
        }
        let w = width.isFinite ? width : widest
        return (CGSize(width: w, height: y + rowHeight), origins)
    }
}
#endif
