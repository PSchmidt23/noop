#if os(iOS)
import SwiftUI

/// Segmented capsule with a sliding accent selection: ONE look for every segmented control in the app.
/// `.glass` is the pinned control under the navigation bar (`BaselineScreen.pinned`: Trends' 7 / 30 / 90
/// days, Progress' horizons) — ONE `.glassEffect` on the whole control inside ONE `GlassEffectContainer`,
/// never per segment. `.flat` lives inside cards (Journal's outcome, the new-habit kind, Compare's
/// metric / source) on a `fill` track. `label` is the pill text, `accessibilityLabel` the spoken form.
/// Four segments fit at the narrowest supported width. Text on glass is ink, never dependent on the blur.
struct BaselineSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var accessibilityLabel: ((Option) -> String)? = nil
    var style: Style = .glass
    enum Style { case glass, flat }
    @Namespace private var selectionSpace

    var body: some View {
        switch style {
        case .glass:
            GlassEffectContainer(spacing: 4) {
                segments
                    .glassEffect(.regular, in: Capsule())
            }
        case .flat:
            segments
                .background(BaselineTheme.fill, in: Capsule())
                .overlay(Capsule().strokeBorder(BaselineTheme.fillStroke, lineWidth: 1))
        }
    }

    private var segments: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(selection == option ? BaselineTheme.text : BaselineTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(BaselineTheme.accent.opacity(0.14))
                                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel?(option) ?? label(option))
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
    }
}

/// A segment of `BaselineRangePicker`: the short pill text ("30D", "1Y"), the spoken form
/// ("Last 30 days", "Last year") and the shorter text used at accessibility Dynamic Type sizes.
protocol BaselineRangeOption: CaseIterable, Identifiable, Hashable {
    var label: String { get }
    var subtitle: String { get }
    /// Pill text when `dynamicTypeSize.isAccessibilitySize`: four segments of "180D" no longer fit, so
    /// the day suffix goes ("90", "180", "1Y", "All"). Defaults to `label` minus a trailing "D".
    var shortLabel: String { get }
}

extension BaselineRangeOption {
    var shortLabel: String {
        guard label.hasSuffix("D"), label.dropLast().allSatisfy(\.isNumber) else { return label }
        return String(label.dropLast())
    }
}

/// The range control (Trends' 7 / 30 / 90 days, Progress' 90 / 180 / 365 / all): `BaselineSegmentedPicker`
/// over every case, with the verbose `subtitle` for VoiceOver and `shortLabel` at accessibility sizes.
/// `.glass` when pinned under the bar; `.flat` inside a card (Compare).
struct BaselineRangePicker<Option: BaselineRangeOption>: View {
    @Binding var selection: Option
    var style: BaselineSegmentedPicker<Option>.Style = .glass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        BaselineSegmentedPicker(options: Array(Option.allCases), selection: $selection,
                                label: { dynamicTypeSize.isAccessibilitySize ? $0.shortLabel : $0.label },
                                accessibilityLabel: { $0.subtitle },
                                style: style)
    }
}
#endif
