#if os(iOS)
import SwiftUI

/// Version, attribution, privacy policy, license and the disclaimer. The LICENSE file is read from the
/// bundle when it ships as a resource; otherwise the short notice with links stands in.
struct SettingsAboutCard: View {
    @State private var showPrivacy = false
    @State private var showLicense = false
    @State private var showDisclaimer = false

    private static let sourceURL = URL(string: "https://github.com/ryanbr/noop")!
    /// The privacy policy as a hosted page (Baseline/PRIVACY.md in the fork, rendered by GitHub). App
    /// Review wants a link to it in the app, and App Store Connect wants the same URL in its
    /// privacy-policy field; `SettingsLegalText.privacy` carries the same text for reading offline.
    static let privacyURL = URL(string: "https://github.com/PSchmidt23/noop/blob/main/Baseline/PRIVACY.md")!

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
            Button(action: { showPrivacy = true }) {
                SettingsRowLabel(icon: "lock.shield", title: "Privacy policy",
                                 subtitle: "Local only, no accounts, no telemetry") { chevron }
            }
            .buttonStyle(.plain)
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
        .sheet(isPresented: $showPrivacy) {
            SettingsTextSheet(title: "Privacy policy", text: SettingsLegalText.privacy, link: Self.privacyURL)
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

/// A scrollable sheet of plain text with a Done button. `link` is the same text hosted online, offered
/// under it; nil for texts that only live in the app.
struct SettingsTextSheet: View {
    let title: String
    let text: String
    var link: URL? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(text)
                        .font(BaselineTheme.body)
                        .foregroundStyle(BaselineTheme.textSecondary)
                        .textSelection(.enabled)
                    if let link {
                        Link(destination: link) {
                            HStack(spacing: 6) {
                                Text("Read online at \(link.host(percentEncoded: false) ?? link.absoluteString)")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(BaselineTheme.label)
                            .foregroundStyle(BaselineTheme.accent)
                        }
                    }
                }
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

    /// Mirrors Baseline/PRIVACY.md (the hosted page behind `SettingsAboutCard.privacyURL`); keep the two
    /// in step when either changes.
    static let privacy = """
    Effective 30 September 2026.

    Baseline is a free, local-only iPhone app for WHOOP 4.0, 5.0 and MG straps, developed by Patrick Schmidt as a personal, non-commercial project on top of NOOP's open-source engine. It has no account, no sign-in, no server, no analytics, no crash reporting, no advertising and no telemetry. Baseline makes no network connections. The developer cannot see your data and never receives it.

    What Baseline stores, and where. Baseline keeps the data it reads from your strap over Bluetooth (heart rate, R-R intervals, battery and sensor records), the metrics it computes from that data (HRV, resting heart rate, readiness, sleep and effort), your journal entries, your profile (age, sex, height, weight and maximum heart rate) and anything you choose to import from a WHOOP or Apple Health export. All of it lives in a database inside the app's own storage on your iPhone, encrypted at rest by iOS. It is part of your iPhone backups like any other app data, and of nothing else. Nothing is sent to the developer, to WHOOP, or to anyone.

    Apple Health. Only when you allow it, Baseline reads sleep, workouts and heart data from Apple Health and writes back the metrics it computes. This happens on your iPhone only. Baseline never sends Apple Health data anywhere, never shares it with third parties and never uses it for advertising or marketing. You can change or withdraw access at any time in the Health app under your profile › Apps › Baseline.

    Bluetooth. Baseline connects to a strap you own and reads data from it. It does not talk to WHOOP's servers or to your WHOOP account.

    Imports. Files you choose to import (a WHOOP data export or an Apple Health export) are read on your iPhone and never uploaded.

    Permissions. Baseline asks only for Bluetooth, to reach your strap, and, if you choose, Apple Health. It does not use your location, motion data, microphone or camera.

    Deleting your data. Delete the app and everything it stored on your iPhone is gone. Metrics Baseline wrote to Apple Health stay there until you delete them in the Health app. A paired strap can be removed under Settings › Devices.

    Changes. When Baseline changes what it stores, this policy changes with it. The current version is always in the app under Settings › About and at the page linked below.

    Contact. Questions go to the project's issue tracker: github.com/PSchmidt23/noop/issues
    """

    static let disclaimer = """
    Baseline is an independent, unofficial, non-commercial project. It is not affiliated with, endorsed by, sponsored by, or connected to WHOOP, Inc. in any way. "WHOOP" is used only to identify the third-party hardware this software works with, never to imply origin, sponsorship or endorsement. Use it only with a device you own, and do not use it in breach of any agreement that applies to you.

    Not a medical device. Heart rate, HRV, resting heart rate, readiness, sleep stages, effort and every other number Baseline shows are approximations computed from published methods. They are not clinically validated, are not a medical device, and are not medical advice. Do not use them to diagnose, treat, or make health decisions. Consult a qualified professional.

    The software is provided as-is, with no warranty of any kind, express or implied. You use it entirely at your own risk, including any risk to your device, data, or warranty status. The authors accept no liability for any damage, loss, or consequence arising from its use.

    Everything stays on your iPhone: there is no account, no server and no telemetry. When you allow it, Baseline reads from and writes to Apple Health on this device only.
    """
}
#endif
