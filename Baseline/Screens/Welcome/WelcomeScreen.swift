#if os(iOS)
import SwiftUI
import WhoopStore

/// First run, three steps, no account: a welcome line, strap pairing through NOOP's `AddDeviceWizard`
/// (opened on the chosen WHOOP model's prep step, past NOOP's device-type chooser), and the Apple Health
/// permission. Every step can be skipped; the disclaimer is accepted implicitly through the footnote on
/// the first page. Calls `onFinished` once, from the last step.
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
            Button("Continue", action: onContinue)
                .buttonStyle(WelcomeCapsuleButtonStyle(filled: true))
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
        .sheet(item: $pairing) { type in
            AddDeviceWizard(live: live, onClose: { pairing = nil }, startAt: (type: type, step: .prep))
        }
    }
}

/// Observes the registry so the check and Continue flip the moment the wizard adopts a strap. The
/// registry is seeded with a placeholder row that has no peripheral, so "non-empty" is not the test;
/// an adopted device (a peripheral id) or a live bond is.
private struct WelcomePairActions: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var live: LiveState
    var onPair: (AddDeviceWizard.DeviceType) -> Void
    var onContinue: () -> Void

    private var paired: Bool {
        live.bonded || registry.devices.contains { $0.peripheralId != nil && !$0.isImportSource }
    }

    var body: some View {
        WelcomePairButtons(paired: paired, onPair: onPair, onContinue: onContinue)
    }
}

/// One button per WHOOP model, so the wizard can open on that model's prep step instead of NOOP's
/// device-type chooser. Nominative use of the WHOOP name only.
private struct WelcomePairButtons: View {
    let paired: Bool
    var onPair: (AddDeviceWizard.DeviceType) -> Void
    var onContinue: () -> Void

    var body: some View {
        if paired {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(BaselineTheme.good)
                Text("Strap paired").font(BaselineTheme.label).foregroundStyle(BaselineTheme.text)
            }
            .transition(.opacity)
        }
        Button("Pair WHOOP 4.0") { onPair(.whoop4) }
            .buttonStyle(WelcomeCapsuleButtonStyle(filled: !paired))
        Button("Pair WHOOP 5.0 / MG") { onPair(.whoop5mg) }
            .buttonStyle(WelcomeCapsuleButtonStyle(filled: !paired))
        Button("Continue", action: onContinue)
            .buttonStyle(WelcomeCapsuleButtonStyle(filled: paired))
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
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(BaselineTheme.good)
                    Text("Apple Health allowed").font(BaselineTheme.label).foregroundStyle(BaselineTheme.text)
                }
                Button("Finish", action: onFinished)
                    .buttonStyle(WelcomeCapsuleButtonStyle(filled: true))
            } else {
                Button(requesting ? "Asking…" : "Allow") {
                    guard !requesting else { return }
                    requesting = true
                    Task {
                        await health.requestAuthorization()
                        requesting = false
                        onFinished()
                    }
                }
                .buttonStyle(WelcomeCapsuleButtonStyle(filled: true))
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
/// instead of pushing the actions under the dots or off-screen.
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
                    VStack(spacing: 14) { actions() }
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

private struct WelcomeGlyph: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(BaselineTheme.accent)
            .frame(width: 72, height: 72)
            .background(BaselineTheme.accent.opacity(0.12), in: Circle())
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
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

// MARK: - Buttons

/// Capsule button: filled accent for the step's main action, a quiet card surface otherwise. One type,
/// so a step can flip which of two buttons is primary without changing view identity.
private struct WelcomeCapsuleButtonStyle: ButtonStyle {
    let filled: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BaselineTheme.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(filled ? Color.clear : BaselineTheme.cardStroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private var foreground: Color {
        if filled { return BaselineTheme.background }
        return isEnabled ? BaselineTheme.text : BaselineTheme.textTertiary
    }

    private var background: Color {
        filled ? BaselineTheme.accent.opacity(isEnabled ? 1 : 0.3) : BaselineTheme.card
    }
}

private struct WelcomeTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BaselineTheme.label)
            .foregroundStyle(BaselineTheme.textSecondary)
            .padding(.vertical, 6)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
#endif
