import FamilyControls
import SwiftUI

/// First-run setup. Walks through what Broke does, makes you pick a mascot,
/// commit to a lock mode (permanently), choose apps, and grant Screen Time.
struct OnboardingView: View {
    @ObservedObject var model: FocusLockModel
    @ObservedObject var proximity: BLEProximityManager
    let finish: () -> Void

    @Environment(\.designTokens) private var design
    @AppStorage(AppPreferenceKey.selectedMascot) private var selectedMascotRawValue = FruitKind.strawberry.rawValue

    @State private var step: Step = OnboardingView.initialStep
    @State private var chosenMode: LockMode? = OnboardingView.initialMode
    @State private var isChoosingApps = false
    @State private var isConfirmingMode = false

    /// DEBUG hook: launch with ONBOARD_STEP=<name> (and optionally
    /// ONBOARD_MODE=<tag|pod|timer>) to jump straight to one screen for QA.
    fileprivate static var initialStep: Step {
#if DEBUG
        if let raw = ProcessInfo.processInfo.environment["ONBOARD_STEP"],
           let s = Step(name: raw) { return s }
#endif
        return .welcome
    }

    fileprivate static var initialMode: LockMode? {
#if DEBUG
        if let raw = ProcessInfo.processInfo.environment["ONBOARD_MODE"] {
            return LockMode(rawValue: raw)
        }
#endif
        return nil
    }

    fileprivate enum Step: Int, CaseIterable {
        case welcome, how, mode, confirmMode, mascot, apps, hardware, done

        init?(name: String) {
            switch name {
            case "welcome": self = .welcome
            case "how": self = .how
            case "mode": self = .mode
            case "confirmMode": self = .confirmMode
            case "mascot": self = .mascot
            case "apps": self = .apps
            case "hardware": self = .hardware
            case "done": self = .done
            default: return nil
            }
        }

        var progressIndex: Int {
            switch self {
            case .welcome, .how: 0
            case .mode, .confirmMode: 1
            case .mascot: 2
            case .apps: 3
            case .hardware, .done: 4
            }
        }
    }

    private var mascot: FruitKind {
        FruitKind(rawValue: selectedMascotRawValue) ?? .strawberry
    }

    var body: some View {
        ZStack {
            PlayfulBackdrop(tokens: design)

            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, design.spacing(24))
                    .padding(.top, design.spacing(14))

                ScrollView {
                    content
                        .padding(.horizontal, design.spacing(24))
                        .padding(.top, design.spacing(24))
                        .padding(.bottom, design.spacing(20))
                }

                footer
                    .padding(.horizontal, design.spacing(24))
                    .padding(.bottom, design.spacing(16))
            }
        }
        .preferredColorScheme(.light)
        .familyActivityPicker(isPresented: $isChoosingApps, selection: $model.selection)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
    }

    // MARK: - Chrome

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(i <= step.progressIndex ? design.primary : design.text.opacity(0.12))
                    .frame(height: 5)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .how: howStep
        case .mode: modeStep
        case .confirmMode: confirmModeStep
        case .mascot: mascotStep
        case .apps: appsStep
        case .hardware: hardwareStep
        case .done: doneStep
        }
    }

    private var footer: some View {
        VStack(spacing: design.spacing(10)) {
            Button(action: advance) {
                Text(primaryTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTAStyle(tokens: design, isEnabled: canAdvance))
            .disabled(!canAdvance)

            if let back = previousStep {
                Button("Back") { step = back }
                    .font(.system(size: design.type(12), weight: .black, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.42))
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: design.spacing(18)) {
            LottieMascotView(fruit: mascot, state: .idle)
                .frame(height: design.hero(210))

            Text("Broke")
                .font(.system(size: design.type(44), weight: .black, design: .rounded))
                .foregroundStyle(design.text)

            Text("A social media blocker with a bouncer.")
                .font(.system(size: design.type(17), weight: .bold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.62))
                .multilineTextAlignment(.center)

            Text("You pick the apps. You pick how they get locked. After that, Broke is the one holding the keys — and it isn't a pushover.")
                .font(.system(size: design.type(14), weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.46))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, design.spacing(6))
        }
        .frame(maxWidth: .infinity)
    }

    private var howStep: some View {
        VStack(alignment: .leading, spacing: design.spacing(22)) {
            stepTitle("How this works", "Three moving parts, that's it.")

            howRow("1", "square.stack.3d.up.fill", "Build a block list",
                   "The apps and sites eating your day. Make as many lists as you like.")
            howRow("2", "lock.fill", "Choose your lock",
                   "A tag, a pod, both, or no hardware and a thirty second wait.")
            howRow("3", "figure.walk.motion", "Go live your life",
                   "Those apps stop opening. Your mascot handles the door.")
        }
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: design.spacing(16)) {
            stepTitle("Pick your lock", "How should Broke stop you?")

            ForEach(LockMode.allCases) { mode in
                modeCard(mode)
            }

            HStack(alignment: .top, spacing: design.spacing(10)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: design.type(13), weight: .bold))
                    .foregroundStyle(design.signal)
                Text("This one sticks. Changing it later means deleting the app — that's the point.")
                    .font(.system(size: design.type(12), weight: .bold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(design.spacing(14))
            .background(design.accentPink.opacity(0.28), in: RoundedRectangle(cornerRadius: design.radius(8)))
        }
    }

    private func modeCard(_ mode: LockMode) -> some View {
        let selected = chosenMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                chosenMode = mode
            }
        } label: {
            VStack(alignment: .leading, spacing: design.spacing(8)) {
                HStack(spacing: design.spacing(11)) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: design.type(17), weight: .bold))
                        .foregroundStyle(selected ? design.secondary : design.primary)
                        .frame(width: 40, height: 40)
                        .background(selected ? design.primary : design.primary.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.title)
                            .font(.system(size: design.type(17), weight: .black, design: .rounded))
                            .foregroundStyle(design.text)
                        Text(mode.tagline)
                            .font(.system(size: design.type(11), weight: .black, design: .rounded))
                            .foregroundStyle(design.primary)
                    }

                    Spacer(minLength: 0)

                    if mode.requiresHardware {
                        Text("NEEDS HARDWARE")
                            .font(.system(size: design.type(8), weight: .black, design: .rounded))
                            .foregroundStyle(design.text.opacity(0.42))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(design.muted, in: Capsule())
                    }
                }

                Text(mode.blurb)
                    .font(.system(size: design.type(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            .padding(design.spacing(16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(design.surface.opacity(selected ? 1 : 0.82),
                        in: RoundedRectangle(cornerRadius: design.radius(12)))
            .overlay {
                RoundedRectangle(cornerRadius: design.radius(12))
                    .stroke(selected ? design.primary : design.text.opacity(0.08),
                            lineWidth: selected ? 2.5 : 1)
            }
        }
        .buttonStyle(PressButtonStyle())
    }

    private var confirmModeStep: some View {
        VStack(spacing: design.spacing(18)) {
            Image(systemName: chosenMode?.symbol ?? "lock.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(design.primary)
                .frame(width: 108, height: 108)
                .background(design.primary.opacity(0.14), in: Circle())
                .padding(.top, design.spacing(10))

            Text("Locking in \(chosenMode?.title ?? "")")
                .font(.system(size: design.type(27), weight: .black, design: .rounded))
                .foregroundStyle(design.text)
                .multilineTextAlignment(.center)

            Text("This is how Broke works on this phone now. No settings screen, no renegotiating at midnight.")
                .font(.system(size: design.type(14), weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Toggle(isOn: $isConfirmingMode) {
                Text("Yeah, I'm sure.")
                    .font(.system(size: design.type(14), weight: .black, design: .rounded))
                    .foregroundStyle(design.text)
            }
            .tint(design.primary)
            .padding(design.spacing(16))
            .background(design.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: design.radius(10)))
        }
    }

    private var mascotStep: some View {
        VStack(alignment: .leading, spacing: design.spacing(16)) {
            stepTitle("Pick your bouncer", "They'll be the one guarding your apps.")

            LottieMascotView(fruit: mascot, state: .idle)
                .frame(height: design.hero(170))
                .frame(maxWidth: .infinity)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: design.spacing(12)) {
                ForEach(FruitKind.allCases) { fruit in
                    let selected = fruit.rawValue == selectedMascotRawValue
                    Button {
                        selectedMascotRawValue = fruit.rawValue
                    } label: {
                        VStack(spacing: 5) {
                            Image(fruit.clayAssetName)
                                .resizable().scaledToFit()
                                .frame(height: design.hero(46))
                                .padding(5)
                                .frame(maxWidth: .infinity)
                                .background(selected ? design.primary.opacity(0.16) : design.muted.opacity(0.6),
                                            in: RoundedRectangle(cornerRadius: design.radius(9)))
                                .overlay {
                                    RoundedRectangle(cornerRadius: design.radius(9))
                                        .stroke(selected ? design.primary : .clear, lineWidth: 2)
                                }
                            Text(fruit.name)
                                .font(.system(size: design.type(9), weight: .black, design: .rounded))
                                .foregroundStyle(design.text.opacity(0.7))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(PressButtonStyle())
                }
            }
        }
    }

    private var appsStep: some View {
        VStack(alignment: .leading, spacing: design.spacing(16)) {
            stepTitle("What's off limits?", "Be honest about the ones that get you.")

            if !model.hasScreenTimeAuthorization {
                Button {
                    model.requestAuthorization()
                } label: {
                    HStack(spacing: design.spacing(11)) {
                        Image(systemName: "hourglass.badge.exclamationmark")
                            .font(.system(size: design.type(15), weight: .bold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow Screen Time access")
                                .font(.system(size: design.type(14), weight: .black, design: .rounded))
                            Text("Broke can't block anything without it.")
                                .font(.system(size: design.type(11), weight: .semibold, design: .rounded))
                                .opacity(0.7)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(design.secondary)
                    .padding(design.spacing(15))
                    .background(design.primary, in: RoundedRectangle(cornerRadius: design.radius(9)))
                }
                .buttonStyle(PressButtonStyle())
            } else {
                Label("Screen Time access granted", systemImage: "checkmark.seal.fill")
                    .font(.system(size: design.type(13), weight: .black, design: .rounded))
                    // `secondary` over a 35%-alpha chip is near-invisible; the
                    // confirmation you just earned should be legible.
                    .foregroundStyle(design.text)
                    .padding(design.spacing(14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(design.accentBlue.opacity(0.35), in: RoundedRectangle(cornerRadius: design.radius(9)))
            }

            Button {
                isChoosingApps = true
            } label: {
                HStack(spacing: design.spacing(11)) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: design.type(15), weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hasSelection ? "Edit your block list" : "Choose apps to block")
                            .font(.system(size: design.type(14), weight: .black, design: .rounded))
                        Text(model.hasSelection
                             ? "\(model.selectedItemCount) picked so far"
                             : "Apps, categories, or whole websites")
                            .font(.system(size: design.type(11), weight: .semibold, design: .rounded))
                            .opacity(0.62)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(design.text.opacity(0.78))
                .padding(design.spacing(15))
                .background(design.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: design.radius(9)))
                .overlay {
                    RoundedRectangle(cornerRadius: design.radius(9))
                        .stroke(design.text.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(PressButtonStyle())

            Text("You can add more lists later — a strict one for work, a looser one for weekends.")
                .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hardwareStep: some View {
        VStack(alignment: .leading, spacing: design.spacing(16)) {
            switch chosenMode ?? .timer {
            case .tag:
                stepTitle("Pair your tag", "Hold your Broke tag against the top of your phone.")
                tagPairingCard

            case .pod:
                stepTitle("Find your pod", "Power it on and keep it in the room you focus in.")
                podPairingCard

            case .both:
                stepTitle("Set up both", "The tag travels with you. The pod holds the room.")
                tagPairingCard
                podPairingCard
                ruleRow("lock.shield.fill", "Either one can lock you.",
                        "Both have to agree to unblock you: leave the room, then tap your tag.")
                    .padding(design.spacing(14))
                    .background(design.surface.opacity(0.9),
                                in: RoundedRectangle(cornerRadius: design.radius(10)))

            case .timer:
                stepTitle("No hardware needed", "Here's the deal you just made.")
                VStack(alignment: .leading, spacing: design.spacing(14)) {
                    ruleRow("lock.fill", "Locking is instant.",
                            "One tap and they're gone.")
                    ruleRow("hourglass", "Unlocking takes 30 seconds.",
                            "Your apps stay blocked the whole countdown.")
                    ruleRow("hand.thumbsup.fill", "You can always back out.",
                            "Cancel the countdown, keep your streak. Most people do.")
                }
                .padding(design.spacing(16))
                .background(design.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: design.radius(12)))
            }
        }
    }

    /// Pulled out of the mode switch so combined mode can show both without
    /// duplicating either.
    private var tagPairingCard: some View {
        setupCard(
            symbol: model.hasPairedTag ? "checkmark.seal.fill" : "wave.3.right",
            title: model.hasPairedTag ? "Tag paired" : "Pair NFC tag",
            detail: model.hasPairedTag
                ? "Only this tag can flip your lock now."
                : "Tap below, then hold the tag to your phone.",
            done: model.hasPairedTag
        ) { model.pairTag() }
    }

    @ViewBuilder
    private var podPairingCard: some View {
        if proximity.pairedPodCount > 0 {
            setupCard(symbol: "checkmark.seal.fill", title: "Pod paired",
                      detail: "Blocks automatically whenever you're in range.",
                      done: true) {}
        } else if let found = proximity.discoveredUnpairedPods.first {
            setupCard(symbol: "sensor.tag.radiowaves.forward",
                      title: "Pair \(found.podID)",
                      detail: "Found a Broke pod nearby. Tap to claim it.",
                      done: false) { proximity.pairPod(found.podID, room: "My room") }
        } else {
            setupCard(symbol: "antenna.radiowaves.left.and.right",
                      title: "Looking for pods…",
                      detail: "Make sure it's powered on and nearby. You can also pair it later.",
                      done: false) {}
        }
    }

    private var doneStep: some View {
        VStack(spacing: design.spacing(18)) {
            LottieMascotView(fruit: mascot, state: .onDuty)
                .frame(height: design.hero(200))

            Text("You're all set")
                .font(.system(size: design.type(32), weight: .black, design: .rounded))
                .foregroundStyle(design.text)

            Text("\(mascot.name.capitalized)'s on the door. Be nice — they're only doing what you asked.")
                .font(.system(size: design.type(15), weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Small pieces

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: design.type(28), weight: .black, design: .rounded))
                .foregroundStyle(design.text)
            Text(subtitle)
                .font(.system(size: design.type(14), weight: .semibold, design: .rounded))
                .foregroundStyle(design.text.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func howRow(_ number: String, _ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: design.spacing(14)) {
            ZStack {
                Circle().fill(design.primary.opacity(0.14)).frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: design.type(17), weight: .bold))
                    .foregroundStyle(design.primary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: design.type(16), weight: .black, design: .rounded))
                    .foregroundStyle(design.text)
                Text(body)
                    .font(.system(size: design.type(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
    }

    private func ruleRow(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: design.spacing(12)) {
            Image(systemName: symbol)
                .font(.system(size: design.type(14), weight: .bold))
                .foregroundStyle(design.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: design.type(14), weight: .black, design: .rounded))
                    .foregroundStyle(design.text)
                Text(body)
                    .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
                    .foregroundStyle(design.text.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setupCard(symbol: String, title: String, detail: String,
                           done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: design.spacing(13)) {
                Image(systemName: symbol)
                    .font(.system(size: design.type(18), weight: .bold))
                    .foregroundStyle(done ? design.secondary : design.primary)
                    .frame(width: 46, height: 46)
                    .background(done ? design.primary : design.primary.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: design.type(16), weight: .black, design: .rounded))
                        .foregroundStyle(design.text)
                    Text(detail)
                        .font(.system(size: design.type(12), weight: .semibold, design: .rounded))
                        .foregroundStyle(design.text.opacity(0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(design.spacing(16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(design.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: design.radius(12)))
            .overlay {
                RoundedRectangle(cornerRadius: design.radius(12))
                    .stroke(design.text.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(PressButtonStyle())
        .disabled(done)
    }

    // MARK: - Flow

    private var primaryTitle: String {
        switch step {
        case .welcome: "GET STARTED"
        case .how: "MAKES SENSE"
        case .mode: "CONTINUE"
        case .confirmMode: "LOCK IT IN"
        case .mascot: "GOOD CHOICE"
        case .apps: "CONTINUE"
        case .hardware: "CONTINUE"
        case .done: "OPEN BROKE"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .mode: chosenMode != nil
        case .confirmMode: isConfirmingMode
        case .apps: model.hasSelection
        default: true
        }
    }

    private var previousStep: Step? {
        switch step {
        case .welcome, .done: nil
        case .how: .welcome
        case .mode: .how
        case .confirmMode: .mode
        // The mode is already committed by this point, so there is no going back.
        case .mascot: nil
        case .apps: .mascot
        case .hardware: .apps
        }
    }

    private func advance() {
        switch step {
        case .welcome: step = .how
        case .how: step = .mode
        case .mode: step = .confirmMode
        case .confirmMode:
            if let chosenMode {
                LockModeStore.commit(chosenMode)
                model.adoptCommittedLockMode()
            }
            step = .mascot
        case .mascot: step = .apps
        case .apps: step = .hardware
        case .hardware: step = .done
        case .done:
            LockModeStore.hasOnboarded = true
            finish()
        }
    }
}
