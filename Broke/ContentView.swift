import FamilyControls
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: FocusLockModel
    @ObservedObject var proximity: BLEProximityManager
    @EnvironmentObject private var designSettings: DesignSettings
    @State private var isChoosingApps = false
    @State private var podRoomNames: [String: String] = [:]
    @State private var calibrationRequest: BoundaryCalibrationRequest?
    @State private var isNamingProfile = false
    @State private var newProfileName = ""
    @State private var isConfirmingEmergencyUnlock = false
    @State private var lockAnimationTrigger = 0
#if DEBUG
    @State private var isShowingCustomize =
        ProcessInfo.processInfo.environment["SHOW_SETTINGS"] == "1"
#else
    @State private var isShowingCustomize = false
#endif
    @AppStorage(AppPreferenceKey.selectedMascot) private var selectedMascotRawValue = FruitKind.strawberry.rawValue
    @AppStorage(AppPreferenceKey.selectedScheme) private var selectedSchemeRawValue = DesignScheme.strawberry.rawValue

    private var design: DesignTokens {
        designSettings.tokens
    }

    private var selectedMascot: FruitKind {
        FruitKind(rawValue: selectedMascotRawValue) ?? .strawberry
    }

    /// The rigs are drawn on a square canvas with a fair margin around the
    /// character, so the compact card leans on the spotlight for presence and
    /// gives back the height the empty margin was eating.
    private var mascotSize: CGFloat {
        design.usesCompactStatusCard ? 138 : 150
    }

    /// Changing what is blocked is the one thing the lock has to prevent, so
    /// every control that can do it is gated on this. The model refuses these
    /// edits regardless; this is so the UI says why instead of going dead.
    private var canEditLists: Bool { model.canEditBlockLists }

    /// The app picker can only be open while unlocked. Locking with the sheet
    /// already up closes it, so a lock that engages mid-edit still holds.
    private var appPickerPresented: Binding<Bool> {
        Binding(
            get: { isChoosingApps && model.canEditBlockLists },
            set: { isChoosingApps = $0 }
        )
    }

    private var editListTitle: String {
        guard canEditLists else { return "Locked — unlock to change apps" }
        return model.hasSelection ? "Edit active list" : "Choose apps for this list"
    }

    /// Shared by the list cards and the "New list" card so the row lines up.
    /// Sized so a fresh install's two cards (one list plus "New list") sit
    /// inside the content width rather than running under the screen edge:
    /// 2 × hero(122) + spacing(14) ≈ 341pt against 358pt of usable width.
    private let blockCardWidth: CGFloat = 122

    /// Debug builds float a lock toggle over the bottom-right corner, which
    /// sat on top of the footer line. Leave it room to land.
    private var contentBottomInset: CGFloat {
#if DEBUG
        design.spacing(28) + 46
#else
        design.spacing(28)
#endif
    }

    var body: some View {
        ZStack {
            PlayfulBackdrop(tokens: design)

            ScrollView {
                VStack(spacing: design.spacing(0)) {
                    header
                    statusCard
                        .padding(.top, design.spacing(20))
                    appSection
                        .padding(.top, design.spacing(24))
                    // Only the hardware you actually signed up for gets a section.
                    if model.lockMode == .pod || model.lockMode == .both {
                        proximitySection
                            .padding(.top, design.spacing(28))
                    }
                    actionSection
                        .padding(.top, design.spacing(28))
                    footer
                        .padding(.top, design.spacing(30))
                }
                .padding(.horizontal, design.spacing(22))
                .padding(.bottom, contentBottomInset)
            }

#if DEBUG
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        model.debugToggleLock()
                    } label: {
                        Image(systemName: model.displayedIsLocked ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: design.type(12), weight: .bold))
                            .foregroundStyle(design.text)
                            .frame(width: 34, height: 34)
                            .background(design.surface.opacity(0.94), in: Circle())
                            .overlay {
                                Circle().stroke(design.text.opacity(0.12), lineWidth: 1)
                            }
                            .shadow(color: design.text.opacity(0.1), radius: 8, y: 3)
                    }
                    .buttonStyle(PressButtonStyle())
                    .opacity(0.58)
                    .accessibilityLabel(model.displayedIsLocked ? "Developer unlock" : "Developer lock")
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            .zIndex(20)
#endif
        }
        .environment(\.designTokens, design)
        .preferredColorScheme(.light)
        .familyActivityPicker(
            isPresented: appPickerPresented,
            selection: $model.selection
        )
        .alert("New block list", isPresented: $isNamingProfile) {
            TextField("Name, e.g. Deep Work", text: $newProfileName)
            Button("Cancel", role: .cancel) {
                newProfileName = ""
            }
            Button("Create") {
                model.addBlockProfile(named: newProfileName)
                newProfileName = ""
                isChoosingApps = true
            }
        } message: {
            Text("A separate set of apps you can switch to in one tap.")
        }
        .confirmationDialog(
            "Use an emergency unlock?",
            isPresented: $isConfirmingEmergencyUnlock,
            titleVisibility: .visible
        ) {
            Button("Use 1 emergency unlock", role: .destructive) {
                model.useEmergencyUnlock()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You get three in total. They do not reset. Use them only if you really need to.")
        }
        .sheet(item: $model.popup) { popup in
            StatusPopup(popup: popup) {
                model.popup = nil
                if case .screenTimeRequired = popup {
                    model.requestAuthorization()
                }
            }
            .presentationDetents([.height(390)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(34)
        }
        .sheet(item: $calibrationRequest) { request in
            BoundaryCalibrationSheet(
                pod: request.pod,
                proximity: proximity,
                dismiss: { calibrationRequest = nil },
                showsIntro: request.showsIntro
            )
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(34)
        }
        .sheet(isPresented: $isShowingCustomize) {
            AppearanceSettingsView(
                selectedMascotRawValue: $selectedMascotRawValue,
                selectedSchemeRawValue: $selectedSchemeRawValue,
                lockMode: model.lockMode
            )
                .environment(\.designTokens, design)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .onChange(of: selectedSchemeRawValue) { _, newValue in
            guard let scheme = DesignScheme(rawValue: newValue) else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                designSettings.apply(scheme)
            }
        }
        .onChange(of: model.displayedIsLocked) { wasLocked, isLocked in
            // Trigger the mascot's celebration on any lock/unlock transition.
            if isLocked != wasLocked {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.58)) {
                    lockAnimationTrigger += 1
                }
            }
        }
        .task {
            await model.requestAuthorizationIfNeeded()
            model.requestNotificationAuthorizationIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: design.spacing(12)) {
            Text("Broke")
                .font(.system(size: design.type(24), weight: design.headingWeight, design: .rounded))
                .foregroundStyle(design.text)

            Spacer(minLength: design.spacing(8))

            if !design.showsSupportingCharacters {
                lockStatusPill
            }

            Button {
                isShowingCustomize = true
            } label: {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: design.type(15), weight: .bold))
                    .foregroundStyle(design.secondary)
                    .frame(width: 38, height: 38)
                    .background(design.primary, in: Circle())
                    .shadow(color: design.primary.opacity(0.18), radius: 8, y: 4)
            }
            .buttonStyle(PressButtonStyle())
            .accessibilityLabel("Customize")

            if design.showsSupportingCharacters {
                Image(model.displayedIsLocked ? "clay_lock_locked" : "clay_lock_unlocked")
                    .resizable()
                    .scaledToFit()
                    .id(lockAnimationTrigger)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                    .frame(width: design.hero(68), height: design.hero(76))
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, design.spacing(16))
    }

    /// Stands in for the clay padlock. Same job — tell you at a glance whether
    /// you're locked — without putting a second character next to the mascot,
    /// and it says the state out loud instead of implying it.
    private var lockStatusPill: some View {
        let locked = model.displayedIsLocked

        return HStack(spacing: design.spacing(6)) {
            Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: design.type(11), weight: .black))
                .contentTransition(.symbolEffect(.replace))
            Text(locked ? "Locked" : "Open")
                .font(.system(size: design.type(12), weight: .black, design: .rounded))
        }
        .foregroundStyle(locked ? design.lockedSecondary : design.inkOnSurface(0.55))
        .padding(.horizontal, design.spacing(12))
        .frame(height: design.spacing(34))
        .background(locked ? design.lockedPrimary : design.muted, in: Capsule())
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: locked)
        .accessibilityLabel(locked ? "Apps are locked" : "Apps are open")
    }

    private var statusCard: some View {
        let locked = model.displayedIsLocked
        let base = design.primaryFor(locked: locked)
        let accent = design.secondaryFor(locked: locked)

        return VStack(spacing: design.spacing(10)) {
            VStack(alignment: .leading, spacing: design.spacing(4)) {
                Text(statusHeadline)
                    .font(.system(size: design.type(30), weight: design.headingWeight, design: .rounded))
                    .foregroundStyle(locked ? design.lockedSecondary : design.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(statusSubhead)
                    .font(.system(size: design.type(13), weight: .semibold, design: .rounded))
                    .foregroundStyle((locked ? design.lockedSecondary : design.secondary).opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LottieMascotView(
                fruit: selectedMascot,
                state: locked ? .onDuty : .idle,
                oneShotState: .celebrate,
                oneShotTrigger: lockAnimationTrigger
            )
            .frame(
                width: design.hero(mascotSize),
                height: design.hero(mascotSize)
            )
            // A soft pool of light so the mascot sits in the card instead of
            // floating on flat colour. It goes in a background so the glow can
            // spill past the rig without adding its own height to the card —
            // and the Lottie rigs bake their own contact shadow, so the ellipse
            // that used to sit here was stacking two shadows under one pair of
            // feet.
            .background {
                if design.usesCompactStatusCard {
                    // Drawn into a circle whose radius equals `endRadius`, so
                    // the glow reaches full transparency exactly at the rim.
                    // A bare RadialGradient fills its rectangle instead, and
                    // the four edge midpoints land inside the fade — which
                    // shows up as a faint square floating on the card.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(locked ? 0.22 : 0.18), accent.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: design.hero(112)
                            )
                        )
                        .frame(width: design.hero(224), height: design.hero(224))
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, design.spacing(design.usesCompactStatusCard ? 2 : 8))

            if locked {
                HStack(spacing: design.spacing(10)) {
                    if design.showsSupportingCharacters {
                        Image("clay_clock")
                            .resizable()
                            .scaledToFit()
                            .frame(width: design.hero(70), height: design.hero(70))
                            .accessibilityHidden(true)
                    }

                    HStack(spacing: design.spacing(6)) {
                        Image(systemName: "timer")
                            .font(.system(size: design.type(12), weight: .black))
                        Text(model.lockDurationText)
                            .font(.system(size: design.type(15), weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(base)
                    .padding(.horizontal, design.spacing(14))
                    .padding(.vertical, design.spacing(8))
                    .background(accent, in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: design.showsSupportingCharacters ? .leading : .center)
                .padding(.top, design.spacing(2))
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(design.spacing(design.usesCompactStatusCard ? 18 : 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(base, in: RoundedRectangle(cornerRadius: design.radius(20)))
        .accessibilityElement(children: .combine)
        .animation(.spring(response: 0.52, dampingFraction: 0.58), value: locked)
    }

    /// The one control that changes the lock. What it does depends entirely on
    /// the mode picked during onboarding.
    @ViewBuilder
    private var primaryControl: some View {
        if let remaining = model.unlockCountdown {
            countdownControl(remaining: remaining)
        } else if model.lockMode == .pod {
            HStack(spacing: design.spacing(12)) {
                Image(systemName: proximity.isNear
                      ? "sensor.tag.radiowaves.forward.fill"
                      : "sensor.tag.radiowaves.forward")
                    .font(.system(size: design.type(16), weight: .bold))
                    .symbolEffect(.variableColor, isActive: !proximity.isNear)
                Text(model.primaryActionTitle)
                    .font(.system(size: design.type(14), weight: .black, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(model.displayedIsLocked ? design.lockedSecondary : design.secondary)
            .padding(.horizontal, design.spacing(18))
            .frame(height: design.spacing(58))
            .frame(maxWidth: .infinity)
            .background(
                design.primaryFor(locked: model.displayedIsLocked),
                in: RoundedRectangle(cornerRadius: design.radius(8))
            )
        } else {
            Button {
                model.primaryAction()
            } label: {
                Label(model.primaryActionTitle, systemImage: model.primaryActionSymbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle(
                tokens: design,
                isEnabled: model.canToggleLock,
                lockState: model.displayedIsLocked
            ))
            .disabled(!model.canToggleLock)
        }
    }

    /// App-only mode's cooling-off period, shown as a filling bar you can bail
    /// out of. Bailing out is the good ending, so it gets the friendly styling.
    private func countdownControl(remaining: Int) -> some View {
        let total = Double(UnlockDelay.seconds)
        let progress = 1 - (Double(remaining) / total)

        return VStack(spacing: design.spacing(10)) {
            HStack(spacing: design.spacing(10)) {
                Image(systemName: "hourglass")
                    .font(.system(size: design.type(15), weight: .bold))
                Text("Unlocking in \(remaining)s")
                    .font(.system(size: design.type(15), weight: .black, design: .rounded))
                    .contentTransition(.numericText(countsDown: true))
                Spacer(minLength: 0)
                Text("Still time to change your mind")
                    .font(.system(size: design.type(10), weight: .bold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.42))
            }
            .foregroundStyle(design.text)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(design.text.opacity(0.10))
                    Capsule()
                        .fill(design.signal)
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 8)

            Button {
                model.cancelUnlockCountdown(userInitiated: true)
            } label: {
                Text("Never mind, keep me locked")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle(tokens: design, isEnabled: true))
        }
        .padding(design.spacing(16))
        .background(design.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: design.radius(12)))
        .overlay {
            RoundedRectangle(cornerRadius: design.radius(12))
                .stroke(design.signal.opacity(0.35), lineWidth: 1.5)
        }
        .animation(.easeInOut(duration: 0.9), value: remaining)
    }

    private var statusHeadline: String {
        if model.unlockCountdown != nil { return "Unlocking" }
        if model.displayedIsLocked { return "Apps blocked" }
        return model.hasSelection ? "Ready to lock" : "No apps chosen"
    }

    private var statusSubhead: String {
        if let remaining = model.unlockCountdown {
            return "\(remaining) seconds left."
        }
        if model.displayedIsLocked {
            switch model.lockMode {
            case .tag: return "Tap your tag to unlock."
            case .pod: return "Leave the room to unlock."
            case .both:
                return model.isBLEPodNear
                    ? "Leave the room, then tap your tag."
                    : "Tap your tag to unlock."
            case .timer: return "Unlocking takes 30 seconds."
            }
        }
        if !model.hasSelection { return "Choose which apps to block." }
        switch model.lockMode {
        case .tag: return "Tap your tag to lock."
        case .pod: return "Enter the pod's room to lock."
        case .both: return "Tap your tag, or enter the pod's room."
        case .timer: return "Lock whenever you're ready."
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: design.spacing(14)) {
            primaryControl
                .padding(.bottom, design.spacing(6))

            HStack {
                Text("Block lists")
                    .sectionLabel(tokens: design)
                Spacer()
                Text("\(model.blockProfiles.count) lists")
                    .font(.system(size: design.type(12), weight: .bold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.38))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: design.spacing(14)) {
                    ForEach(Array(model.blockProfiles.enumerated()), id: \.element.id) { index, profile in
                        blockProfileIsland(profile, index: index)
                    }

                    Button {
                        isNamingProfile = true
                    } label: {
                        VStack(spacing: design.spacing(8)) {
                            Image(systemName: "plus")
                                .font(.system(size: design.type(20), weight: .bold))
                            Text("New list")
                                .font(.system(size: design.type(11), weight: .black, design: .rounded))
                        }
                        .foregroundStyle(design.text.opacity(0.45))
                        // Matches the list cards — mismatched widths in one row
                        // read as an alignment mistake.
                        .frame(width: design.hero(blockCardWidth), height: design.hero(164))
                        .background(design.muted.opacity(0.5), in: RoundedRectangle(cornerRadius: design.radius(12)))
                        .overlay {
                            RoundedRectangle(cornerRadius: design.radius(12))
                                .stroke(
                                    design.text.opacity(0.12),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [5])
                                )
                        }
                    }
                    .buttonStyle(PressButtonStyle())
                    .disabled(!canEditLists)
                }
            }
            .contentMargins(.horizontal, 1, for: .scrollContent)

            Button {
                isChoosingApps = true
            } label: {
                HStack {
                    Image(systemName: canEditLists ? "slider.horizontal.3" : "lock.fill")
                    Text(editListTitle)
                    Spacer()
                    if canEditLists {
                        Text("\(model.selectedItemCount) selected")
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.system(size: design.type(12), weight: .black, design: .rounded))
                .foregroundStyle(design.inkOnSurface(canEditLists ? 0.68 : 0.45))
                .padding(.horizontal, design.spacing(16))
                .frame(height: design.spacing(48))
                .background(design.muted, in: RoundedRectangle(cornerRadius: design.radius(8)))
            }
            .buttonStyle(.plain)
            .disabled(!canEditLists)

            if !model.hasScreenTimeAuthorization {
                Button {
                    model.requestAuthorization()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "hourglass.badge.exclamationmark")
                        Text("Enable Screen Time access")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: design.type(12), weight: .black, design: .rounded))
                    // `secondary` is on-primary ink; over a 55%-alpha wash it
                    // left the one button that fixes a broken install unreadable.
                    .foregroundStyle(design.text)
                    .padding(.horizontal, design.spacing(16))
                    .frame(height: design.spacing(48))
                    .background(design.accentBlue.opacity(0.55), in: RoundedRectangle(cornerRadius: design.radius(8)))
                }
                .buttonStyle(.plain)
            }

            Label(
                model.authorizationMessage,
                systemImage: model.hasScreenTimeAuthorization
                    ? "checkmark.shield.fill"
                    : "exclamationmark.shield.fill"
            )
            .font(.system(size: 12, weight: .bold, design: .rounded))
            // The granted case used to be drawn in `secondary` — on-primary
            // ink over the page background, so the confirmation was invisible.
            .foregroundStyle(
                model.hasScreenTimeAuthorization
                    ? design.inkOnSurface(0.5)
                    : design.signal
            )
        }
    }

    private func blockProfileIsland(_ profile: BlockProfile, index: Int) -> some View {
        let isActive = profile.id == model.activeProfileID
        // `secondary`/`surface` are on-primary inks — near-white in every light
        // scheme — so using them here put the list name at ~1.0:1 against its
        // own card. Active is signalled by the fill and border instead.
        let ink = design.text
        // Each list keeps its own distinct fruit, fixed regardless of lock
        // state, and never the mascot: that one is the bouncer on the card above.
        let persona = FruitPersona.forBlockList(index, excluding: selectedMascot)

        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                model.selectBlockProfile(profile.id)
            }
        } label: {
            VStack(spacing: design.spacing(10)) {
                if design.showsBlockListMascots {
                    ClayFruitView(kind: persona.fruit)
                        .frame(width: design.hero(66), height: design.hero(66))
                } else {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "square.stack.3d.up.fill")
                        .font(.system(size: design.type(30), weight: .semibold))
                        .foregroundStyle(isActive ? design.primary : design.text.opacity(0.36))
                        .frame(width: design.hero(66), height: design.hero(66))
                }

                VStack(spacing: design.spacing(3)) {
                    Text(profile.name)
                        .font(.system(size: design.type(14), weight: design.headingWeight, design: .rounded))
                        .lineLimit(1)

                    Text("\(profile.itemCount) apps")
                        .font(.system(size: design.type(11), weight: .bold, design: .monospaced))
                        .foregroundStyle(ink.opacity(0.6))

                    Text(profileStatus(isActive: isActive, count: profile.itemCount))
                        .font(.system(size: design.type(10), weight: .black, design: .rounded))
                        .foregroundStyle(isActive ? design.primary : design.text.opacity(0.5))
                        .padding(.top, design.spacing(2))
                }
                .multilineTextAlignment(.center)
            }
            .foregroundStyle(ink)
            .padding(.vertical, design.spacing(16))
            .padding(.horizontal, design.spacing(12))
            .frame(width: design.hero(blockCardWidth), height: design.hero(164))
            .background(
                isActive ? design.surface : design.muted,
                in: RoundedRectangle(cornerRadius: design.radius(12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: design.radius(12))
                    .stroke(isActive ? design.primary : design.text.opacity(0.06), lineWidth: isActive ? 2.5 : 1)
            }
        }
        .buttonStyle(PressButtonStyle())
        .disabled(!canEditLists)
        .contextMenu {
            if canEditLists, model.blockProfiles.count > 1 {
                Button("Delete list", role: .destructive) {
                    model.deleteBlockProfile(profile.id)
                }
            }
        }
    }

    private func profileStatus(isActive: Bool, count: Int) -> String {
        guard count > 0 else { return isActive ? "Add apps" : "Empty" }
        guard isActive else { return "Tap to use" }
        return model.displayedIsLocked ? "Blocking now" : "Active"
    }

    private var actionSection: some View {
        VStack(spacing: design.spacing(12)) {
            // Emergency unlocks only exist for the modes you can genuinely get
            // stuck in. App-only mode already has a thirty second exit.
            if model.isLocked && model.lockMode != .timer {
                Button {
                    isConfirmingEmergencyUnlock = true
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Emergency unlock")
                        Spacer()
                        Text("\(model.emergencyUnlocksRemaining) left")
                    }
                    .font(.system(size: design.type(12), weight: .black, design: .rounded))
                    .foregroundStyle(model.canUseEmergencyUnlock ? design.signal : design.text.opacity(0.32))
                    .padding(.horizontal, design.spacing(16))
                    .frame(height: design.spacing(48))
                    .background(
                        model.canUseEmergencyUnlock ? design.accentPink.opacity(0.35) : design.muted,
                        in: RoundedRectangle(cornerRadius: design.radius(8))
                    )
                }
                .buttonStyle(PressButtonStyle())
                .disabled(!model.canUseEmergencyUnlock)
            }

            if (model.lockMode == .tag || model.lockMode == .both)
                && !FocusLockModel.isNFCTestBypassEnabled {
                Button {
                    model.pairTag()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(model.hasPairedTag ? "Pair a different tag" : "Pair your NFC tag")
                    }
                    .font(.system(size: design.type(13), weight: .black, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.58))
                    .frame(height: design.spacing(42))
                }
                .buttonStyle(.plain)
                .disabled(!model.hasSelection)
            }

            modeBadge
        }
    }

    /// A quiet reminder of the deal you signed up for. Deliberately not a
    /// button — the mode is permanent.
    private var modeBadge: some View {
        HStack(spacing: design.spacing(10)) {
            Image(systemName: model.lockMode.symbol)
                .font(.system(size: design.type(12), weight: .bold))
                .foregroundStyle(design.primary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Unlock method: \(model.lockMode.title)")
                    .font(.system(size: design.type(12), weight: .black, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.7))
                Text("Set during setup. Cannot be changed.")
                    .font(.system(size: design.type(10), weight: .semibold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, design.spacing(14))
        .padding(.vertical, design.spacing(12))
        .background(design.muted.opacity(0.7), in: RoundedRectangle(cornerRadius: design.radius(8)))
    }

    private var proximitySection: some View {
        VStack(alignment: .leading, spacing: design.spacing(14)) {
            HStack {
                Text("BLE pods")
                    .sectionLabel(tokens: design)
                Spacer()
                Text("\(proximity.pairedPodCount) paired")
                    .font(.system(size: design.type(12), weight: .bold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.38))
            }

            VStack(spacing: design.spacing(14)) {
                if proximity.pairedPodSnapshots.isEmpty {
                    HStack(spacing: design.spacing(14)) {
                        // Was a hardcoded peach, which put a second copy of the
                        // mascot on screen for anyone whose bouncer is a peach.
                        // An empty state doesn't need a character anyway — the
                        // one on the card above is the character.
                        Image(systemName: "sensor.tag.radiowaves.forward")
                            .font(.system(size: design.type(24), weight: .bold))
                            .foregroundStyle(design.primary)
                            .symbolEffect(.variableColor)
                            .frame(width: design.hero(60), height: design.hero(60))

                        Text("No pods paired yet.\nPower one on nearby.")
                            .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
                            .foregroundStyle(design.text.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(design.spacing(14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(design.accentBlue.opacity(0.25), in: RoundedRectangle(cornerRadius: design.radius(10)))
                }

                ForEach(proximity.pairedPodSnapshots) { pod in
                    pairedPodRow(pod)
                    if pod.id != proximity.pairedPodSnapshots.last?.id {
                        Divider().opacity(0.35)
                    }
                }

                ForEach(proximity.discoveredUnpairedPods) { pod in
                    Divider().opacity(0.35)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("New pod · \(pod.podID)")
                            .font(.system(size: design.type(11), weight: .black, design: .rounded))
                            .foregroundStyle(design.text.opacity(0.42))

                        HStack(spacing: design.spacing(10)) {
                            TextField(
                                "Room name",
                                text: Binding(
                                    get: { podRoomNames[pod.podID, default: ""] },
                                    set: { podRoomNames[pod.podID] = $0 }
                                )
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: design.type(14), weight: .semibold, design: .rounded))
                            .padding(.horizontal, design.spacing(12))
                            .frame(height: design.spacing(42))
                            .background(design.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: design.radius(6)))

                            Button("Pair") {
                                let room = podRoomNames[pod.podID, default: ""]
                                proximity.pairPod(pod.podID, room: room)
                                // Calibration is part of pairing, not a chore
                                // to find later: a pod without a boundary
                                // falls back to a generic threshold, which is
                                // exactly the state that behaves confusingly.
                                // pairPod publishes snapshots synchronously,
                                // so the paired snapshot exists right here.
                                if let paired = proximity.pairedPodSnapshots
                                    .first(where: { $0.podID == pod.podID }) {
                                    proximity.clearCalibrationResult()
                                    calibrationRequest = BoundaryCalibrationRequest(
                                        pod: paired, showsIntro: true)
                                }
                            }
                            .font(.system(size: design.type(12), weight: .black, design: .rounded))
                            .foregroundStyle(design.secondary)
                            .padding(.horizontal, design.spacing(16))
                            .frame(height: design.spacing(42))
                            .background(design.primary, in: RoundedRectangle(cornerRadius: design.radius(6)))
                        }
                    }
                }
            }
            .playfulPanel(tokens: design)

            Text(proximity.isNear
                 ? "A paired room is in range. Signals are evaluated separately."
                 : proximity.status.label)
                .font(.system(size: design.type(11), weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.34))
                .padding(.horizontal, 2)
        }
    }

    private func pairedPodRow(_ pod: BLEProximityManager.PodSnapshot) -> some View {
        HStack(spacing: design.spacing(12)) {
            Circle()
                .fill(pod.isNear ? design.primary : design.muted)
                .frame(width: design.hero(40), height: design.hero(40))
                .overlay {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: design.type(13), weight: .bold))
                        .foregroundStyle(pod.isNear ? design.secondary : design.text.opacity(0.55))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(pod.displayName)
                    .font(.system(size: design.type(15), weight: .bold, design: .rounded))
                    .foregroundStyle(design.text)
                Text(podStatus(pod))
                    .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.45))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let rssi = pod.smoothedRSSI {
                    Text("\(Int(rssi.rounded())) dBm")
                        .font(.system(size: design.type(12), weight: .black, design: .monospaced))
                        // In range used to draw in `secondary`, which is
                        // on-primary ink — invisible on the panel behind it.
                        .foregroundStyle(pod.isNear ? design.primary : design.inkOnSurface(0.5))
                }
                HStack(spacing: design.spacing(10)) {
                    Button(pod.boundaryRSSI == nil ? "Calibrate" : "Recalibrate") {
                        proximity.clearCalibrationResult()
                        calibrationRequest = BoundaryCalibrationRequest(
                            pod: pod, showsIntro: false)
                    }
                    .foregroundStyle(design.text.opacity(0.58))

                    Button("Forget") {
                        proximity.forgetPod(pod.podID)
                    }
                    .foregroundStyle(design.signal)
                }
                .font(.system(size: design.type(10), weight: .black, design: .rounded))
            }
        }
    }

    private func podStatus(_ pod: BLEProximityManager.PodSnapshot) -> String {
        if pod.isNear {
            return "Inside blocking range"
        }
        if !pod.isConnected {
            return "Disconnected"
        }
        if let boundary = pod.boundaryRSSI, let buffer = pod.hysteresisBuffer {
            return "Edge \(Int(boundary.rounded())) dBm · buffer \(Int(buffer.rounded()))"
        }
        if let distance = pod.estimatedDistance {
            return String(format: "Approx. %.1f m away", distance)
        }
        return "Reading signal"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone.radiowaves.left.and.right")
            Text(model.footerMessage)
        }
        .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
        .foregroundStyle(design.text.opacity(0.36))
        .multilineTextAlignment(.center)
    }
}

private struct AppearanceSettingsView: View {
    @Binding var selectedMascotRawValue: String
    @Binding var selectedSchemeRawValue: String
    let lockMode: LockMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTokens) private var design
    @EnvironmentObject private var designSettings: DesignSettings

    private let mascotColumns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 4
    )
    private let schemeColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 2
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: design.spacing(28)) {
                    howItWorksSection
                    schemeSection
                    interfaceSection
                    mascotSection
                }
                .padding(.horizontal, design.spacing(20))
                .padding(.vertical, design.spacing(22))
            }
            .background(PlayfulBackdrop(tokens: design))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(design.primary)
                }
            }
        }
    }

    /// A permanent reminder of the deal, plus the ground rules. There is no
    /// control here on purpose — the mode cannot be changed after setup.
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: design.spacing(14)) {
            sectionTitle("How Broke works", subtitle: "Your current setup.")

            VStack(alignment: .leading, spacing: design.spacing(14)) {
                HStack(spacing: design.spacing(13)) {
                    Image(systemName: lockMode.symbol)
                        .font(.system(size: design.type(18), weight: .bold))
                        .foregroundStyle(design.secondary)
                        .frame(width: 46, height: 46)
                        .background(design.primary, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(lockMode.title)
                            .font(.system(size: design.type(17), weight: .black, design: .rounded))
                            .foregroundStyle(design.text)
                        Text(lockMode.tagline)
                            .font(.system(size: design.type(11), weight: .black, design: .rounded))
                            .foregroundStyle(design.primary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "lock.fill")
                        .font(.system(size: design.type(12), weight: .bold))
                        .foregroundStyle(design.text.opacity(0.3))
                }

                Text(lockMode.blurb)
                    .font(.system(size: design.type(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)

                Divider().overlay(design.text.opacity(0.08))

                Text("This was set during setup and cannot be changed. To use a different method, delete Broke and set it up again.")
                    .font(.system(size: design.type(11), weight: .semibold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(design.spacing(16))
            .background(design.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: design.radius(14)))
            .overlay {
                RoundedRectangle(cornerRadius: design.radius(14))
                    .stroke(design.text.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private var mascotSection: some View {
        VStack(alignment: .leading, spacing: design.spacing(14)) {
            sectionTitle("Mascot", subtitle: "Pick the fruit shown on your home screen.")

            LazyVGrid(columns: mascotColumns, spacing: design.spacing(14)) {
                ForEach(FruitKind.allCases) { fruit in
                    let isSelected = fruit.rawValue == selectedMascotRawValue

                    Button {
                        selectedMascotRawValue = fruit.rawValue
                    } label: {
                        VStack(spacing: design.spacing(6)) {
                            // Static clay art, matching the onboarding picker.
                            // These were live Lottie rigs — eight of them, all
                            // looping at once on top of the home screen's rigs
                            // still playing behind the sheet. The animation is
                            // the payoff for choosing, not the preview of it.
                            //
                            // The ZStack is centred so the fruit sits in the
                            // middle of its swatch; only the badge is pinned to
                            // the corner, via an overlay on the tile itself.
                            ZStack {
                                RoundedRectangle(cornerRadius: design.radius(10))
                                    .fill(isSelected ? design.primary.opacity(0.14) : design.muted.opacity(0.72))
                                    .frame(height: design.hero(62))
                                    .overlay(alignment: .topTrailing) {
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: design.type(16), weight: .bold))
                                                .foregroundStyle(design.primary)
                                                .background(design.surface, in: Circle())
                                                .offset(x: 4, y: -4)
                                        }
                                    }

                                Image(fruit.clayAssetName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: design.hero(56))
                                    .padding(.horizontal, 4)
                            }

                            Text(fruit.name)
                                .font(.system(size: design.type(10), weight: .bold, design: .rounded))
                                .foregroundStyle(design.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                    .buttonStyle(PressButtonStyle())
                    .accessibilityLabel("Use \(fruit.name) mascot")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(design.spacing(14))
            .background(design.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: design.radius(14)))
        }
    }

    private var schemeSection: some View {
        VStack(alignment: .leading, spacing: design.spacing(14)) {
            sectionTitle("Color scheme", subtitle: "Set the palette across Broke.")

            LazyVGrid(columns: schemeColumns, spacing: design.spacing(12)) {
                ForEach(DesignScheme.allCases) { scheme in
                    let tokens = scheme.tokens
                    let isSelected = scheme.rawValue == selectedSchemeRawValue

                    Button {
                        selectedSchemeRawValue = scheme.rawValue
                    } label: {
                        VStack(alignment: .leading, spacing: design.spacing(10)) {
                            HStack(spacing: 5) {
                                Circle().fill(tokens.primary)
                                Circle().fill(tokens.accentPink)
                                Circle().fill(tokens.accentBlue)
                            }
                            .frame(height: 30)

                            HStack(spacing: 6) {
                                Text(scheme.name)
                                    .font(.system(size: design.type(13), weight: .black, design: .rounded))
                                    .foregroundStyle(tokens.text)
                                Spacer(minLength: 0)
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(tokens.primary)
                                }
                            }
                        }
                        .padding(design.spacing(12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tokens.surface, in: RoundedRectangle(cornerRadius: design.radius(11)))
                        .overlay {
                            RoundedRectangle(cornerRadius: design.radius(11))
                                .stroke(
                                    isSelected ? design.primary : tokens.text.opacity(0.12),
                                    lineWidth: isSelected ? 2.5 : 1
                                )
                        }
                    }
                    .buttonStyle(PressButtonStyle())
                    .accessibilityLabel("Use \(scheme.name) color scheme")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: design.spacing(14)) {
            sectionTitle("Interface", subtitle: "Shape and spacing.")

            VStack(spacing: 0) {
                choiceRow(
                    title: "Card corners",
                    symbol: "square.on.square",
                    selection: $designSettings.cardCornerStyle
                )
                Divider().overlay(design.text.opacity(0.08))
                choiceRow(
                    title: "Layout density",
                    symbol: "arrow.up.and.down.text.horizontal",
                    selection: $designSettings.layoutDensity
                )
                Divider().overlay(design.text.opacity(0.08))
                settingToggle(
                    title: "Soft blobs",
                    subtitle: "Decorative background shapes",
                    symbol: "circle.hexagongrid.fill",
                    isOn: $designSettings.showsSoftBlobs
                )
                Divider().overlay(design.text.opacity(0.08))
                settingToggle(
                    title: "Block-list mascots",
                    subtitle: "Show fruit on each list card",
                    symbol: "face.smiling.fill",
                    isOn: $designSettings.showsBlockListMascots
                )
                Divider().overlay(design.text.opacity(0.08))
                settingToggle(
                    title: "Bold headings",
                    subtitle: "Use extra-heavy title type",
                    symbol: "bold",
                    isOn: $designSettings.usesBoldHeadings
                )
            }
            .padding(.horizontal, design.spacing(14))
            .background(design.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: design.radius(14)))
            .overlay {
                RoundedRectangle(cornerRadius: design.radius(14))
                    .stroke(design.text.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func choiceRow<Option>(
        title: String,
        symbol: String,
        selection: Binding<Option>
    ) -> some View where Option: RawRepresentable & CaseIterable & Identifiable & Hashable, Option.RawValue == String {
        VStack(alignment: .leading, spacing: design.spacing(10)) {
            Label(title, systemImage: symbol)
                .font(.system(size: design.type(13), weight: design.headingWeight, design: .rounded))
                .foregroundStyle(design.text)

            Picker(title, selection: selection) {
                ForEach(Array(Option.allCases)) { option in
                    Text(option.rawValue.capitalized).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, design.spacing(14))
    }

    private func settingToggle(
        title: String,
        subtitle: String,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: design.spacing(11)) {
                Image(systemName: symbol)
                    .font(.system(size: design.type(13), weight: .bold))
                    .foregroundStyle(design.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: design.type(13), weight: design.headingWeight, design: .rounded))
                        .foregroundStyle(design.text)
                    Text(subtitle)
                        .font(.system(size: design.type(10), weight: .semibold, design: .rounded))
                        .foregroundStyle(design.text.opacity(0.46))
                }
            }
        }
        .tint(design.primary)
        .padding(.vertical, design.spacing(12))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: design.type(18), weight: design.headingWeight, design: .rounded))
                .foregroundStyle(design.text)
            Text(subtitle)
                .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.48))
        }
    }
}

/// How the calibration sheet was opened. Pairing shows the intro page first;
/// recalibrating an existing pod goes straight to the flow.
struct BoundaryCalibrationRequest: Identifiable {
    let pod: BLEProximityManager.PodSnapshot
    let showsIntro: Bool
    var id: String { pod.podID }
}

struct BoundaryCalibrationSheet: View {
    let pod: BLEProximityManager.PodSnapshot
    @ObservedObject var proximity: BLEProximityManager
    let dismiss: () -> Void
    /// When opened as the tail of pairing, start on a "Pod paired" page and
    /// wait for an explicit button press before showing the calibration flow —
    /// dropping someone into measuring UI mid-pair reads as it starting on
    /// its own, even though sampling never begins until they ask.
    var showsIntro = false
    @State private var hasLeftIntro = false
    @Environment(\.designTokens) private var design

    private var isShowingIntro: Bool {
        showsIntro && !hasLeftIntro && session == nil && result == nil
    }

    private var session: BLEProximityManager.CalibrationSession? {
        guard proximity.calibrationSession?.podID == pod.podID else { return nil }
        return proximity.calibrationSession
    }

    private var result: BLEProximityManager.CalibrationResult? {
        guard proximity.calibrationResult?.podID == pod.podID else { return nil }
        return proximity.calibrationResult
    }

    var body: some View {
        Group {
            if isShowingIntro {
                intro
            } else {
                calibration
            }
        }
        .background(design.surface)
        .onDisappear {
            if session != nil {
                proximity.cancelCalibration()
            }
            proximity.clearCalibrationResult()
        }
    }

    /// The reading step between pairing and calibrating. Nothing measures
    /// here; it says what happens next and waits.
    private var intro: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(design.primary.opacity(0.16))
                    .frame(width: 108, height: 108)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(design.primary)
            }
            .padding(.top, 34)

            Text("Pod paired")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(design.text)
                .padding(.top, 20)

            Text("\(pod.displayName) is set up. One more step: show Broke where this room ends.\n\nWalk to the edge of the room — the spot where your apps should switch between locked and unlocked — and hold your phone still for a few seconds while it measures.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 34)
                .padding(.top, 8)

            Spacer()

            Button {
                hasLeftIntro = true
            } label: {
                Text("Set the room boundary")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle(tokens: design, isEnabled: true))
            .padding(.horizontal, 22)

            Button("Do it later") {
                dismiss()
            }
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(design.text.opacity(0.45))
            .padding(.top, 16)

            Spacer().frame(height: 20)
        }
    }

    private var calibration: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.16))
                    .frame(width: 108, height: 108)

                if let session {
                    VStack(spacing: 0) {
                        Text("\(session.sampleCount)")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .contentTransition(.numericText())
                        Text("of \(session.targetSampleCount)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(iconColor)
                } else {
                    Image(systemName: result?.succeeded == true
                          ? "checkmark"
                          : "dot.radiowaves.left.and.right")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(iconColor)
                }
            }
            .padding(.top, 34)

            Text(title)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(design.text)
                .padding(.top, 20)

            Text(message)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 34)
                .padding(.top, 8)

            if let session {
                HStack(spacing: 18) {
                    reading("Live", session.currentRSSI.map { "\(Int($0.rounded())) dBm" } ?? "Waiting")
                    reading("Progress", "\(session.sampleCount) / \(session.targetSampleCount)")
                }
                .padding(.top, 22)
            } else if let result, let average = result.averageRSSI, let buffer = result.bufferRSSI {
                HStack(spacing: 18) {
                    reading("Edge", "\(Int(average.rounded())) dBm")
                    reading("Buffer", "\(Int(buffer.rounded())) dBm")
                }
                .padding(.top, 22)
            }

            Spacer()

            Button(action: primaryAction) {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle(tokens: design, isEnabled: pod.isConnected || session != nil || result != nil))
            .disabled(!pod.isConnected && session == nil && result == nil)
            .opacity(!pod.isConnected && session == nil && result == nil ? 0.35 : 1)
            .padding(.horizontal, 22)

            if session != nil {
                Button("Cancel") {
                    proximity.cancelCalibration()
                    dismiss()
                }
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(design.text.opacity(0.45))
                .padding(.top, 16)
            }

            Spacer().frame(height: 20)
        }
    }

    private var title: String {
        if session != nil { return "Hold still at the edge" }
        if result != nil { return result?.succeeded == true ? "Room calibrated" : "Try that again" }
        return "Find the room edge"
    }

    private var message: String {
        if session != nil {
            return "Keep your phone still. Broke will finish automatically after enough valid signal readings. Locking is paused while it measures."
        }
        if let result {
            return result.message
        }
        if !pod.isConnected {
            return "Reconnect \(pod.displayName), then return here to calibrate its room boundary."
        }
        return "Move to the edge of \(pod.displayName), where you want apps to switch between locked and unlocked. Stand still, then begin."
    }

    private var buttonTitle: String {
        if let session { return "Collecting \(session.sampleCount) / \(session.targetSampleCount)" }
        if result != nil { return result?.succeeded == true ? "Done" : "Try again" }
        return "Start calibration"
    }

    private var iconColor: Color {
        // Was `secondary` — on-primary ink drawn straight onto the sheet's
        // `surface`, so the icon and the live sample count were invisible.
        result?.succeeded == false ? design.signal : design.primary
    }

    private func primaryAction() {
        if session != nil { return }
        if let result {
            if result.succeeded {
                dismiss()
            } else {
                proximity.startCalibration(for: pod.podID)
            }
        } else {
            proximity.startCalibration(for: pod.podID)
        }
    }

    private func reading(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(design.text.opacity(0.35))
            Text(value)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundStyle(design.text)
        }
        .frame(minWidth: 100)
        .padding(.vertical, 11)
        .background(design.muted, in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct StatusPopup: View {
    let popup: FocusPopup
    let dismiss: () -> Void
    @Environment(\.designTokens) private var design

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(popup.tint.opacity(0.16))
                    .frame(width: 108, height: 108)
                    .scaleEffect(appeared ? 1 : 0.55)

                Image(systemName: popup.symbol)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(popup.tint)
                    .symbolEffect(.bounce, value: appeared)
            }
            .padding(.top, 34)

            Text(popup.title)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .foregroundStyle(design.text)
                .padding(.top, 20)

            Text(popup.message)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 34)
                .padding(.top, 8)

            Spacer()

            Button(action: dismiss) {
                Text(popup.buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle(tokens: design, isEnabled: true))
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .background(design.surface)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

private struct LockStateBanner: View {
    let banner: LockBanner
    @Environment(\.designTokens) private var design

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(banner.tint)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: banner.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(design.text)
                Text(banner.message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.52))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .background(design.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(design.text.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: design.text.opacity(0.1), radius: 22, y: 10)
    }
}

private extension View {
    func sectionLabel(tokens: DesignTokens) -> some View {
        font(.system(size: tokens.type(13), weight: tokens.headingWeight, design: .rounded))
            .foregroundStyle(tokens.text.opacity(0.72))
    }

    func playfulPanel(tokens: DesignTokens) -> some View {
        padding(tokens.spacing(16))
            .background(tokens.accentBlue.opacity(0.28), in: RoundedRectangle(cornerRadius: tokens.radius(10)))
            .overlay {
                RoundedRectangle(cornerRadius: tokens.radius(10))
                    .stroke(tokens.text.opacity(0.05), lineWidth: 1)
            }
    }
}
