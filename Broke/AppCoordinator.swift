import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    let model = FocusLockModel()
    let proximity = BLEProximityManager()

    private var cancellables = Set<AnyCancellable>()

    init() {
        proximity.$isNear
            .removeDuplicates()
            .sink { [weak model] isNear in
                model?.updateBLEProximity(isNear: isNear)
            }
            .store(in: &cancellables)

        // The model ignores proximity until the mode says pods count, and the
        // publisher above de-duplicates — so finishing onboarding while already
        // standing next to the pod would otherwise leave you unlocked until you
        // walked out and back in. Re-push the current reading on any mode change.
        model.$lockMode
            .removeDuplicates()
            .sink { [weak model, weak proximity] _ in
                guard let proximity else { return }
                model?.updateBLEProximity(isNear: proximity.isNear)
            }
            .store(in: &cancellables)
    }
}
