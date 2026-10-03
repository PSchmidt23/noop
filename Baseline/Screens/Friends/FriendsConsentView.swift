#if os(iOS)
import SwiftUI

/// The per-metric consent list (`consent_version = 1`, FRIENDS_SPEC §7.2): eight rows, each with the exact
/// form that would leave the phone and an Off / Only in competitions / Friends menu (physiology: Off /
/// Friends). Every row starts Off; nothing is pre-ticked. Used by the setup sheet's third step; Settings
/// › Friends & sharing applies the same menus one at a time (`FriendsShareMenu`), each Off → on behind its
/// own "I agree" (`FriendsShareConsentSheet`).
struct FriendsConsentView: View {
    @Binding var shares: [FriendsMetric: ShareAudience]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(FriendsMetric.allCases.enumerated()), id: \.element) { i, metric in
                if i > 0 { SettingsDivider() }
                FriendsShareRow(metric: metric, audience: shares[metric]) { shares[metric] = $0 }
            }
        }
    }
}

/// One metric row: icon tile, title, the exact shared form, and the audience menu (`share-menu-<metric>`).
struct FriendsShareRow: View {
    let metric: FriendsMetric
    let audience: ShareAudience?
    let onChange: (ShareAudience?) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        layout {
            HStack(alignment: .top, spacing: 14) {
                SettingsIconTile(icon: FriendsUI.symbol(metric))
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.title).font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                    Text(metric.sharedForm.prefix(1).uppercased() + metric.sharedForm.dropFirst())
                        .font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            FriendsShareMenu(metric: metric, audience: audience, onChange: onChange)
        }
        .padding(.vertical, 8)
    }
}

/// The Off / Only in competitions / Friends menu for one metric.
struct FriendsShareMenu: View {
    let metric: FriendsMetric
    let audience: ShareAudience?
    let onChange: (ShareAudience?) -> Void

    static func label(_ a: ShareAudience?) -> String {
        a?.title ?? "Off"
    }

    var body: some View {
        Menu {
            Picker(metric.title, selection: Binding(get: { audience }, set: onChange)) {
                Text("Off").tag(ShareAudience?.none)
                ForEach(metric.allowedAudiences, id: \.self) { a in
                    Text(Self.label(a)).tag(Optional(a))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(Self.label(audience))
                    .font(BaselineTheme.label)
                    .foregroundStyle(audience == nil ? BaselineTheme.textSecondary : BaselineTheme.text)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(BaselineTheme.symbolSmall)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(audience == nil ? BaselineTheme.chipFill : BaselineTheme.accent.opacity(0.14), in: Capsule())
        }
        .accessibilityIdentifier("share-menu-\(metric.rawValue)")
        .accessibilityLabel("\(metric.title), shared with")
        .accessibilityValue(Self.label(audience))
    }
}
#endif
