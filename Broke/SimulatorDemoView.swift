import SwiftUI

struct SimulatorDemoView: View {
    @EnvironmentObject private var designSettings: DesignSettings
    @State private var isLocked = false
    @State private var showPopup = false
    @State private var showAppPicker = false
    @State private var selectedApps: Set<DemoApp> = [.instagram, .tiktok, .youtube]
    @State private var demoPods: [DemoPod] = [
        DemoPod(room: "Living Room", rssi: -76, isNear: false),
        DemoPod(room: "Bedroom", rssi: -82, isNear: false)
    ]
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
                VStack(spacing: 0) {
                    header
                    statusCard
                        .padding(.top, design.spacing(28))
                    appSection
                        .padding(.top, design.spacing(32))
                    demoPodsSection
                        .padding(.top, design.spacing(28))
                    actionSection
                        .padding(.top, design.spacing(28))
                    footer
                        .padding(.top, design.spacing(24))
                }
                .padding(.horizontal, design.spacing(22))
                .padding(.top, design.spacing(16))
                .padding(.bottom, design.spacing(28))
            }

#if DEBUG
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        isShowingDesignPanel = true
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: design.type(17), weight: .black))
                            .foregroundStyle(design.secondary)
                            .frame(width: 52, height: 52)
                            .background(design.primary, in: Circle())
                    }
                    .buttonStyle(PressButtonStyle())
                }
                .padding(.horizontal, design.spacing(22))
                .padding(.bottom, design.spacing(22))
            }
#endif
        }
        .environment(\.designTokens, design)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showAppPicker) {
            DemoAppPicker(selectedApps: $selectedApps)
        }
        .alert(isLocked ? "You are locked in." : "Welcome back.", isPresented: $showPopup) {
            Button("Done", role: .cancel) {}
        } message: {
            Text(isLocked
                 ? "Your selected apps are now blocked."
                 : "Your apps are available again.")
        }
#if DEBUG
        .sheet(isPresented: $isShowingDesignPanel) {
            DesignDebugPanel(settings: designSettings)
                .presentationDetents([.large])
        }
#endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Good morning")
                    .font(.system(size: design.type(24), weight: .black, design: .rounded))
                    .foregroundStyle(design.text)
                Text("Less scroll. More life.")
                    .font(.system(size: design.type(15), weight: .semibold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.48))
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(isLocked ? design.signal : design.primary)
                    .frame(width: 8, height: 8)
                Text(isLocked ? "Locked" : "Open")
                    .font(.system(size: design.type(12), weight: .black, design: .rounded))
            }
            .padding(.horizontal, design.spacing(12))
            .frame(height: design.spacing(36))
            .background(design.muted, in: RoundedRectangle(cornerRadius: design.radius(6)))
        }
    }

    private var statusCard: some View {
        let persona = FruitPersona.forStatus(isLocked: isLocked)
        let base = design.primaryFor(locked: isLocked)
        let accent = design.secondaryFor(locked: isLocked)

        return HStack(alignment: .center, spacing: design.spacing(16)) {
            VStack(alignment: .leading, spacing: design.spacing(6)) {
                Text(isLocked ? "Focus is on" : "Ready to focus")
                    .font(.system(size: design.type(12), weight: .black, design: .rounded))
                    .foregroundStyle(accent.opacity(isLocked ? 0.85 : 0.72))
                Text(isLocked ? "The noise is blocked." : "Tap your tag to begin.")
                    .font(.system(size: design.type(22), weight: .black, design: .rounded))
                    .foregroundStyle(isLocked ? design.surface : design.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isLocked
                     ? "Scan your tag to unlock."
                     : "One scan locks. Next unlocks.")
                    .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
                    .foregroundStyle(isLocked ? design.surface.opacity(0.72) : design.text.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: design.spacing(8))

            FruitCharacter(fruit: persona.fruit, personality: persona.personality, size: design.hero(100))
        }
        .padding(design.spacing(18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(base, in: RoundedRectangle(cornerRadius: design.radius(14)))
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isLocked)
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: design.spacing(14)) {
            HStack {
                Text("Block list")
                    .font(.system(size: design.type(13), weight: .black, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.72))
                Spacer()
                Text("\(selectedApps.count) selected")
                    .font(.system(size: design.type(12), weight: .bold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.38))
            }

            HStack(spacing: design.spacing(14)) {
                FruitCharacter(fruit: .strawberry, personality: .freckled, size: design.hero(72))

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedApps.isEmpty ? "Choose apps" : "Blocked apps")
                        .font(.system(size: design.type(14), weight: .black, design: .rounded))
                    Text(selectedAppsDescription)
                        .font(.system(size: design.type(11), weight: .semibold, design: .rounded))
                        .opacity(0.55)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(design.text)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: design.type(13), weight: .bold))
                    .foregroundStyle(design.text.opacity(0.35))
            }
            .padding(design.spacing(16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(design.accentPink.opacity(0.4), in: RoundedRectangle(cornerRadius: design.radius(12)))
            .onTapGesture { showAppPicker = true }
        }
    }

    private var actionSection: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isLocked.toggle()
            }
            showPopup = true
        } label: {
            Label(
                isLocked ? "Demo: scan to unlock" : "Demo: scan to lock",
                systemImage: "wave.3.right"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryCTAStyle(tokens: design, isEnabled: !selectedApps.isEmpty))
        .disabled(selectedApps.isEmpty)
    }

    private var footer: some View {
        Text("Simulator demo: app selection, BLE signals, and scans are simulated. Hardware requires a physical iPhone.")
            .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
            .foregroundStyle(design.text.opacity(0.36))
            .multilineTextAlignment(.center)
    }

    private var selectedAppsDescription: String {
        let names = DemoApp.allCases
            .filter(selectedApps.contains)
            .map(\.name)

        if names.isEmpty {
            return "Pick the apps that steal your time"
        }
        if names.count <= 3 {
            return names.joined(separator: ", ")
        }
        return "\(names.prefix(3).joined(separator: ", ")) +\(names.count - 3)"
    }

    private var demoPodsSection: some View {
        VStack(alignment: .leading, spacing: design.spacing(14)) {
            HStack {
                Text("BLE pods")
                    .font(.system(size: design.type(13), weight: .black, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.72))
                Spacer()
                Text("\(demoPods.count) paired")
                    .font(.system(size: design.type(12), weight: .bold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.38))
            }

            VStack(spacing: 12) {
                ForEach($demoPods) { $pod in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            pod.isNear.toggle()
                            pod.rssi = pod.isNear ? -63 : -82
                            isLocked = demoPods.contains(where: \.isNear)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(pod.isNear ? design.primary : design.muted)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(pod.isNear ? design.secondary : design.text.opacity(0.55))
                                }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(pod.room)
                                    .font(.system(size: design.type(15), weight: .bold, design: .rounded))
                                    .foregroundStyle(design.text)
                                Text(pod.isNear ? "Inside blocking range" : "Outside blocking range")
                                    .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
                                    .foregroundStyle(design.text.opacity(0.45))
                            }

                            Spacer()

                            Text("\(pod.rssi) dBm")
                                .font(.system(size: design.type(12), weight: .black, design: .monospaced))
                                .foregroundStyle(pod.isNear ? design.secondary : design.text.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)

                    if pod.id != demoPods.last?.id {
                        Divider().opacity(0.35)
                    }
                }

                Button {
                    let number = demoPods.count + 1
                    demoPods.append(
                        DemoPod(room: "Room \(number)", rssi: -85, isNear: false)
                    )
                } label: {
                    Label("Add demo pod", systemImage: "plus.circle.fill")
                        .font(.system(size: design.type(12), weight: .black, design: .rounded))
                        .foregroundStyle(design.text.opacity(0.58))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
            }
            .padding(design.spacing(16))
            .background(design.accentBlue.opacity(0.28), in: RoundedRectangle(cornerRadius: design.radius(10)))
        }
    }
}

private struct DemoPod: Identifiable {
    let id = UUID()
    var room: String
    var rssi: Int
    var isNear: Bool
}

private struct DemoAppPicker: View {
    @Binding var selectedApps: Set<DemoApp>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTokens) private var design
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(DemoApp.allCases) { app in
                        Button {
                            if selectedApps.contains(app) {
                                selectedApps.remove(app)
                            } else {
                                selectedApps.insert(app)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: app.symbol)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(design.secondary)
                                        .frame(width: 42, height: 42)
                                        .background(design.primary, in: RoundedRectangle(cornerRadius: 12))

                                    Spacer()

                                    Image(systemName: selectedApps.contains(app)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(
                                            selectedApps.contains(app)
                                                ? design.secondary
                                                : design.text.opacity(0.25)
                                        )
                                }

                                Text(app.name)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(design.text)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                            .background(design.muted, in: RoundedRectangle(cornerRadius: 18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(
                                        selectedApps.contains(app)
                                            ? design.secondary.opacity(0.8)
                                            : design.text.opacity(0.06),
                                        lineWidth: selectedApps.contains(app) ? 2 : 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(design.surface)
            .navigationTitle("Blocked apps")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private enum DemoApp: String, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case youtube
    case snapchat
    case x
    case reddit
    case facebook

    var id: Self { self }

    var name: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .snapchat: "Snapchat"
        case .x: "X"
        case .reddit: "Reddit"
        case .facebook: "Facebook"
        }
    }

    var symbol: String {
        switch self {
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        case .youtube: "play.fill"
        case .snapchat: "message.fill"
        case .x: "xmark"
        case .reddit: "bubble.left.and.bubble.right.fill"
        case .facebook: "person.2.fill"
        }
    }
}
