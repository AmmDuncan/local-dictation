import Combine
import Sparkle
import SwiftUI

/// Owns the Sparkle updater — started at launch so scheduled background checks
/// run — and drives the "Check for Updates…" menu item (enabled state mirrors
/// the updater so it greys out while a check is already in flight).
@MainActor
final class UpdaterModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
