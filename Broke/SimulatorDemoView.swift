import SwiftUI

struct SimulatorDemoView: View {
    @State private var isLocked = false
    @State private var showPopup = false
    @State private var showAppPicker = false
    @State private var selectedApps: Set<DemoApp> = [.instagram, .tiktok, .youtube]

    var body: some View {
        ZStack {
            Color(red: 0.965, green: 0.95, blue: 0.91)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BROKE")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .tracking(3.2)
                            Text("Less scroll. More life.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.black.opacity(0.48))
                        }
                        Spacer()
                        Image(systemName: isLocked ? "lock.fill" : "circle.dotted")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(isLocked ? .red : .black, in: Circle())
                    }

                    ZStack {
                        Circle()
                            .stroke(.black.opacity(0.08), lineWidth: 1)
                            .frame(width: 174, height: 174)
                        Circle()
                            .fill(isLocked ? .red : .black)
                            .frame(width: 142, height: 142)
                            .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
                        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.top, 42)

                    Text(isLocked ? "FOCUS IS ON" : "READY TO FOCUS")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(2.4)
                        .foregroundStyle(isLocked ? .red : .black.opacity(0.55))
                        .padding(.top, 24)

                    Text(isLocked ? "The noise is blocked." : "Tap your tag to begin.")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .padding(.top, 8)

                    Text(isLocked
                         ? "Scan the same NFC tag to unlock your apps."
                         : "One scan locks your chosen apps. The next brings them back.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)

                    HStack {
                        Text("BLOCK LIST")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(.black.opacity(0.52))
                        Spacer()
                        Text("\(selectedApps.count) selected")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.38))
                    }
                    .padding(.top, 38)

                    Button {
                        showAppPicker = true
                    } label: {
                        HStack(spacing: 15) {
                            Image(systemName: "square.grid.2x2.fill")
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.black, in: RoundedRectangle(cornerRadius: 14))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(selectedApps.isEmpty ? "Choose apps" : "Edit blocked apps")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black)
                                Text(selectedAppsDescription)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.black.opacity(0.45))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.black.opacity(0.35))
                        }
                    }
                    .padding(14)
                    .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.black.opacity(0.08), lineWidth: 1)
                    }
                    .padding(.top, 13)
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            isLocked.toggle()
                        }
                        showPopup = true
                    } label: {
                        Label(
                            isLocked ? "DEMO: SCAN TO UNLOCK" : "DEMO: SCAN TO LOCK",
                            systemImage: "wave.3.right"
                        )
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(.black, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .padding(.top, 30)
                    .disabled(selectedApps.isEmpty)
                    .opacity(selectedApps.isEmpty ? 0.35 : 1)

                    Text("Simulator demo: app selection and scans are simulated. NFC requires a physical iPhone.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.36))
                        .padding(.top, 24)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
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
}

private struct DemoAppPicker: View {
    @Binding var selectedApps: Set<DemoApp>
    @Environment(\.dismiss) private var dismiss
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
                                        .foregroundStyle(.white)
                                        .frame(width: 42, height: 42)
                                        .background(app.color, in: RoundedRectangle(cornerRadius: 12))

                                    Spacer()

                                    Image(systemName: selectedApps.contains(app)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(
                                            selectedApps.contains(app)
                                                ? .black
                                                : .gray.opacity(0.4)
                                        )
                                }

                                Text(app.name)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                            .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(
                                        selectedApps.contains(app)
                                            ? .black.opacity(0.8)
                                            : .black.opacity(0.06),
                                        lineWidth: selectedApps.contains(app) ? 2 : 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
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

    var color: Color {
        switch self {
        case .instagram: .purple
        case .tiktok: .black
        case .youtube: .red
        case .snapchat: .yellow
        case .x: .black
        case .reddit: .orange
        case .facebook: .blue
        }
    }
}
