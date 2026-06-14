import Combine
import Foundation
import Sparkle

struct AppUpdate: Equatable {
    let version: String
}

@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    @Published private(set) var availableUpdate: AppUpdate?

    private let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func startCheckingForUpdates() {
        // Sparkle owns its automatic check schedule via Info.plist settings.
    }

    func stopCheckingForUpdates() {
        // Keep Sparkle's updater alive for the process lifetime.
    }

    func openAvailableUpdate() {
        checkForUpdates()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
