import FamilyControls
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: FocusLockModel
    @ObservedObject var proximity: BLEProximityManager
    @EnvironmentObject private var designSettings: DesignSettings
    @State private var isChoosingApps = false
    @State private var podRoomNames: [String: String] = [:]
    @State private var calibrationPod: BLEProximityManager.PodSnapshot?
    @State private var isNamingProfile = false
    @State private var newProfileName = ""
    @State private var isConfirmingEmergencyUnlock = false
    @State private var lockAnimationTrigger = 0
#if DEBUG
    @State private var isShowingDesignPanel = false
#endif

    private var design: DesignTokens {
        designSettings.tokens
    }

    var body: some View {
        ZStack {
            PlayfulBackdrop(tokens: design)

            ScrollView {
                VStack(spacing: design.spacing(0)) {
                    header
                    statusCard
                        .padding(.top, design.spacing(28))
                    appSection
                        .padding(.top, design.spacing(32))
                    proximitySection
                        .padding(.top, design.spacing(28))
                    actionSection
                        .padding(.top, design.spacing(28))
                    footer
                        .padding(.top, design.spacing(30))
                }
                .padding(.horizontal, design.spacing(22))
                .padding(.bottom, design.spacing(28))
            }

#if DEBUG
            VStack {
                Spacer()
                HStack(spacing: design.spacing(12)) {
                    Spacer()
                    Button {
                        model.debugToggleLock()
                    } label: {
                        Image(systemName: model.displayedIsLocked ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: design.type(17), weight: .black))
                            .foregroundStyle(design.primary)
                            .frame(width: 52, height: 52)
                            .background(design.secondary, in: Circle())
                            .shadow(
                                color: design.text.opacity(0.14),
                                radius: design.shadow(20),
                                y: design.shadow(10)
                            )
                    }
                    .buttonStyle(PressButtonStyle())
                    .accessibilityLabel(model.displayedIsLocked ? "Dev unlock" : "Dev lock")

                    Button {
                        isShowingDesignPanel = true
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: design.type(17), weight: .black))
                            .foregroundStyle(design.secondary)
                            .frame(width: 52, height: 52)
                            .background(design.primary, in: Circle())
                            .shadow(
                                color: design.text.opacity(0.14),
                                radius: design.shadow(20),
                                y: design.shadow(10)
                            )
                    }
                    .buttonStyle(PressButtonStyle())
                    .accessibilityLabel("Open design controls")
                }
                .padding(.horizontal, design.spacing(22))
                .padding(.bottom, design.spacing(22))
            }
            .zIndex(20)
#endif
        }
        .environment(\.designTokens, design)
        .preferredColorScheme(.light)
        .familyActivityPicker(
            isPresented: $isChoosingApps,
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
            Text("Create another set of apps you can switch to instantly.")
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
            Text("You only get 3 emergency unlocks. They do not come back unless Broke is deleted and reinstalled.")
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
        .sheet(item: $calibrationPod) { pod in
            BoundaryCalibrationSheet(
                pod: pod,
                proximity: proximity,
                dismiss: { calibrationPod = nil }
            )
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(34)
        }
#if DEBUG
        .sheet(isPresented: $isShowingDesignPanel) {
            DesignDebugPanel(settings: designSettings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
#endif
        .onChange(of: model.displayedIsLocked) { wasLocked, isLocked in
            // Trigger the mascot's jump-spin on any lock/unlock transition.
            if isLocked != wasLocked {
                lockAnimationTrigger += 1
            }
        }
        .task {
            await model.requestAuthorizationIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Broke")
                .font(.system(size: design.type(24), weight: .black, design: .rounded))
                .foregroundStyle(design.text)

            Spacer()

            LockCharacter(
                size: design.hero(44),
                isLocked: model.displayedIsLocked,
                transitionTrigger: lockAnimationTrigger
            )
            .frame(width: design.hero(68), height: design.hero(76))
            .padding(.top, design.spacing(36))
        }
        .padding(.top, design.spacing(16))
    }

    private var statusCard: some View {
        let locked = model.displayedIsLocked
        let base = design.primaryFor(locked: locked)
        let accent = design.secondaryFor(locked: locked)

        return VStack(spacing: design.spacing(10)) {
            Text(locked ? "Locked" : "Ready to focus?")
                .font(.system(size: design.type(30), weight: .black, design: .rounded))
                .foregroundStyle(model.displayedIsLocked ? design.surface : design.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            StatusAwareMascot(
                size: design.hero(104),
                isLocked: locked,
                transitionTrigger: lockAnimationTrigger
            )
            .padding(.top, design.spacing(34))

            if locked {
                HStack(spacing: design.spacing(10)) {
                    ClockCharacter(size: design.hero(70))

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
                .padding(.top, design.spacing(2))
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(design.spacing(18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(base, in: RoundedRectangle(cornerRadius: design.radius(14)))
        .accessibilityElement(children: .combine)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: locked)
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: design.spacing(14)) {
            Button {
                model.scanTag()
            } label: {
                Label(
                    FocusLockModel.isNFCTestBypassEnabled
                        ? model.displayedIsLocked ? "Test unlock" : "Test lock"
                        : model.displayedIsLocked ? "Scan to unlock" : "Scan to lock",
                    systemImage: FocusLockModel.isNFCTestBypassEnabled
                        ? "hand.tap.fill"
                        : "wave.3.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle(tokens: design, isEnabled: model.canScan, lockState: model.displayedIsLocked))
            .disabled(!model.canScan)

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
                        .frame(width: design.hero(116), height: design.hero(164))
                        .background(design.muted, in: RoundedRectangle(cornerRadius: design.radius(12)))
                        .overlay {
                            RoundedRectangle(cornerRadius: design.radius(12))
                                .stroke(
                                    design.text.opacity(0.12),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [5])
                                )
                        }
                    }
                    .buttonStyle(PressButtonStyle())
                }
            }
            .contentMargins(.horizontal, 1, for: .scrollContent)

            Button {
                isChoosingApps = true
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text(model.hasSelection ? "Edit active list" : "Choose apps for this list")
                    Spacer()
                    Text("\(model.selectedItemCount) selected")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: design.type(12), weight: .black, design: .rounded))
                .foregroundStyle(design.text.opacity(0.68))
                .padding(.horizontal, design.spacing(16))
                .frame(height: design.spacing(48))
                .background(design.muted, in: RoundedRectangle(cornerRadius: design.radius(8)))
            }
            .buttonStyle(.plain)

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
                    .foregroundStyle(design.secondary)
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
            .foregroundStyle(
                model.hasScreenTimeAuthorization
                    ? design.secondary
                    : design.signal
            )
        }
    }

    private func blockProfileIsland(_ profile: BlockProfile, index: Int) -> some View {
        let isActive = profile.id == model.activeProfileID
        let ink = isActive ? design.surface : design.text
        // Each list keeps its own distinct fruit, fixed regardless of lock state.
        let persona = FruitPersona.forBlockList(index)

        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                model.selectBlockProfile(profile.id)
            }
        } label: {
            VStack(spacing: design.spacing(10)) {
                FruitCharacter(fruit: persona.fruit, personality: persona.personality, size: design.hero(66))

                VStack(spacing: design.spacing(3)) {
                    Text(profile.name)
                        .font(.system(size: design.type(14), weight: .black, design: .rounded))
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
            .frame(width: design.hero(136), height: design.hero(164))
            .background(
                isActive ? design.secondary : design.muted,
                in: RoundedRectangle(cornerRadius: design.radius(12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: design.radius(12))
                    .stroke(isActive ? design.primary.opacity(0.5) : design.text.opacity(0.06), lineWidth: isActive ? 2 : 1)
            }
        }
        .buttonStyle(PressButtonStyle())
        .contextMenu {
            if model.blockProfiles.count > 1 {
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
            if model.isLocked {
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

            if !FocusLockModel.isNFCTestBypassEnabled {
                Button {
                    model.pairTag()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(model.hasPairedTag ? "Pair a different tag" : "Pair NFC tag")
                    }
                    .font(.system(size: design.type(13), weight: .black, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.58))
                    .frame(height: design.spacing(42))
                }
                .buttonStyle(.plain)
                .disabled(!model.hasSelection)
            }
        }
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
                        FruitCharacter(fruit: .peach, personality: .sleepy, size: design.hero(60))

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
                        .foregroundStyle(pod.isNear ? design.secondary : design.text.opacity(0.5))
                }
                HStack(spacing: design.spacing(10)) {
                    Button(pod.boundaryRSSI == nil ? "Calibrate" : "Recalibrate") {
                        proximity.clearCalibrationResult()
                        calibrationPod = pod
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

private struct BoundaryCalibrationSheet: View {
    let pod: BLEProximityManager.PodSnapshot
    @ObservedObject var proximity: BLEProximityManager
    let dismiss: () -> Void
    @Environment(\.designTokens) private var design

    private var session: BLEProximityManager.CalibrationSession? {
        guard proximity.calibrationSession?.podID == pod.podID else { return nil }
        return proximity.calibrationSession
    }

    private var result: BLEProximityManager.CalibrationResult? {
        guard proximity.calibrationResult?.podID == pod.podID else { return nil }
        return proximity.calibrationResult
    }

    var body: some View {
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
        .background(design.surface)
        .onDisappear {
            if session != nil {
                proximity.cancelCalibration()
            }
            proximity.clearCalibrationResult()
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
        result?.succeeded == false ? design.signal : design.secondary
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
        font(.system(size: tokens.type(13), weight: .black, design: .rounded))
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
