#if os(iOS)
import SwiftUI

/// Version, attribution, license and the disclaimer. The LICENSE file is read from the bundle when it
/// ships as a resource; otherwise the short notice with links stands in.
struct SettingsAboutCard: View {
    @State private var showLicense = false
    @State private var showDisclaimer = false

    private static let sourceURL = URL(string: "https://github.com/ryanbr/noop")!

    var body: some View {
        BaselineCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Baseline").font(BaselineTheme.headline).foregroundStyle(BaselineTheme.text)
                Text(Self.versionLine).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
            }
            Text("Built on NOOP, the open-source, local-only strap engine by ryanbr and contributors. Baseline keeps NOOP's engine unchanged and adds its own screens.")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsDivider()
            Link(destination: Self.sourceURL) {
                SettingsRowLabel(icon: "chevron.left.forwardslash.chevron.right", title: "NOOP on GitHub",
                                 subtitle: "github.com/ryanbr/noop") {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BaselineTheme.textTertiary)
                }
            }
            SettingsDivider()
            Button(action: { showLicense = true }) {
                SettingsRowLabel(icon: "doc.text", title: "License",
                                 subtitle: "PolyForm Noncommercial 1.0.0") { chevron }
            }
            .buttonStyle(.plain)
            SettingsDivider()
            Button(action: { showDisclaimer = true }) {
                SettingsRowLabel(icon: "cross.case", title: "Disclaimer",
                                 subtitle: "Not medical advice") { chevron }
            }
            .buttonStyle(.plain)
            SettingsDivider()
            Text("Not affiliated with WHOOP. Free, no accounts, nothing leaves your iPhone.")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showLicense) {
            SettingsTextSheet(title: "License", text: SettingsLegalText.license)
        }
        .sheet(isPresented: $showDisclaimer) {
            SettingsTextSheet(title: "Disclaimer", text: SettingsLegalText.disclaimer)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BaselineTheme.textTertiary)
    }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        if let build = info?["CFBundleVersion"] as? String { return "Version \(version) (\(build))" }
        return "Version \(version)"
    }
}

/// A scrollable sheet of plain text with a Done button.
struct SettingsTextSheet: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(BaselineTheme.body)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BaselineTheme.gutter)
                    .padding(.bottom, 24)
            }
            .background(BaselineBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(BaselineTheme.accent)
        .presentationDragIndicator(.visible)
    }
}

enum SettingsLegalText {
    /// The repository's LICENSE when it ships in the bundle; the short notice otherwise.
    static var license: String {
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.isEmpty {
            return text
        }
        return licenseNotice
    }

    static let licenseNotice = """
    Baseline is built on NOOP and is licensed under the PolyForm Noncommercial License 1.0.0.

    Required Notice: Copyright 2026 NoopApp

    In short: free for personal and other non-commercial use. Read it, run it, fork it, and contribute. Commercial use is not granted by this license. The license covers NOOP's and Baseline's original work only; protocol facts are uncopyrightable, and bundled dependencies keep their own licenses (GRDB.swift and ZIPFoundation are MIT).

    Full terms: https://polyformproject.org/licenses/noncommercial/1.0.0

    Source: https://github.com/ryanbr/noop
    """

    static let disclaimer = """
    Baseline is an independent, unofficial, non-commercial project. It is not affiliated with, endorsed by, sponsored by, or connected to WHOOP, Inc. in any way. "WHOOP" is used only to identify the third-party hardware this software works with, never to imply origin, sponsorship or endorsement. Use it only with a device you own, and do not use it in breach of any agreement that applies to you.

    Not a medical device. Heart rate, HRV, resting heart rate, readiness, sleep stages, effort and every other number Baseline shows are approximations computed from published methods. They are not clinically validated, are not a medical device, and are not medical advice. Do not use them to diagnose, treat, or make health decisions. Consult a qualified professional.

    The software is provided as-is, with no warranty of any kind, express or implied. You use it entirely at your own risk, including any risk to your device, data, or warranty status. The authors accept no liability for any damage, loss, or consequence arising from its use.

    Everything stays on your iPhone: there is no account, no server and no telemetry. When you allow it, Baseline reads from and writes to Apple Health on this device only.
    """
}
#endif
