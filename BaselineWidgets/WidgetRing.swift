import SwiftUI

/// A lightweight copy of `MetricRing`'s gauge geometry for the extension: a 270° arc open at the bottom
/// (`Circle().trim(0…0.75)` rotated 135°), a track and a value arc. The fill is the snapshot's
/// pre-computed `hrvRingFraction` (the app's `MetricRingScale` over Home's domain), so the widget never
/// scales a number itself. nil fraction = track only (calibrating or stale), as Home shows it.
struct WidgetRing<Centre: View>: View {
    let fraction: Double?
    let color: Color
    var lineWidth: CGFloat = 8
    @ViewBuilder var centre: () -> Centre

    private static var sweep: Double { 0.75 }
    private static var startAngle: Double { 135 }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Self.sweep)
                .stroke(WidgetPalette.ringTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(Self.startAngle))
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: Self.sweep * min(1, max(0, fraction)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(Self.startAngle))
            }
            centre()
        }
        .padding(lineWidth / 2)
    }
}
