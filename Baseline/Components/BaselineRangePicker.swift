#if os(iOS)
import SwiftUI

/// A segment of `BaselineRangePicker`: the short pill text ("30D", "1Y") and the spoken form
/// ("Last 30 days", "Last year").
protocol BaselineRangeOption: CaseIterable, Identifiable, Hashable {
    var label: String { get }
    var subtitle: String { get }
}

/// Segmented pill with a sliding accent selection. One style for every screen that picks a window
/// (Trends' 7 / 30 / 90 days, Progress' 90 / 180 / 365 / all), so a range control reads the same
/// wherever it appears. Four segments fit at the narrowest supported width.
struct BaselineRangePicker<Option: BaselineRangeOption>: View {
    @Binding var selection: Option
    @Namespace private var selectionSpace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Option.allCases)) { option in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = option }
                } label: {
                    Text(option.label)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(selection == option ? BaselineTheme.accent : BaselineTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(BaselineTheme.accent.opacity(0.16))
                                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.subtitle)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(BaselineTheme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(BaselineTheme.cardStroke, lineWidth: 1))
    }
}
#endif
