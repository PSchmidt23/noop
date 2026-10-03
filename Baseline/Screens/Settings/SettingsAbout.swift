#if os(iOS)
import SwiftUI

/// Version, attribution, privacy policy, license, open-source notices, the disclaimer and the accuracy
/// review (`AccuracyScreen`, pushed). LICENSE, NOTICE and ATTRIBUTION.md are read from the bundle (they
/// ship as resources of the Baseline target); should one be missing, a short notice with links stands in.
struct SettingsAboutCard: View {
    @State private var showPrivacy = false
    @State private var showLicense = false
    @State private var showNotices = false
    @State private var showDisclaimer = false

    private static let sourceURL = URL(string: "https://github.com/ryanbr/noop")!
    /// The fork itself: Baseline's screens, this file included, next to NOOP's engine.
    private static let baselineSourceURL = URL(string: "https://github.com/PSchmidt23/noop")!
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
                        .font(BaselineTheme.symbolSmall)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            SettingsDivider()
            Link(destination: Self.baselineSourceURL) {
                SettingsRowLabel(icon: "chevron.left.forwardslash.chevron.right", title: "Baseline source",
                                 subtitle: "github.com/PSchmidt23/noop") {
                    Image(systemName: "arrow.up.right")
                        .font(BaselineTheme.symbolSmall)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            SettingsDivider()
            Button(action: { showPrivacy = true }) {
                SettingsRowLabel(icon: "lock.shield", title: "Privacy policy",
                                 subtitle: "Local first, no telemetry; Friends is optional") { chevron }
            }
            .buttonStyle(.plain)
            SettingsDivider()
            Button(action: { showLicense = true }) {
                SettingsRowLabel(icon: "doc.text", title: "License",
                                 subtitle: "PolyForm Noncommercial 1.0.0") { chevron }
            }
            .buttonStyle(.plain)
            SettingsDivider()
            Button(action: { showNotices = true }) {
                SettingsRowLabel(icon: "shippingbox", title: "Open-source notices",
                                 subtitle: "Credits and dependency licenses") { chevron }
            }
            .buttonStyle(.plain)
            SettingsDivider()
            Button(action: { showDisclaimer = true }) {
                SettingsRowLabel(icon: "cross.case", title: "Disclaimer",
                                 subtitle: "Not medical advice") { chevron }
            }
            .buttonStyle(.plain)
            SettingsDivider()
            // The evidence tier behind every metric (`MetricAccuracy`), with the studies linked.
            SettingsLinkRow(icon: "checkmark.seal", title: "How accurate is this?",
                            subtitle: "Every metric's evidence tier, with the studies") {
                AccuracyScreen()
            }
            SettingsDivider()
            Text("Not affiliated with WHOOP. Free, no telemetry. Nothing leaves your iPhone unless you share it in Friends.")
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
        .sheet(isPresented: $showNotices) {
            SettingsTextSheet(title: "Open-source notices", text: SettingsLegalText.notices)
        }
        .sheet(isPresented: $showDisclaimer) {
            SettingsTextSheet(title: "Disclaimer", text: SettingsLegalText.disclaimer)
        }
    }

    private var chevron: some View { SettingsChevron() }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        if let build = info?["CFBundleVersion"] as? String { return "Version \(version) (\(build))" }
        return "Version \(version)"
    }
}

/// A scrollable sheet of plain text with a Done button. `link` is the same text hosted online, offered
/// under it; nil for texts that only live in the app. System sheet chrome (its bar is the glass), a flat
/// body on `BaselineBackground`; no colour-scheme override.
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
                                Image(systemName: "arrow.up.right").accessibilityHidden(true)
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
        bundledText("LICENSE") ?? licenseNotice
    }

    static let licenseNotice = """
    Baseline is built on NOOP and is licensed under the PolyForm Noncommercial License 1.0.0.

    Required Notice: Copyright 2026 NoopApp

    In short: free for personal and other non-commercial use. Read it, run it, fork it, and contribute. Commercial use is not granted by this license. The license covers NOOP's and Baseline's original work only; protocol facts are uncopyrightable, and bundled dependencies keep their own licenses (GRDB.swift, ZIPFoundation, swift-markdown-ui and NetworkImage are MIT; swift-cmark is BSD-2-Clause). See Open-source notices for the full text.

    Full terms: https://polyformproject.org/licenses/noncommercial/1.0.0

    NOOP source: https://github.com/ryanbr/noop
    Baseline source: https://github.com/PSchmidt23/noop
    """

    /// NOOP's NOTICE and ATTRIBUTION.md as shipped in the bundle, followed by the notices for the
    /// packages the Baseline target links that NOOP's NOTICE does not list. NOTICE is a NOOP file and
    /// is never edited in the fork, so the supplement lives here.
    static var notices: String {
        var parts: [String] = []
        if let notice = bundledText("NOTICE") { parts.append(notice) }
        if let attribution = bundledText("ATTRIBUTION", extension: "md") { parts.append(attribution) }
        if parts.isEmpty {
            parts.append("NOOP's NOTICE and ATTRIBUTION.md are not in this build. Read them at https://github.com/ryanbr/noop.")
        }
        parts.append(thirdPartyNotices)
        return parts.joined(separator: "\n\n" + String(repeating: "—", count: 24) + "\n\n")
    }

    /// Copyright and permission notices for every third-party package compiled into Baseline, as the
    /// MIT and BSD licenses require. Versions are the ones pinned in Package.resolved.
    static let thirdPartyNotices = """
    Baseline — third-party notices

    Besides NOOP's engine, this app contains the following open-source packages, used under their own licenses. Their copyright and permission notices are reproduced below.

    GRDB.swift (groue/GRDB.swift) — MIT
      Copyright (C) 2015-2024 Gwendal Roué
      SQLite persistence.

    ZIPFoundation (weichsel/ZIPFoundation) — MIT
      Copyright (c) 2017-2025 Thomas Zoechling (https://www.peakstep.com)
      Reading WHOOP and Apple Health export archives during import.

    swift-markdown-ui (gonzalezreal/swift-markdown-ui) — MIT
      Copyright (c) 2020 Guillermo Gonzalez
      Markdown rendering, linked by NOOP's engine.

    NetworkImage (gonzalezreal/NetworkImage) — MIT
      Copyright (c) 2020 Guille Gonzalez
      A dependency of swift-markdown-ui.

    swift-cmark (swiftlang/swift-cmark) — BSD 2-Clause
      Copyright (c) 2014, John MacFarlane. All rights reserved.
      CommonMark parsing, a dependency of swift-markdown-ui. Parts of cmark are derived from MIT-licensed code: houdini (Copyright (C) 2012 Vicent Martí), buffer (Copyright (C) 2012 GitHub, Inc.) and utf8proc (Copyright (C) 2009 Public Software Group e. V., Berlin, Germany).

    The MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

    The BSD 2-Clause License (swift-cmark)

    Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    """

    /// A text file shipped at the bundle root, or nil when it is absent or empty.
    private static func bundledText(_ name: String, extension ext: String? = nil) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    /// Mirrors Baseline/PRIVACY.md (the hosted page behind `SettingsAboutCard.privacyURL`); keep the two
    /// in step when either changes.
    static let privacy = """
    Effective 2 October 2026.

    Baseline is a free iPhone app for WHOOP 4.0, 5.0 and MG straps, made by Patrick Schmidt as a personal, non-commercial project on NOOP's open-source engine.

    Local first; Friends is optional. Everything in Baseline works without an account, and nothing you do in Home, Trends, Sleep or the journal is sent anywhere. The one exception is Friends, an optional tab. Only if you sign in to it with Apple and turn a metric on does Baseline send that metric, in a reduced form, to Baseline's server so friends you accept can see it. Every metric is off until you turn it on.

    What stays on your iPhone. Baseline stores what it reads from your strap over Bluetooth (heart rate, R-R intervals, battery and sensor records), the numbers it computes from that (HRV, resting heart rate, readiness, sleep and effort), your journal, your profile and any WHOOP or Apple Health export you choose to import. All of it lives in the app's own storage on your iPhone, protected by iOS, and is included in your normal iPhone backups. The developer never sees it.

    Apple Health. Only if you allow it, Baseline reads sleep, workouts, steps and heart data from Apple Health and writes back the metrics it computes. That exchange happens on your iPhone. Baseline never sends Apple Health data anywhere, with one exception you control: if you share Steps in Friends and your iPhone counted the day's steps, that daily total is sent, marked "iPhone". Apple Health data is never used for advertising or marketing and never sold. You can change or withdraw access at any time in the Health app under your profile › Apps › Baseline.

    Bluetooth. Baseline talks only to a strap you own, directly over Bluetooth. It does not contact WHOOP's servers or your WHOOP account.

    Friends (optional)

    Signing in. Friends uses Sign in with Apple. Baseline asks Apple for no name and no email; Apple shares only an identifier unique to Baseline's developer, and the server gives you a user ID. You then type a display name (2 to 24 characters; the only thing about you friends see besides what you share) and confirm you are 16 or older. Your daily step goal and weekly intensity goal are stored with it, so friends and competitions can score against your own goal.

    What is sent, and only what you turn on. Each metric is Off, Only in competitions, or Friends; Off is the default. When you turn one on, you agree to it on that screen.

    • Steps: your daily step count and whether the strap or iPhone counted it.
    • Intensity minutes: your daily minutes, counted against your own heart rate.
    • Active days: whether a day had 20+ intensity minutes or a 20-minute workout.
    • Nights at sleep goal: whether a night reached your own sleep goal; never hours or times.
    • On-time bedtimes: whether bedtime was within 30 minutes of your target; never the time.
    • HRV trend: weekly HRV change against your own baseline, for example +8 %; never your HRV.
    • Resting HR trend: weekly change against your own baseline, for example −2 bpm; never your heart rate.
    • Readiness trend: this week against your month, for example +4; never your score.

    Never sent: heart rate, R-R intervals, your HRV, resting heart rate or readiness values, sleep hours, stages or clock times, calories, stress, effort, workouts, the journal, location, your email, contacts or photos. Friends has no chat and no free text.

    Why. Only to show what you chose to the friends you accept, or only inside competitions you join, and to score those competitions. For health data, the legal basis is your explicit consent (EU GDPR Art. 9(2)(a)), given per metric and never pre-ticked; for your account (user ID, name, goals), it is providing the Friends service you asked for (Art. 6(1)(b)).

    Where. Baseline's server runs on Supabase (Supabase, Inc.) in its Frankfurt, EU region. Supabase processes it for Baseline under its data processing agreement, which covers any access from outside the EU with the EU Standard Contractual Clauses. Everything travels over HTTPS. Your sign-in session is kept in your iPhone's Keychain, on this device only, never in iCloud.

    Who sees it. Friends you accept see your name, your goals and what you share with Friends, except friends you hide your data from (they are not told). A pending friend request shows your name. People in a competition you join see your name and your score in that competition only. Someone holding an invite code you made sees your name before connecting. HRV, resting HR and readiness are only ever shown as your change against your own baseline, listed alphabetically, never ranked and never in a competition. The developer can open the server's tables to run Friends and act on reports, and does so only for that. Nothing is sold or shared with anyone else.

    How long it is kept.

    • Daily values: 35 days.
    • HRV, resting HR and readiness trends: the current week plus 4 previous weeks.
    • Invite codes: 7 days (deleted a day after they expire).
    • Competitions and their results: 90 days after the competition ends.
    • Reports: 12 months.
    • Accounts not used for 13 months are deleted with everything in them.
    • The record of what you agreed to and withdrew: until you delete your account.
    • Supabase's API logs record the IP address of each request and keep it only for the hosting plan's short log window (days, not months). Baseline does not use it.

    Withdrawing. Turn any metric Off in Settings › Friends & sharing: its values are deleted from the server at once, and friends and competitions stop seeing it. Signing out stops uploads; friends keep seeing what you last shared until it ages out after 35 days or you stop sharing.

    Seeing and exporting your data. Settings › Friends & sharing › "See what's on the server" shows everything the server holds for you, as stored, and exports it as JSON.

    Deleting your account. Settings › Friends & sharing › "Delete account and shared data" deletes your account and every row about you on the server at once, and revokes Baseline's Sign in with Apple when Apple allows it (otherwise the app tells you how: iPhone Settings › your name › Sign in with Apple › Baseline › Stop Using). Deleting the app does not delete your Friends account; delete the account first.

    Reports and blocking. Every friend can be reported or blocked. A report sends the developer only a fixed reason (name, cheating, harassment or other), never text you write. Reports are reviewed at least weekly; the developer may block or delete a profile. Blocking removes the friendship both ways.

    Age. Friends is for people 16 and older.

    The demo preview. "Preview with demo friends", sample data and the screenshots use made-up friends on your iPhone and send nothing.

    No analytics, ads or tracking. Baseline contains no analytics, crash reporting, advertising, tracking or other telemetry. Its only network connections are Friends' requests to Baseline's server, and only after you sign in to Friends. It asks only for Bluetooth and, if you choose, Apple Health; it does not ask for your location, motion data, microphone or camera.

    Deleting your data. Delete the app and everything it stored on your iPhone is gone. Metrics written to Apple Health stay there until you remove them in the Health app. A paired strap can be forgotten under Settings › Devices. If you used Friends, delete your account in Settings › Friends & sharing before deleting the app: the account and what you shared stay on the server otherwise (until they age out as above), and iOS may keep the sign-in session in the Keychain.

    Your rights. Wherever you live, you can see, export, correct (your name, in Settings › Friends & sharing) and delete what the server holds about you, and withdraw any consent, all in the app. If EU or UK data protection law applies to you, you also have the rights to object and to restrict processing, and you can complain to the data protection authority where you live or work. For anything else, write to the contact below.

    Record of processing and risk assessment (outline).

    • Controller: Patrick Schmidt (contact below). Processor: Supabase, Inc. (DPA signed; EU region Frankfurt).
    • Purpose: showing chosen activity and trend values to accepted friends and scoring friendly competitions. No other purpose; no profiling, advertising or sale.
    • People: Baseline users 16 and older who sign in to Friends.
    • Data: user ID, display name, goals, the per-metric values listed above, friendships, hides, blocks, invites, competitions and results, reports, the consent record, API IP logs.
    • Retention: as listed above, enforced by a daily server job and on every upload.
    • Risks and measures: health data (Art. 9) is reduced before it leaves the phone (daily counts, 0/1 nights, clipped weekly changes against the person's own baseline) and is off by default, per metric, with explicit consent and withdrawal that deletes. Comparing bodies is avoided: physiology is never ranked or in a competition. Wrong-audience exposure is limited by one server-side visibility rule on every health table and writes only through checked server functions. Account misuse: Sign in with Apple only, sessions on this device only, no secret key in the app. Social harm: no free text, 16+, report and block on every friend, a name filter.

    Changes. If what Baseline stores or sends changes, this policy changes with it. The current version is always in the app and at the page linked below.

    Contact. Patrick Schmidt, paddyr.schmidt@gmail.com (also for reports and data requests)

    About Baseline. Baseline is not affiliated with, endorsed by or connected to WHOOP, Inc.; "WHOOP" only names the hardware it works with. Baseline is not a medical device and nothing it shows is medical advice: every number is an estimate from published methods. Talk to a professional about health decisions.
    """

    static let disclaimer = """
    Baseline is an independent, unofficial, non-commercial project. It is not affiliated with, endorsed by, sponsored by, or connected to WHOOP, Inc. in any way. "WHOOP" is used only to identify the third-party hardware this software works with, never to imply origin, sponsorship or endorsement. Use it only with a device you own, and do not use it in breach of any agreement that applies to you.

    Not a medical device. Heart rate, HRV, resting heart rate, readiness, sleep stages, effort and every other number Baseline shows are approximations computed from published methods. They are not clinically validated, are not a medical device, and are not medical advice. Do not use them to diagnose, treat, or make health decisions. Consult a qualified professional.

    The software is provided as-is, with no warranty of any kind, express or implied. You use it entirely at your own risk, including any risk to your device, data, or warranty status. The authors accept no liability for any damage, loss, or consequence arising from its use.

    Local first: everything works without an account, and there is no telemetry. Nothing leaves your iPhone unless you sign in to Friends and turn sharing on; the privacy policy lists exactly what is then sent. When you allow it, Baseline reads from and writes to Apple Health on this device.
    """
}
#endif
