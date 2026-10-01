#if os(iOS)
import SwiftUI
import WhoopStore

/// First run, three steps, no account: a welcome line, strap pairing through NOOP's `AddDeviceWizard`,
/// and the Apple Health permission. Every step can be skipped; the disclaimer is accepted implicitly
/// through the footnote on the first page. Calls `onFinished` once, from the last step.
struct WelcomeScreen: View {
    var onFinished: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                WelcomeIntroStep(onContinue: { advance(to: 1) }).tag(0)
                WelcomePairStep(onContinue: { advance(to: 2) }).tag(1)
                WelcomeHealthStep(onFinished: onFinished).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            WelcomeDots(count: 3, index: step)
                .padding(.bottom, 24)
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
    @State private var showWizard = false

    var body: some View {
        WelcomeStepLayout {
            VStack(spacing: 16) {
                WelcomeGlyph(systemName: "dot.radiowaves.left.and.right")
                Text("Pair your strap")
                    .font(BaselineTheme.hero(34))
                    .foregroundStyle(BaselineTheme.text)
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
                WelcomePairActions(registry: registry, onPair: { showWizard = true }, onContinue: onContinue)
            } else {
                WelcomePairButtons(paired: live.bonded, onPair: { showWizard = true }, onContinue: onContinue)
            }
        }
        .sheet(isPresented: $showWizard) {
            AddDeviceWizard(live: live, onClose: { showWizard = false })
        }
    }
}

/// Observes the registry so the check and Continue flip the moment the wizard adopts a strap. The
/// registry is seeded with a placeholder row that has no peripheral, so "non-empty" is not the test;
/// an adopted device (a peripheral id) or a live bond is.
private struct WelcomePairActions: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var live: LiveState
    var onPair: () -> Void
    var onContinue: () -> Void

    private var paired: Bool {
        live.bonded || registry.devices.contains { $0.peripheralId != nil && !$0.isImportSource }
    }

    var body: some View {
        WelcomePairButtons(paired: paired, onPair: onPair, onContinue: onContinue)
    }
}

private struct WelcomePairButtons: View {
    let paired: Bool
    var onPair: () -> Void
    var onContinue: () -> Void

    var body: some View {
        if paired {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(BaselineTheme.good)
                Text("Strap paired").font(BaselineTheme.label).foregroundStyle(BaselineTheme.text)
            }
            .transition(.opacity)
        }
        Button(paired ? "Pair another strap" : "Pair strap", action: onPair)
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

/// Centered copy above, a column of actions pinned below. Keeps the three steps aligned.
private struct WelcomeStepLayout<Hero: View, Actions: View>: View {
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var actions: () -> Actions

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
