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

    fileprivate var animationName: String {
        "strawberry_\(rawValue)"
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

    /// The state to return to after a one-shot finishes.
    var state: MascotState
    /// Optional one-shot fired when `oneShotTrigger` changes.
    var oneShotState: MascotState?
    var oneShotTrigger: Int = 0

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

        context.coordinator.baseState = state
        context.coordinator.lastOneShotTrigger = oneShotTrigger
        context.coordinator.playBase(state, in: animationView)
        return container
    }

    func updateUIView(_ container: ContainerView, context: Context) {
        let coordinator = context.coordinator
        let animationView = container.animationView
        coordinator.baseState = state

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

        var baseState: MascotState = .idle
        var currentState: MascotState?
        var lastOneShotTrigger = 0
        var isPlayingOneShot = false
        private var playbackGeneration = 0

        func playBase(_ state: MascotState, in view: LottieAnimationView) {
            playbackGeneration += 1
            isPlayingOneShot = false

            guard load(state, in: view) else { return }

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
            guard let animation = LottieAnimation.named(
                state.animationName,
                bundle: .main
            ) else {
                Self.logger.error("Failed to load Lottie mascot clip: \(state.animationName, privacy: .public)")

                // Preserve a working clip. On first load, make one safe attempt
                // to establish idle without recursively retrying it.
                if view.animation == nil,
                   state != .idle,
                   let idleAnimation = LottieAnimation.named(
                       MascotState.idle.animationName,
                       bundle: .main
                   ) {
                    currentState = .idle
                    view.animation = idleAnimation
                    view.currentProgress = 0
                    view.loopMode = .loop
                    view.play()
                } else if view.animation == nil, state != .idle {
                    Self.logger.error("Failed to load fallback Lottie mascot clip: \(MascotState.idle.animationName, privacy: .public)")
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
