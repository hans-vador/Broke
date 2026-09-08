//
//  DevPanel.swift
//  Broke
//
//  The development build's control room. Everything QA needs that normally
//  requires a tag tap, a pod in the room, a thirty second wait, or a reinstall.
//
//  The whole file is compiled out of shipped builds by `#if DEV_BUILD`, so the
//  TestFlight app has no panel, no entry point, and none of these strings.
//
//  This exists because the older QA hooks are environment variables, which only
//  arrive via `SIMCTL_CHILD_*` on the simulator or an Xcode scheme launch. Tap
//  the app icon on a real phone and none of them are set — so on device the
//  hooks may as well not exist. The panel is the on-device equivalent.
//

#if DEV_BUILD

import Combine
import SwiftUI

struct DevPanel: View {
    @ObservedObject var model: FocusLockModel
    @ObservedObject var proximity: BLEProximityManager
    // Passed in rather than read from the environment: `devTools()` is applied
    // outside `environmentObject(designSettings)` in BrokeApp, so the panel's
    // sheet is not a descendant of the injection and @EnvironmentObject would
    // trap the moment the panel is opened.
    @ObservedObject var designSettings: DesignSettings
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingReset = false
    @State private var didReset = false
    @State private var nfcBypass = FocusLockModel.isNFCTestBypassEnabled
    @State private var journalGeneration = 0

    var body: some View {
        NavigationStack {
            List {
                buildSection
                stateSection
                lockSection
                hardwareSection
                mascotSection
                designSection
                journalSection
                resetSection
            }
            .navigationTitle("Dev Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var buildSection: some View {
        Section("Build") {
            row("Identity", AppBuild.summary)
            row("Mode", AppBuild.isDevelopment ? "development" : "shipped")
            row("URL scheme", "\(AppBuild.urlScheme)://")
        }
    }

    /// Read-only mirror of the things that decide whether the lock engages, so
    /// a "why isn't it blocking?" question is one glance rather than a rebuild.
    private var stateSection: some View {
        Section("State") {
            row("Lock mode", model.lockMode.title)
            row("Locked", model.isLocked ? "yes" : "no")
            row("Block list", model.hasSelection ? "has apps" : "EMPTY")
            row("Screen Time", model.hasScreenTimeAuthorization ? "granted" : "NOT GRANTED")
            row("Paired tag", model.hasPairedTag ? "yes" : "no")
            row("Pod in range", model.isBLEPodNear ? "yes" : "no")
            row("Paired pods", "\(proximity.pairedPodCount)")
            row("Emergency unlocks", "\(model.emergencyUnlocksRemaining)")
            if let countdown = model.unlockCountdown {
                row("Countdown", "\(countdown)s")
            }
        }
    }

    private var lockSection: some View {
        Section {
            Button("Force lock") { model.debugSetLocked(true) }
                .disabled(model.isLocked)
            Button("Force unlock") { model.debugSetLocked(false) }
                .disabled(!model.isLocked)

            if model.lockMode == .timer {
                Button("Start unlock countdown") { model.beginUnlockCountdown() }
                    .disabled(!model.isLocked || model.unlockCountdown != nil)
                Button("Cancel countdown") { model.cancelUnlockCountdown() }
                    .disabled(model.unlockCountdown == nil)
            }
        } header: {
            Text("Lock")
        } footer: {
            Text("Drives the same path as a real tag scan — shields, banners, haptics, notifications and the session timer all behave normally.")
        }
    }

    private var hardwareSection: some View {
        Section {
            Toggle("Bypass NFC tag", isOn: $nfcBypass)
                .onChange(of: nfcBypass) { _, newValue in
                    FocusLockModel.isNFCTestBypassEnabled = newValue
                    // The flag is read statically, so nudge the views that use it.
                    model.objectWillChange.send()
                }

            Button(model.isBLEPodNear ? "Simulate pod: away" : "Simulate pod: in range") {
                model.updateBLEProximity(isNear: !model.isBLEPodNear)
            }
            .disabled(model.lockMode != .pod && model.lockMode != .both)

            Button("Forget paired tag", role: .destructive) {
                model.devForgetPairedTag()
            }
            .disabled(!model.hasPairedTag)
        } header: {
            Text("Hardware")
        } footer: {
            Text(hardwareFooter)
        }
    }

    private var hardwareFooter: String {
        switch model.lockMode {
        case .pod, .both:
            "Simulating the pod goes through the real proximity path. A genuine BLE reading will override it on the next change."
        case .tag, .timer:
            "Pod simulation is disabled because this build's lock mode ignores pods."
        }
    }

    @ViewBuilder
    private var mascotSection: some View {
        Section("Mascots") {
            NavigationLink("Mascot gallery") {
                MascotGalleryView()
            }
        }
    }

    /// The home screen's newer look, switchable against the old one. Shipped
    /// builds get the values in `DesignTokens.production` and no switches, so
    /// this is purely a way to compare the two on a real phone.
    private var designSection: some View {
        Section {
            Toggle(isOn: $designSettings.showsSupportingCharacters) {
                devToggleLabel(
                    "Supporting characters",
                    detail: "Clay padlock in the header and clay clock on the locked card. Off leaves the fruit as the only character."
                )
            }

            Toggle(isOn: $designSettings.usesCompactStatusCard) {
                devToggleLabel(
                    "Compact status card",
                    detail: "Tighter card with a spotlight behind the mascot instead of a second drop shadow."
                )
            }

            Button("Restore shipped look") {
                designSettings.showsSupportingCharacters = DesignTokens.production.showsSupportingCharacters
                designSettings.usesCompactStatusCard = DesignTokens.production.usesCompactStatusCard
            }
            .disabled(isShowingShippedLook)
        } header: {
            Text("Design")
        } footer: {
            Text("Close the panel to see the change — these repaint the home screen live.")
        }
    }

    /// What the app did while it was not on screen. "[bg]" lines are the
    /// proof: they were written without the app being open. Empty after a
    /// walk test means the radio never woke us — force-quit, or Bluetooth
    /// denied — which is exactly the diagnosis this exists to make.
    private var journalSection: some View {
        Section {
            let entries = BackgroundJournal.entries
            if entries.isEmpty {
                Text("No events yet. Pair a pod, background the app, and walk.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entries.prefix(30).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.contains("[bg]") ? .primary : .secondary)
                }
            }
            Button("Clear journal") {
                BackgroundJournal.clear()
                journalGeneration += 1
            }
        } header: {
            Text("Background journal")
        } footer: {
            Text("Every radio wake, boundary crossing, and lock change, stamped with whether the app was on screen. [bg] lines happened without the app open.")
        }
        .id(journalGeneration)
    }

    private var isShowingShippedLook: Bool {
        designSettings.showsSupportingCharacters == DesignTokens.production.showsSupportingCharacters
            && designSettings.usesCompactStatusCard == DesignTokens.production.usesCompactStatusCard
    }

    private func devToggleLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var resetSection: some View {
        Section {
            Button("Restore emergency unlocks") {
                model.devResetEmergencyUnlocks()
            }
            Button("Reset onboarding & lock mode", role: .destructive) {
                isConfirmingReset = true
            }
        } header: {
            Text("Reset")
        } footer: {
            Text(didReset
                 ? "Done — force-quit and reopen Broke to start from onboarding."
                 : "Lock mode is permanent by design, so this is the only way to try a different one without deleting the app.")
        }
        .confirmationDialog(
            "Reset onboarding and lock mode?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                LockModeStore.resetForDebug()
                didReset = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears the permanent lock mode and the onboarding flag. Your block lists, paired tag and pods are kept.")
        }
    }

    // MARK: - Bits

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }
}

// MARK: - Entry point

extension View {
    /// Adds the dev build's badge and makes it the way into the panel. Tap the
    /// badge to open it. Compiled out of shipped builds entirely.
    func devTools(
        model: FocusLockModel,
        proximity: BLEProximityManager,
        designSettings: DesignSettings
    ) -> some View {
        modifier(DevToolsOverlay(
            model: model,
            proximity: proximity,
            designSettings: designSettings
        ))
    }
}

private struct DevToolsOverlay: ViewModifier {
    @ObservedObject var model: FocusLockModel
    @ObservedObject var proximity: BLEProximityManager
    @ObservedObject var designSettings: DesignSettings
    // Launch with SHOW_DEV_PANEL=1 to open straight into the panel, the same
    // way SHOW_SETTINGS=1 opens the settings sheet. Lets a screenshot run
    // reach the panel without a tap.
    @State private var isShowingPanel =
        ProcessInfo.processInfo.environment["SHOW_DEV_PANEL"] == "1"

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Button {
                    isShowingPanel = true
                } label: {
                    Text("DEV")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.85), in: Capsule())
                        // Generous tap target: the badge itself is tiny and it
                        // sits near the status bar.
                        .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .accessibilityLabel("Open dev panel")
            }
            .sheet(isPresented: $isShowingPanel) {
                DevPanel(
                    model: model,
                    proximity: proximity,
                    designSettings: designSettings
                )
                // The sheet is presented from outside the app's token
                // injection, so hand it the live tokens too — otherwise the
                // mascot gallery renders against the production defaults
                // instead of the scheme you're actually looking at.
                .environment(\.designTokens, designSettings.tokens)
            }
    }
}

#endif
