import Lottie
import OSLog
import SwiftUI

/// Prototype state surface for the image-layer strawberry Lottie pipeline.
enum MascotState: String, Equatable {
    case idle
    case onDuty
    case celebrate
    case surprised
    case blocking

    fileprivate func animationName(for fruit: FruitKind) -> String {
        "\(fruit.rawValue)_\(rawValue)"
    }

    fileprivate var loops: Bool {
        switch self {
        case .idle, .onDuty, .blocking:
            true
        case .celebrate, .surprised:
            false
        }
    }
}

/// STRAWBERRY-ONLY PROTOTYPE. Existing SwiftUI mascot views remain available
/// while this validates bundle loading, image providers, and state playback.
struct LottieMascotView: UIViewRepresentable {
    final class ContainerView: UIView {
        let animationView: LottieAnimationView

        override init(frame: CGRect) {
            animationView = LottieAnimationView()
            super.init(frame: frame)

            backgroundColor = .clear
            clipsToBounds = true

            animationView.translatesAutoresizingMaskIntoConstraints = false
            animationView.backgroundColor = .clear
            animationView.contentMode = .scaleAspectFit
            animationView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            animationView.setContentHuggingPriority(.defaultLow, for: .vertical)
            animationView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            animationView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

            addSubview(animationView)
            NSLayoutConstraint.activate([
                animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
                animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
                animationView.topAnchor.constraint(equalTo: topAnchor),
                animationView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    /// Which fruit's rig to render. Each fruit has a `<fruit>_idle.json`; only
    /// the strawberry currently has the extra state clips (onDuty/celebrate/etc.),
    /// so other fruits gracefully fall back to their own idle.
    var fruit: FruitKind = .strawberry
    /// The state to return to after a one-shot finishes.
    var state: MascotState
    /// Optional one-shot fired when `oneShotTrigger` changes.
    var oneShotState: MascotState?
    var oneShotTrigger: Int = 0

    /// Honoured here rather than at each call site. `ClayFruitView` already
    /// swapped in static art under Reduce Motion, but the status card, the
    /// onboarding steps and the gallery build the rig directly — so the
    /// biggest animation in the app was the one ignoring the setting.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ContainerView {
        let container = ContainerView()
        let animationView = container.animationView
        animationView.imageProvider = BundleImageProvider(
            bundle: .main,
            searchPath: nil
        )

        context.coordinator.fruit = fruit
        context.coordinator.baseState = state
        context.coordinator.lastOneShotTrigger = oneShotTrigger
        context.coordinator.isMotionReduced = reduceMotion
        context.coordinator.playBase(state, in: animationView)
        return container
    }

    func updateUIView(_ container: ContainerView, context: Context) {
        let coordinator = context.coordinator
        let animationView = container.animationView
        // If the fruit changed (e.g. mascot picker), reload from scratch.
        let fruitChanged = coordinator.fruit != fruit
        let motionChanged = coordinator.isMotionReduced != reduceMotion
        coordinator.fruit = fruit
        coordinator.baseState = state
        coordinator.isMotionReduced = reduceMotion
        if fruitChanged || motionChanged {
            coordinator.playBase(state, in: animationView)
            return
        }

        // Under Reduce Motion the rig is parked on its first frame, so a
        // celebrate burst would be a jump cut rather than an animation.
        if reduceMotion {
            return
        }

        if let oneShotState,
           !oneShotState.loops,
           oneShotTrigger != coordinator.lastOneShotTrigger {
            coordinator.lastOneShotTrigger = oneShotTrigger
            coordinator.playOneShot(oneShotState, in: animationView)
        } else if !coordinator.isPlayingOneShot,
                  coordinator.currentState != state {
            coordinator.playBase(state, in: animationView)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ContainerView,
        context: Context
    ) -> CGSize? {
        let intrinsicSize = uiView.animationView.intrinsicContentSize
        let aspectRatio = intrinsicSize.width > 0 && intrinsicSize.height > 0
            ? intrinsicSize.width / intrinsicSize.height
            : 1
        let defaultLength: CGFloat = 104

        switch (proposal.width, proposal.height) {
        case let (width?, height?):
            return CGSize(width: width, height: height)
        case let (width?, nil):
            return CGSize(width: width, height: width / aspectRatio)
        case let (nil, height?):
            return CGSize(width: height * aspectRatio, height: height)
        case (nil, nil):
            return CGSize(width: defaultLength * aspectRatio, height: defaultLength)
        }
    }

    final class Coordinator {
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "Broke",
            category: "LottieMascot"
        )

        var fruit: FruitKind = .strawberry
        var baseState: MascotState = .idle
        var currentState: MascotState?
        var lastOneShotTrigger = 0
        var isPlayingOneShot = false
        var isMotionReduced = false
        private var playbackGeneration = 0

        func playBase(_ state: MascotState, in view: LottieAnimationView) {
            playbackGeneration += 1
            isPlayingOneShot = false

            guard load(state, in: view) else { return }

            // Reduce Motion: hold the pose instead of looping. The character
            // is still there and still on model — it just stops moving.
            guard !isMotionReduced else {
                view.currentProgress = 0
                return
            }

            view.loopMode = state.loops ? .loop : .playOnce
            view.play()
        }

        func playOneShot(_ state: MascotState, in view: LottieAnimationView) {
            playbackGeneration += 1
            let generation = playbackGeneration
            isPlayingOneShot = true

            guard load(state, in: view) else {
                isPlayingOneShot = false
                return
            }

            view.loopMode = .playOnce
            view.play { [weak self, weak view] finished in
                guard let self,
                      let view,
                      self.playbackGeneration == generation else { return }
                self.isPlayingOneShot = false
                if finished {
                    self.playBase(self.baseState, in: view)
                }
            }
        }

        @discardableResult
        private func load(_ state: MascotState, in view: LottieAnimationView) -> Bool {
            let clipName = state.animationName(for: fruit)
            guard let animation = LottieAnimation.named(
                clipName,
                bundle: .main
            ) else {
                Self.logger.error("Failed to load Lottie mascot clip: \(clipName, privacy: .public)")

                // This fruit lacks this state (only strawberry has non-idle
                // clips). Fall back to THIS fruit's own idle clip.
                let idleName = MascotState.idle.animationName(for: fruit)
                if state != .idle,
                   let idleAnimation = LottieAnimation.named(idleName, bundle: .main) {
                    view.stop()
                    currentState = .idle
                    view.animation = idleAnimation
                    view.currentProgress = 0
                    view.loopMode = .loop
                    if !isMotionReduced { view.play() }
                } else if state != .idle {
                    Self.logger.error("Failed to load fallback Lottie mascot clip: \(idleName, privacy: .public)")
                }
                return false
            }

            view.stop()
            currentState = state
            view.animation = animation
            view.currentProgress = 0
            return true
        }
    }
}
