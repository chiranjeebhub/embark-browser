import AppKit
import Observation
import Sparkle
import SwiftUI

/// Automatic updates with Sparkle. Builds from GitHub Releases read the appcast published with
/// each release and check once a day; updates download in the background and install when
/// Embark quits. Builds without an update key, such as most builds made from source, leave
/// the updater off. See docs/RELEASING.md.
@MainActor @Observable
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    enum Status: Equatable {
        case idle
        case upToDate
        /// Found and being downloaded, or waiting for the person to choose in Sparkle's window.
        case found(version: String)
        /// Downloaded; installs at quit, or now with `installNow()`.
        case ready(version: String)
        case failed(String)
    }

    /// False when the build has no feed or public key, so it can't verify updates.
    let isAvailable: Bool
    private(set) var status = Status.idle
    private(set) var isChecking = false
    private(set) var lastCheck: Date?

    var checksAutomatically = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    var installsAutomatically = false {
        didSet { controller?.updater.automaticallyDownloadsUpdates = installsAutomatically }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var installNowHandler: (() -> Void)?
    @ObservationIgnored private var sessionObservation: NSKeyValueObservation?

    private override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = info["SUPublicEDKey"] as? String ?? ""
        let feed = info["SUFeedURL"] as? String ?? ""
        isAvailable = !key.isEmpty && !feed.isEmpty
        super.init()
    }

    /// Starts checking on the schedule. Called once at launch.
    func start() {
        guard isAvailable, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        do {
            try updater.start()
        } catch {
            NSLog("Embark: updater didn't start: \(error.localizedDescription)")
            status = .failed(error.localizedDescription)
            return
        }
        checksAutomatically = updater.automaticallyChecksForUpdates
        installsAutomatically = updater.automaticallyDownloadsUpdates
        lastCheck = updater.lastUpdateCheckDate
        sessionObservation = updater.observe(\.sessionInProgress, options: [.new]) { [weak self] updater, _ in
            // Sparkle changes it on the main thread.
            MainActor.assumeIsolated {
                self?.isChecking = updater.sessionInProgress
                self?.lastCheck = updater.lastUpdateCheckDate
            }
        }
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Embark ▸ Check for Updates…, with Sparkle's window showing the result.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Quits, installs the downloaded update and opens Embark again.
    func installNow() {
        installNowHandler?()
    }
}

extension AppUpdater: @preconcurrency SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .found(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let code = (error as NSError).code
        // No update and a cancelled install also end here, and aren't failures.
        guard code != Int(SUError.noUpdateError.rawValue),
              code != Int(SUError.installationCanceledError.rawValue) else { return }
        status = .failed(error.localizedDescription)
    }

    /// A downloaded update waits for quit. Keeping the handler lets Settings offer to restart now.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        status = .ready(version: item.displayVersionString)
        installNowHandler = immediateInstallHandler
        return true
    }
}

/// Embark ▸ Check for Updates…
struct UpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                .disabled(!AppUpdater.shared.isAvailable)
        }
    }
}
