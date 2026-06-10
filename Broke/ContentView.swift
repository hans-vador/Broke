import FamilyControls
import SwiftUI

struct ContentView: View {
    @StateObject private var model = FocusLockModel()
    @StateObject private var proximity = BLEProximityManager()
    @State private var isChoosingApps = false
    @State private var podRoomNames: [String: String] = [:]

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    statusCard
                        .padding(.top, 34)
                    appSection
                        .padding(.top, 38)
                    proximitySection
                        .padding(.top, 30)
                    actionSection
                        .padding(.top, 30)
                    footer
                        .padding(.top, 34)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.light)
        .familyActivityPicker(
            isPresented: $isChoosingApps,
            selection: $model.selection
        )
        .sheet(item: $model.popup) { popup in
            StatusPopup(popup: popup) {
                model.popup = nil
            }
            .presentationDetents([.height(390)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(34)
        }
        .task {
            await model.requestAuthorizationIfNeeded()
        }
        .onChange(of: proximity.isNear) { _, isNear in
            model.updateBLEProximity(isNear: isNear)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BROKE")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(3.2)
                Text("Less scroll. More life.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.48))
            }

            Spacer()

            Circle()
                .fill(model.isLocked ? Color.signal : Color.ink)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: model.isLocked ? "lock.fill" : "circle.dotted")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
        .padding(.top, 18)
    }

    private var statusCard: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.ink.opacity(0.08), lineWidth: 1)
                    .frame(width: 174, height: 174)

                Circle()
                    .fill(model.isLocked ? Color.signal : Color.ink)
                    .frame(width: 142, height: 142)
                    .shadow(
                        color: (model.isLocked ? Color.signal : Color.ink).opacity(0.18),
                        radius: 22,
                        y: 12
                    )

                Image(systemName: model.isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(spacing: 8) {
                Text(model.isLocked ? "FOCUS IS ON" : "READY TO FOCUS")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(model.isLocked ? Color.signal : Color.ink.opacity(0.55))

                Text(model.isLocked
                     ? "The noise is blocked."
                     : FocusLockModel.isNFCTestBypassEnabled
                        ? "Ready for a test run."
                        : "Tap your tag to begin.")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)

                Text(FocusLockModel.isNFCTestBypassEnabled
                     ? "Use the button below to test locking and unlocking."
                     : model.isLocked
                        ? "Scan the same NFC tag to unlock your apps."
                        : "One scan locks your chosen apps. The next brings them back.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 310)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("BLOCK LIST")
                    .sectionLabel()
                Spacer()
                Text("\(model.selectedItemCount) selected")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.38))
            }

            Button {
                isChoosingApps = true
            } label: {
                HStack(spacing: 15) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.ink)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.hasSelection ? "Edit blocked apps" : "Choose apps")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Text(model.hasSelection
                             ? "Apps and categories are ready"
                             : "Pick the apps that steal your time")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.ink.opacity(0.45))
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(0.35))
                }
                .padding(14)
                .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.ink.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                model.scanTag()
            } label: {
                Label(
                    FocusLockModel.isNFCTestBypassEnabled
                        ? model.isLocked ? "TEST UNLOCK" : "TEST LOCK"
                        : model.isLocked ? "SCAN TO UNLOCK" : "SCAN TO LOCK",
                    systemImage: FocusLockModel.isNFCTestBypassEnabled
                        ? "hand.tap.fill"
                        : "wave.3.right"
                )
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(1.2)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .foregroundStyle(.white)
                .background(
                    model.canScan ? Color.ink : Color.ink.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 18)
                )
            }
            .buttonStyle(PressButtonStyle())
            .disabled(!model.canScan)

            if !FocusLockModel.isNFCTestBypassEnabled {
                Button {
                    model.writeTag()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(model.hasPairedTag ? "REPLACE NFC TAG" : "SET UP NFC TAG")
                    }
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Color.ink.opacity(0.58))
                    .frame(height: 42)
                }
                .buttonStyle(.plain)
                .disabled(!model.hasSelection)
            }
        }
    }

    private var proximitySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("BLE PODS")
                    .sectionLabel()
                Spacer()
                Text("\(proximity.pairedPodCount) paired")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.38))
            }

            VStack(spacing: 14) {
                if proximity.pairedPodSnapshots.isEmpty {
                    Text("No rooms paired yet. Power on a Broke pod nearby.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.ink.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(proximity.pairedPodSnapshots) { pod in
                    pairedPodRow(pod)
                    if pod.id != proximity.pairedPodSnapshots.last?.id {
                        Divider().opacity(0.45)
                    }
                }

                ForEach(proximity.discoveredUnpairedPods) { pod in
                    Divider().opacity(0.45)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NEW POD · \(pod.podID)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Color.ink.opacity(0.42))

                        HStack(spacing: 10) {
                            TextField(
                                "Room name",
                                text: Binding(
                                    get: { podRoomNames[pod.podID, default: ""] },
                                    set: { podRoomNames[pod.podID] = $0 }
                                )
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(Color.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                            Button("PAIR") {
                                let room = podRoomNames[pod.podID, default: ""]
                                proximity.pairPod(pod.podID, room: room)
                            }
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 42)
                            .background(Color.ink, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(14)
            .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.ink.opacity(0.08), lineWidth: 1)
            }

            Text(proximity.isNear
                 ? "A paired room is in range. Signals are evaluated separately."
                 : proximity.status.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ink.opacity(0.34))
                .padding(.horizontal, 2)
        }
    }

    private func pairedPodRow(_ pod: BLEProximityManager.PodSnapshot) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(pod.isNear ? Color.signal : Color.ink.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(pod.isNear ? .white : Color.ink.opacity(0.6))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(pod.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text(podStatus(pod))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.45))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let rssi = pod.smoothedRSSI {
                    Text("\(Int(rssi.rounded())) dBm")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(pod.isNear ? Color.signal : Color.ink.opacity(0.5))
                }
                Button("FORGET") {
                    proximity.forgetPod(pod.podID)
                }
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(Color.signal)
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
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.ink.opacity(0.36))
        .multilineTextAlignment(.center)
    }
}

private struct StatusPopup: View {
    let popup: FocusPopup
    let dismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(popup.tint.opacity(0.12))
                    .frame(width: 108, height: 108)
                    .scaleEffect(appeared ? 1 : 0.55)

                Image(systemName: popup.symbol)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(popup.tint)
                    .symbolEffect(.bounce, value: appeared)
            }
            .padding(.top, 34)

            Text(popup.title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
                .padding(.top, 20)

            Text(popup.message)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.ink.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 34)
                .padding(.top, 8)

            Spacer()

            Button(action: dismiss) {
                Text(popup.buttonTitle)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(PressButtonStyle())
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .background(Color.canvas)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

private struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private extension View {
    func sectionLabel() -> some View {
        font(.system(size: 12, weight: .black, design: .rounded))
            .tracking(2)
            .foregroundStyle(Color.ink.opacity(0.52))
    }
}

private extension Color {
    static let canvas = Color(red: 0.965, green: 0.95, blue: 0.91)
    static let ink = Color(red: 0.075, green: 0.078, blue: 0.07)
    static let signal = Color(red: 0.91, green: 0.25, blue: 0.13)
}
