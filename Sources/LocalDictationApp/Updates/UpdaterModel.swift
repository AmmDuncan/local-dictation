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
        // A debug build runs as an unsigned bare binary with no bundled, signed
        // Sparkle helper, so starting the updater just fails ("The updater failed
        // to start") and pops a dialog that steals focus. Skip auto-start in DEBUG;
        // release .apps (built `-c release` by build-app.sh) update normally.
        #if DEBUG
        let shouldStart = false
        #else
        let shouldStart = true
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: shouldStart,
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
