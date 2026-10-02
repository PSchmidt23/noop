#if os(iOS)
import SwiftUI
import WhoopStore

/// Settings › Devices: one card per paired strap, an "Add strap" CTA (flat, in content), and the three
/// pairing facts.
/// The engine underneath is NOOP's `DeviceRegistry` (rename / make active / archive) and its
/// `AddDeviceWizard`, opened on the chosen WHOOP model's prep step exactly as the welcome flow does.
/// The outer view only waits for the registry to exist; `DevicesContent` observes it and `LiveState`.
struct DevicesScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BaselineScreen(title: "Devices") {
            if let registry = model.deviceRegistry {
                DevicesContent(registry: registry)
            } else {
                BaselineCard {
                    BaselineEmptyState(icon: "hourglass",
                                       title: "Opening your data",
                                       message: "Paired straps appear here in a moment.")
                }
            }
        }
    }
}

// MARK: - Content (registry resolved)

private struct DevicesContent: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    @State private var showChooser = false
    /// The model chosen in the Add sheet, carried across its dismissal so the wizard opens after it.
    @State private var chosen: AddDeviceWizard.DeviceType?
    /// The strap model whose pairing wizard is open, or nil.
    @State private var pairing: AddDeviceWizard.DeviceType?
    @State private var renameTarget: PairedDevice?
    @State private var renameDraft = ""
    @State private var forgetTarget: PairedDevice?
    @State private var pickNewActive = false
    @State private var showHelp = false

    private var straps: [PairedDevice] {
        DevicesModel.visibleStraps(registry.devices, liveBonded: live.bonded)
    }

    var body: some View {
        // One container, not a Group: a Group would hand every presentation modifier below to each
        // child, and several children presenting the same sheet is a presentation conflict.
        VStack(alignment: .leading, spacing: BaselineTheme.cardSpacing) {
            if straps.isEmpty {
                BaselineCard {
                    BaselineEmptyState(icon: "dot.radiowaves.left.and.right",
                                       title: "No strap yet",
                                       message: "Add your WHOOP strap and Baseline reads your nights straight from it.")
                }
            } else {
                ForEach(straps) { device in
                    StrapCard(device: device,
                              isActive: device.status == .active,
                              pairedCount: registry.devices.count,
                              onRename: { renameDraft = device.nickname ?? ""; renameTarget = device },
                              onMakeActive: { registry.setActive(device.id) },
                              onForget: { forgetTarget = device })
                }
            }
            addButton
            PairingHelpCard(expanded: $showHelp)
        }
        // The Add sheet closes before the wizard opens: SwiftUI will not present a second sheet over
        // one that is still dismissing, so the choice is carried through `onDismiss`.
        .sheet(isPresented: $showChooser, onDismiss: {
            if let chosen { pairing = chosen }
            chosen = nil
        }) {
            AddStrapSheet { type in chosen = type; showChooser = false }
        }
        .sheet(item: $pairing) { type in
            AddDeviceWizard(live: live, onClose: { pairing = nil }, startAt: (type: type, step: .prep))
                .environmentObject(model)
                .environmentObject(live)
        }
        .alert("Rename strap",
               isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } }),
               presenting: renameTarget) { device in
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                registry.rename(device.id, to: renameDraft)
                renameTarget = nil
            }
        } message: { _ in
            Text("A name you will recognise. Leave it empty to show the model again.")
        }
        .confirmationDialog("Forget this strap?",
                            isPresented: Binding(get: { forgetTarget != nil }, set: { if !$0 { forgetTarget = nil } }),
                            titleVisibility: .visible,
                            presenting: forgetTarget) { device in
            Button("Forget \(DevicesModel.cardTitle(device, liveVariant: live.whoop5Variant))", role: .destructive) {
                forget(device)
            }
            Button("Cancel", role: .cancel) { forgetTarget = nil }
        } message: { _ in
            Text("Baseline stops connecting to it. The nights it recorded stay. Pair it again any time.")
        }
        .confirmationDialog("Which strap is active now?",
                            isPresented: $pickNewActive,
                            titleVisibility: .visible) {
            ForEach(straps) { device in
                Button(DevicesModel.cardTitle(device, liveVariant: live.whoop5Variant)) { registry.setActive(device.id) }
            }
            Button("None for now", role: .cancel) { }
        } message: {
            Text("You forgot the active strap. The active strap is the one Baseline reads new nights from.")
        }
    }

    /// The one primary action on the page; its label is the UI test's `buttons["Add strap"]`.
    private var addButton: some View {
        BaselineCTA(title: "Add strap", systemImage: "plus") { showChooser = true }
            .accessibilityLabel("Add strap")
    }

    /// Release the Bluetooth link (otherwise the engine keeps re-grabbing the strap and it can never enter
    /// pairing mode again), then archive the row; its recorded data is kept. If it was the active strap and
    /// others remain, ask which one takes over.
    private func forget(_ device: PairedDevice) {
        let wasActive = device.status == .active
        let remaining = DevicesModel.nextActiveCandidates(after: device, in: straps)
        model.ble.forgetDevice(device.peripheralId)
        registry.archive(device.id)
        forgetTarget = nil
        if wasActive && !remaining.isEmpty { pickNewActive = true }
    }
}

// MARK: - Strap card

/// Name, model, connection, battery, firmware and when the strap was last heard from. Observes
/// `LiveState` itself so only the cards repaint on a strap tick.
private struct StrapCard: View {
    let device: PairedDevice
    let isActive: Bool
    let pairedCount: Int
    var onRename: () -> Void
    var onMakeActive: () -> Void
    var onForget: () -> Void
    @EnvironmentObject private var live: LiveState

    private var connected: Bool { isActive && live.connected }
    private var variant: String? { isActive ? live.whoop5Variant : nil }

    var body: some View {
        BaselineCard {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(connected ? BaselineTheme.good : BaselineTheme.inactive)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DevicesModel.cardTitle(device, liveVariant: variant))
                        .font(BaselineTheme.headline)
                        .foregroundStyle(BaselineTheme.text)
                    if let subtitle = DevicesModel.cardSubtitle(device, liveVariant: variant) {
                        Text(subtitle).font(BaselineTheme.caption).foregroundStyle(BaselineTheme.textSecondary)
                    }
                    Text(DevicesModel.lastSeenLine(connected: connected,
                                                   lastSyncedAt: isActive ? live.lastSyncedAt : nil,
                                                   lastSeenAt: device.lastSeenAt))
                        .font(BaselineTheme.caption)
                        .foregroundStyle(BaselineTheme.textSecondary)
                }
                Spacer(minLength: 8)
                if isActive { BaselinePill(text: "Active") }
                menu
            }
            BaselineStatRow {
                StatCell(label: "Battery", value: battery?.text ?? "–", color: battery?.color ?? BaselineTheme.text)
                StatCell(label: "Firmware", value: firmware ?? "–")
                StatCell(label: "Status", value: connected ? "Connected" : (isActive ? "Not connected" : "Paired"))
            }
        }
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var menu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(BaselineTheme.symbolAccessory.weight(.regular))
                .foregroundStyle(BaselineTheme.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Strap actions")
    }

    @ViewBuilder private var menuItems: some View {
        Button(action: onRename) { Label("Rename", systemImage: "pencil") }
        if !isActive {
            Button(action: onMakeActive) { Label("Make active", systemImage: "checkmark.circle") }
        }
        Button(role: .destructive, action: onForget) { Label("Forget", systemImage: "minus.circle") }
    }

    /// Battery is the strap's own number and outlives its link, so it is only shown while this strap is
    /// the connected source (the same rule as the Settings strap card).
    private var battery: (text: String, color: Color)? {
        guard connected, live.activeIsWhoop,
              let b = DevicesModel.batteryText(pct: live.batteryPct, charging: live.charging) else { return nil }
        let color: Color
        switch b.level {
        case .low: color = BaselineTheme.low
        case .watch: color = BaselineTheme.watch
        case .good: color = BaselineTheme.good
        }
        return (b.text, color)
    }

    /// The handshake value for the connected strap, else the build NOOP persisted for this peripheral;
    /// the engine's single legacy key only when one strap is paired, because it cannot say whose it is.
    private var firmware: String? {
        FirmwareAttribution.resolve(
            live: isActive ? live.strapFirmware : nil,
            perDevice: FirmwareAttribution.prefKey(peripheralId: device.peripheralId)
                .flatMap { UserDefaults.standard.string(forKey: $0) },
            legacyGlobal: UserDefaults.standard.string(forKey: "noop.lastFirmware"),
            pairedCount: pairedCount)
    }

    private var accessibilitySummary: String {
        var parts = [DevicesModel.cardTitle(device, liveVariant: variant)]
        if let s = DevicesModel.cardSubtitle(device, liveVariant: variant) { parts.append(s) }
        if isActive { parts.append("active") }
        parts.append(connected ? "connected" : "not connected")
        if let battery { parts.append("battery \(battery.text)") }
        if let firmware { parts.append("firmware \(firmware)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Add strap sheet

/// The two-option chooser the welcome flow also offers, so the wizard opens on the right model's prep
/// step instead of NOOP's device-type list. WHOOP is named nominatively only. System sheet chrome, a
/// flat body: the two choices are in-content CTAs (the 4.0 prominent, as on Welcome), each with its one
/// pairing cue as a caption beneath.
private struct AddStrapSheet: View {
    var onChoose: (AddDeviceWizard.DeviceType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // A plain Text: the UI test waits for it after tapping "Add strap".
                Text("Which strap are you adding?")
                    .font(BaselineTheme.headline)
                    .foregroundStyle(BaselineTheme.text)
                Text("Pairing runs on NOOP, the open-source engine Baseline is built on. The strap talks to one phone at a time, so quit its previous app first.")
                    .font(BaselineTheme.caption)
                    .foregroundStyle(BaselineTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                choice("WHOOP 4.0", detail: "The strap with the clasp-side sensor", prominent: true) { onChoose(.whoop4) }
                choice("WHOOP 5.0 / MG", detail: "Tap it until the LEDs flash blue", prominent: false) { onChoose(.whoop5mg) }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BaselineTheme.gutter)
            .background(BaselineBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(BaselineTheme.accent)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// A `BaselineCTA` whose label is the model name verbatim, with its pairing cue beneath it (and as
    /// the button's hint for VoiceOver).
    private func choice(_ title: String, detail: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BaselineCTA(title: title, prominent: prominent, action: action)
                .accessibilityHint(detail)
            Text(detail)
                .font(BaselineTheme.caption)
                .foregroundStyle(BaselineTheme.textTertiary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Pairing help

/// The three pairing facts the welcome flow states, behind a disclosure so the screen stays quiet.
private struct PairingHelpCard: View {
    @Binding var expanded: Bool

    private static let facts = [
        "A strap talks to one phone at a time. Quit its previous app, or pairing may fail.",
        "On a 5.0 or MG, tap the strap until its LEDs flash blue; that is pairing mode.",
        "If the strap is listed under iPhone Settings › Bluetooth, choose Forget This Device first."
    ]

    var body: some View {
        BaselineCard {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                HStack(spacing: 14) {
                    SettingsIconTile(icon: "questionmark.circle")
                    Text("Pairing help").font(BaselineTheme.body).foregroundStyle(BaselineTheme.text)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(BaselineTheme.symbolSmall)
                        .foregroundStyle(BaselineTheme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(expanded ? "expanded" : "collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.facts, id: \.self) { fact in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(BaselineTheme.textTertiary).frame(width: 4, height: 4).padding(.top, 7)
                                .accessibilityHidden(true)
                            Text(fact)
                                .font(BaselineTheme.caption)
                                .foregroundStyle(BaselineTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
#endif
