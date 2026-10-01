#if os(iOS)
import SwiftUI
import WhoopStore

/// First run, three steps, no account: a welcome line, strap pairing through NOOP's `AddDeviceWizard`
/// (opened on the chosen WHOOP model's prep step, past NOOP's device-type chooser), and the Apple Health
/// permission. Every step can be skipped; the disclaimer is accepted implicitly through the footnote on
/// the first page. Calls `onFinished` once, from the last step.
///
/// Light paper (`BaselineBackground`) with the copy centred above and a floating action column below.
/// The column is the one place Baseline uses glass buttons (`GlassCTA`, inside one
/// `GlassEffectContainer`): the buttons float over the background, not inside a card, so the HIG's
/// "glass is for the layer above content" rule holds. Text actions ("Skip for now", "Not now") stay
/// plain text. NOOP's pairing wizard keeps its own sheet chrome; `StrandPalette` resolves to its light
/// values under the app's `.preferredColorScheme(.light)`, so no colour-scheme override is applied.
struct WelcomeScreen: View {
    var onFinished: () -> Void
    @State private var step = WelcomeScreen.launchStep

    /// DEBUG-only: `--welcome-step 1|2` opens the flow on that page for screenshots.
    private static var launchStep: Int {
        #if DEBUG
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--welcome-step"), i + 1 < a.count, let n = Int(a[i + 1]), (0...2).contains(n) { return n }
        #endif
        return 0
    }

    var body: some View {
        TabView(selection: $step) {
            WelcomeIntroStep(onContinue: { advance(to: 1) }).tag(0)
            WelcomePairStep(onContinue: { advance(to: 2) }).tag(1)
            WelcomeHealthStep(onFinished: onFinished).tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // The dots are a bottom inset rather than a sibling below the pager: a page that scrolls (large
        // type, short phones) then ends above the dots instead of sliding its last button under them.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WelcomeDots(count: 3, index: step)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BaselineBackground())
    }

    private func advance(to next: Int) {
        withAnimation(.easeInOut(duration: 0.3)) { step = next }
    }
}

// MARK: - Step 1 · Welcome

private struct WelcomeIntroStep: View {
    var onContinue: () -> Void

    var body: some View {
        WelcomeStepLayout {
            VStack(spacing: 18) {
                Text("Baseline")
                    .font(BaselineTheme.hero(54))
                    .foregroundStyle(BaselineTheme.text)
                Text("Your HRV and resting heart rate, against your own baseline.")
                    .font(BaselineTheme.body)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        } actions: {
            Text("Works with WHOOP 4.0, 5.0 and MG straps · Everything stays on your iPhone · Not medical advice")
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GlassCTA(title: "Continue", action: onContinue)
        }
    }
}

// MARK: - Step 2 · Pair your strap

private struct WelcomePairStep: View {
    var onContinue: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    /// The strap model whose pairing wizard is open, or nil. Seeding the wizard with a model skips
    /// NOOP's device-type chooser (eight rows, an Experimental tier) and lands on that WHOOP prep step.
    @State private var pairing: AddDeviceWizard.DeviceType?

    var body: some View {
        WelcomeStepLayout {
            VStack(spacing: 16) {
                WelcomeGlyph(systemName: "dot.radiowaves.left.and.right")
                Text("Pair your strap")
                    .font(BaselineTheme.hero(34))
                    .foregroundStyle(BaselineTheme.text)
                // Names NOOP before the wizard's own copy does.
                Text("Pairing runs on NOOP, the open-source engine Baseline is built on.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    // Facts reused from NOOP's pairing guidance: a strap holds one Bluetooth link at a
                    // time, and a 5.0 / MG enters pairing mode when its LEDs flash blue.
                    Text("A strap talks to one phone at a time. Quit its previous app first, or pairing may fail.")
                    Text("On a 5.0 or MG, tap the strap until its LEDs flash blue. If it is listed under iPhone Settings › Bluetooth, choose Forget This Device.")
                }
                .font(BaselineTheme.body)
                .foregroundStyle(BaselineTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            if let registry = model.deviceRegistry {
                WelcomePairActions(registry: registry, onPair: { pairing = $0 }, onContinue: onContinue)
            } else {
                WelcomePairButtons(paired: live.bonded, onPair: { pairing = $0 }, onContinue: onContinue)
            }
        }
        // NOOP's sheet, NOOP's chrome: the wizard's copy already names NOOP, and StrandPalette carries a
        // light variant, so it inherits the app's light scheme untouched.
        .sheet(item: $pairing) { type in
            AddDeviceWizard(live: live, onClose: { pairing = nil }, startAt: (type: type, step: .prep))
        }
    }
}

/// Observes the registry so the check and Continue flip the moment the wizard adopts a strap. The
/// registry is seeded with a placeholder row that has no peripheral, so "non-empty" is not the test;
/// an adopted device (a peripheral id) or a live bond is. Same test as `StrapStatusPill.isPaired`.
private struct WelcomePairActions: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var live: LiveState
    var onPair: (AddDeviceWizard.DeviceType) -> Void
    var onContinue: () -> Void

    var body: some View {
        WelcomePairButtons(paired: StrapStatusPill.isPaired(live: live, registry: registry),
                           onPair: onPair, onContinue: onContinue)
    }
}

/// One button per WHOOP model, so the wizard can open on that model's prep step instead of NOOP's
/// device-type chooser. Nominative use of the WHOOP name only. Before pairing, "Pair WHOOP 4.0" is the
/// prominent action; once a strap is adopted it steps back to plain glass and "Continue" takes over.
private struct WelcomePairButtons: View {
    let paired: Bool
    var onPair: (AddDeviceWizard.DeviceType) -> Void
    var onContinue: () -> Void

    var body: some View {
        if paired {
            WelcomeDoneRow(text: "Strap paired")
        }
        GlassCTA(title: "Pair WHOOP 4.0", prominent: !paired) { onPair(.whoop4) }
        GlassCTA(title: "Pair WHOOP 5.0 / MG", prominent: false) { onPair(.whoop5mg) }
        GlassCTA(title: "Continue", action: onContinue)
            .disabled(!paired)
        Button("Skip for now", action: onContinue)
            .buttonStyle(WelcomeTextButtonStyle())
            .opacity(paired ? 0 : 1)
            .disabled(paired)
    }
}

// MARK: - Step 3 · Apple Health

private struct WelcomeHealthStep: View {
    var onFinished: () -> Void
    @EnvironmentObject private var health: HealthKitBridge
    @State private var requesting = false

    var body: some View {
        WelcomeStepLayout {
            VStack(spacing: 16) {
                WelcomeGlyph(systemName: "heart.text.square")
                Text("Apple Health")
                    .font(BaselineTheme.hero(34))
                    .foregroundStyle(BaselineTheme.text)
                Text("Let Baseline read sleep, workouts and heart data from Apple Health and write back what it computes, all on this iPhone.")
                    .font(BaselineTheme.body)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            if health.auth == .authorized {
                WelcomeDoneRow(text: "Apple Health allowed")
                GlassCTA(title: "Finish", action: onFinished)
            } else {
                GlassCTA(title: requesting ? "Asking…" : "Allow") {
                    guard !requesting else { return }
                    requesting = true
                    Task {
                        await health.requestAuthorization()
                        requesting = false
                        onFinished()
                    }
                }
                .disabled(requesting)
                Button("Not now", action: onFinished)
                    .buttonStyle(WelcomeTextButtonStyle())
                    .disabled(requesting)
            }
        }
    }
}

// MARK: - Layout pieces

/// Centered copy above, a column of actions below. Keeps the three steps aligned. The column fills the
/// page and centres when it fits; at accessibility Dynamic Type sizes or on short phones it scrolls
/// instead of pushing the actions under the dots or off-screen. The action column is the screen's one
/// `GlassEffectContainer`, so neighbouring glass buttons share a sampling layer and blend correctly.
private struct WelcomeStepLayout<Hero: View, Actions: View>: View {
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    hero()
                        .frame(maxWidth: 420)
                    Spacer(minLength: 24)
                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: 12) { actions() }
                    }
                    .frame(maxWidth: 420)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// The step's flat glyph: a light accent symbol on an `accent @ 0.10` circle (the icon-tile fill), never glass.
private struct WelcomeGlyph: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(BaselineTheme.accent)
            .frame(width: 72, height: 72)
            .background(BaselineTheme.accent.opacity(0.10), in: Circle())
            .accessibilityHidden(true)
    }
}

/// "Strap paired" / "Apple Health allowed": a `good` check beside ink text, one accessibility element.
private struct WelcomeDoneRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(BaselineTheme.symbol)
                .foregroundStyle(BaselineTheme.good)
            Text(text)
                .font(BaselineTheme.label)
                .foregroundStyle(BaselineTheme.text)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? BaselineTheme.accent : BaselineTheme.hairline)
                    .frame(width: i == index ? 22 : 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

// MARK: - Buttons

/// Text-only tertiary action under the glass column ("Skip for now", "Not now"): plain, `textSecondary`,
/// never glass. The primary and secondary actions are `GlassCTA` (Components/BaselineButtons.swift).
private struct WelcomeTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BaselineTheme.label)
            .foregroundStyle(isEnabled ? BaselineTheme.textSecondary : BaselineTheme.textTertiary)
            .padding(.vertical, 6)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
#endif
