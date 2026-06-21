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
    }
}
