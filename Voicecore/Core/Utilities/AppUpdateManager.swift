// AppUpdateManager.swift
// Provides App Update Manager for shared utilities.

import Foundation
import Sparkle
import AppKit
import Combine

@MainActor
final class AppUpdateManager: NSObject, ObservableObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    enum CheckSource {
        case automatic
        case manual
    }

    enum UpdateChannel: String {
        case stable
        case beta
    }

    private var updaterControllerStorage: SPUStandardUpdaterController?
    private var updaterController: SPUStandardUpdaterController? {
        if let updaterControllerStorage {
            return updaterControllerStorage
        }
        guard sparkleIsAvailable else { return nil }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        configureUpdaterRequestContext(controller.updater, shouldClearLegacyFeedURL: true)
        updaterControllerStorage = controller
        return controller
    }

    static let stableFeedURLString = "https://voicecore.actnow.dev/updates/stable/appcast.xml"
    static let betaFeedURLString = "https://voicecore.actnow.dev/updates/beta/appcast.xml"
    static let betaFeedEnableEnvKey = "VOICECORE_ENABLE_BETA_UPDATES"
    private let defaults: UserDefaults
    private let interactiveUIPresentationTimeout: Duration = .seconds(4)
    private var lastCheckSource: CheckSource = .automatic
    private var isPresentingUpdateUI = false
    private var interactiveUIPresentationWatchdogTask: Task<Void, Never>?
    @Published private(set) var hasUpdate = false
    @Published private(set) var latestVersion: String?
    @Published private(set) var updateCheckIssueMessage: String?
    @Published private(set) var isPreparingInteractiveUpdateUI = false
    private var latestDownloadedUpdateURL: URL?
    var onUpdatePresentationWillBegin: (() -> Void)?
    var onUpdatePresentationDidEnd: (() -> Void)?
    private lazy var sparkleIsAvailable: Bool = {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier
        guard Self.shouldEnableSparkle(bundleIdentifier: bundleIdentifier) else {
            VoiceCoreLog.update("Sparkle disabled for development or test bundle. bundleID=\(bundleIdentifier ?? "nil")")
            return false
        }
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let buildVersion = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let available = !shortVersion.isEmpty && !buildVersion.isEmpty
        if !available {
            VoiceCoreLog.updateWarning("Sparkle disabled: bundle version metadata is missing. short=\(shortVersion), build=\(buildVersion)")
        }
        return available
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    // Background/dockless apps should opt into Sparkle's gentle reminder support
    // to avoid missing scheduled update alerts.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set {
            guard let updaterController else { return }
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var shouldDisableInteractiveUpdateTrigger: Bool {
        isPreparingInteractiveUpdateUI
    }

    func syncAutomaticallyChecksForUpdates(_ newValue: Bool) {
        guard newValue || sparkleIsAvailable || updaterControllerStorage != nil else { return }
        guard automaticallyChecksForUpdates != newValue else { return }
        automaticallyChecksForUpdates = newValue
    }

    func betaUpdatesPreferenceDidChange() {
        guard hasUpdate || latestVersion != nil || updateCheckIssueMessage != nil || latestDownloadedUpdateURL != nil else {
            return
        }

        setUpdateState(hasUpdate: false, latestVersion: nil, issue: nil, downloadedURL: nil)
        VoiceCoreLog.update("Sparkle update state cleared because update channel preference changed.")
    }

    func shutdownForApplicationTermination() {
        cancelInteractiveUpdatePresentationWatchdog()
        onUpdatePresentationWillBegin = nil
        onUpdatePresentationDidEnd = nil
    }

    #if DEBUG
    func setUpdateStateForTesting(hasUpdate: Bool, latestVersion: String?, issue: String?) {
        setUpdateState(hasUpdate: hasUpdate, latestVersion: latestVersion, issue: issue, downloadedURL: nil)
    }
    #endif

    func checkForUpdatesWithUserInterface() {
        lastCheckSource = .manual
        reportIssue(nil)
        guard sparkleIsAvailable, let updaterController else {
            reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
            return
        }

        if isPreparingInteractiveUpdateUI {
            NSApp.activate(ignoringOtherApps: true)
            VoiceCoreLog.update("Manual update trigger ignored because Sparkle UI is still preparing.")
            return
        }

        if isPresentingUpdateUI {
            focusExistingUpdateUI(using: updaterController.updater, reason: "manual-repeat")
            return
        }

        configureUpdaterRequestContext(updaterController.updater)
        guard isInstallerServiceAvailable() else {
            VoiceCoreLog.updateError("Sparkle installer services unavailable. Unable to present interactive update flow.")
            reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
            return
        }

        logInstallerServiceAvailability()
        setPreparingInteractiveUpdateUI(true)
        startInteractiveUpdatePresentationWatchdog()
        NSApp.activate(ignoringOtherApps: true)
        VoiceCoreLog.update("Manual update check triggered via Sparkle user interface.")
        updaterController.updater.checkForUpdates()
    }

    func checkForUpdates(source: CheckSource) {
        lastCheckSource = source
        reportIssue(nil)
        guard sparkleIsAvailable, let updaterController else {
            reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
            return
        }
        configureUpdaterRequestContext(updaterController.updater)
        if source == .manual {
            if !isInstallerServiceAvailable() {
                VoiceCoreLog.updateError("Sparkle installer services unavailable. Opening manual update page instead of Sparkle installer flow.")
                reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
                return
            }
            logInstallerServiceAvailability()
        }
        switch source {
        case .manual:
            NSApp.activate(ignoringOtherApps: true)
            VoiceCoreLog.update("Manual update check triggered via Sparkle background mode.")
            updaterController.updater.checkForUpdatesInBackground()
        case .automatic:
            if !isInstallerServiceAvailable() {
                VoiceCoreLog.updateWarning("Sparkle installer services unavailable. Skipping background update cycle.")
                reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
                return
            }
            VoiceCoreLog.update("Background update check triggered via Sparkle.")
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        selectedFeedURLString
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        cancelInteractiveUpdatePresentationWatchdog()
        let nsError = error as NSError
        if isNoUpdateFoundError(nsError) {
            setPreparingInteractiveUpdateUI(false)
            setUpdateState(hasUpdate: false, latestVersion: nil, issue: nil, downloadedURL: nil)
            VoiceCoreLog.update(
                """
                Sparkle update abort treated as no-update result. source=\(lastCheckSource.description), \
                domain=\(nsError.domain), code=\(nsError.code), description=\(nsError.localizedDescription)
                """
            )
            return
        }
        let failureReason = nsError.localizedFailureReason ?? "nil"
        let underlyingErrorSummary: String
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            underlyingErrorSummary = "\(underlyingError.domain):\(underlyingError.code):\(underlyingError.localizedDescription)"
        } else {
            underlyingErrorSummary = "nil"
        }
        VoiceCoreLog.updateError(
            """
            Sparkle update aborted. domain=\(nsError.domain), code=\(nsError.code), \
            description=\(nsError.localizedDescription), failureReason=\(failureReason), \
            underlyingError=\(underlyingErrorSummary), updateURL=\(latestDownloadedUpdateURL?.absoluteString ?? "nil"), \
            userInfo=\(nsError.userInfo)
            """
        )
        reportIssue(nsError.localizedDescription)
        finishUpdatePresentationIfNeeded()
        handleInstallerFailureIfNeeded(nsError)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        setUpdateState(
            hasUpdate: true,
            latestVersion: "\(item.displayVersionString) (\(item.versionString))",
            issue: nil,
            downloadedURL: item.fileURL
        )
        VoiceCoreLog.update(
            """
            Sparkle found update. source=\(lastCheckSource.description), \
            version=\(item.displayVersionString), build=\(item.versionString), \
            minSystemVersion=\(item.minimumSystemVersion ?? "nil")
            """
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        cancelInteractiveUpdatePresentationWatchdog()
        setPreparingInteractiveUpdateUI(false)
        setUpdateState(hasUpdate: false, latestVersion: nil, issue: nil, downloadedURL: nil)
        let nsError = error as NSError
        VoiceCoreLog.update(
            """
            Sparkle did not find update. source=\(lastCheckSource.description), \
            domain=\(nsError.domain), code=\(nsError.code), description=\(nsError.localizedDescription)
            """
        )
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        latestDownloadedUpdateURL = item.fileURL
        VoiceCoreLog.update(
            """
            Sparkle finished downloading update. version=\(item.displayVersionString), \
            build=\(item.versionString), fileURL=\(item.fileURL?.absoluteString ?? "nil")
            """
        )
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        let nsError = error as NSError
        VoiceCoreLog.updateError(
            """
            Sparkle failed to download update. version=\(item.displayVersionString), \
            build=\(item.versionString), domain=\(nsError.domain), \
            code=\(nsError.code), description=\(nsError.localizedDescription)
            """
        )
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        cancelInteractiveUpdatePresentationWatchdog()
        if let error {
            let nsError = error as NSError
            if isNoUpdateFoundError(nsError) {
                setUpdateState(hasUpdate: false, latestVersion: nil, issue: nil, downloadedURL: nil)
                VoiceCoreLog.update(
                    """
                    Sparkle finished update cycle with no-update result. source=\(lastCheckSource.description), \
                    check=\(String(describing: updateCheck)), domain=\(nsError.domain), \
                    code=\(nsError.code), description=\(nsError.localizedDescription)
                    """
                )
                return
            }
            reportIssue(nsError.localizedDescription)
            VoiceCoreLog.updateWarning(
                """
                Sparkle finished update cycle with error. source=\(lastCheckSource.description), \
                check=\(String(describing: updateCheck)), domain=\(nsError.domain), \
                code=\(nsError.code), description=\(nsError.localizedDescription)
                """
            )
        } else {
            reportIssue(nil)
            VoiceCoreLog.update(
                "Sparkle finished update cycle successfully. source=\(lastCheckSource.description), check=\(String(describing: updateCheck))"
            )
        }
        finishUpdatePresentationIfNeeded()
    }

    func standardUserDriverWillShowModalAlert() {
        beginUpdatePresentationIfNeeded(reason: "modal alert")
        VoiceCoreLog.update("Sparkle will show modal alert.")
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            beginUpdatePresentationIfNeeded(reason: "will handle showing update")
        } else {
            setPreparingInteractiveUpdateUI(false)
        }
        VoiceCoreLog.update(
            """
            Sparkle will handle showing update. handleShowingUpdate=\(handleShowingUpdate), \
            version=\(update.displayVersionString), build=\(update.versionString)
            """
        )
    }

    func standardUserDriverDidShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
        VoiceCoreLog.update("Sparkle did show modal alert.")
    }

    func standardUserDriverWillFinishUpdateSession() {
        VoiceCoreLog.update("Sparkle will finish update session.")
        finishUpdatePresentationIfNeeded()
    }

    private var selectedFeedURLString: String {
        let betaUpdatesEnabled = defaults.object(forKey: AppPreferenceKey.betaUpdatesEnabled) as? Bool ?? false
        let channel = Self.resolvedUpdateChannel(
            betaUpdatesEnabled: betaUpdatesEnabled,
            environment: ProcessInfo.processInfo.environment
        )
        let baseFeedURLString = Self.feedURLString(for: channel)
        return Self.localizedFeedURLString(
            baseURLString: baseFeedURLString,
            interfaceLanguage: AppLocalization.language
        )
    }

    private func handleInstallerFailureIfNeeded(_ error: NSError) {
        let message = error.localizedDescription.lowercased()
        let indicatesInstallerFailure =
            (error.domain == SUSparkleErrorDomain && [4003, 4005, 4008, 4012].contains(error.code)) ||
            message.contains("authorization") ||
            message.contains("installer") ||
            message.contains("gain authorization required to update target")
        guard indicatesInstallerFailure else { return }

        let fallbackURLString = latestDownloadedUpdateURL?.absoluteString
            ?? selectedFeedURLString.replacingOccurrences(of: "/appcast.xml", with: "/")

        guard let url = URL(string: fallbackURLString) else { return }
        VoiceCoreLog.updateWarning(
            """
            Sparkle installer failed to launch or authorize. \
            Opening fallback update URL: \(fallbackURLString)
            """
        )
        NSWorkspace.shared.open(url)
    }

    private func logInstallerServiceAvailability() {
        guard isInstallerServiceAvailable() else {
            return
        }
        let frameworkXPCServicesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices", isDirectory: true)
        let frameworkEntries = (try? FileManager.default.contentsOfDirectory(atPath: frameworkXPCServicesURL.path)) ?? []
        let installerEntries = frameworkEntries.filter { $0.localizedCaseInsensitiveContains("Installer") }
        VoiceCoreLog.update("Sparkle installer check: found installer services \(installerEntries)")
    }

    private func isInstallerServiceAvailable() -> Bool {
        let appXPCServicesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices", isDirectory: true)
        let frameworkXPCServicesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices", isDirectory: true)
        let fm = FileManager.default
        let appEntries = (try? fm.contentsOfDirectory(atPath: appXPCServicesURL.path)) ?? []
        let frameworkEntries = (try? fm.contentsOfDirectory(atPath: frameworkXPCServicesURL.path)) ?? []

        let combinedEntries = appEntries + frameworkEntries
        let installerEntries = combinedEntries.filter { $0.localizedCaseInsensitiveContains("Installer") }
        guard !installerEntries.isEmpty else {
            VoiceCoreLog.updateError(
                """
                Sparkle installer services not found.
                appXPCServices=\(appXPCServicesURL.path) entries=\(appEntries)
                frameworkXPCServices=\(frameworkXPCServicesURL.path) entries=\(frameworkEntries)
                """
            )
            return false
        }
        return true
    }

    private func reportIssue(_ message: String?) {
        setUpdateState(
            hasUpdate: hasUpdate,
            latestVersion: latestVersion,
            issue: message,
            downloadedURL: latestDownloadedUpdateURL
        )
    }

    private func setUpdateState(
        hasUpdate: Bool,
        latestVersion: String?,
        issue: String?,
        downloadedURL: URL?
    ) {
        self.hasUpdate = hasUpdate
        self.latestVersion = latestVersion
        self.updateCheckIssueMessage = issue
        self.latestDownloadedUpdateURL = downloadedURL
        NotificationCenter.default.post(name: .voicecoreUpdateAvailabilityDidChange, object: nil)
    }

    private func setPreparingInteractiveUpdateUI(_ isPreparing: Bool) {
        guard isPreparingInteractiveUpdateUI != isPreparing else { return }
        isPreparingInteractiveUpdateUI = isPreparing
        NotificationCenter.default.post(name: .voicecoreUpdateAvailabilityDidChange, object: nil)
    }

    private func configureUpdaterRequestContext(_ updater: SPUUpdater, shouldClearLegacyFeedURL: Bool = false) {
        if shouldClearLegacyFeedURL, let legacyFeedURL = updater.clearFeedURLFromUserDefaults() {
            VoiceCoreLog.update("Sparkle cleared legacy persisted feed URL. url=\(legacyFeedURL.absoluteString)")
        }

        let headers = Self.updateRequestHeaders(interfaceLanguage: AppLocalization.language)
        if updater.httpHeaders != headers {
            updater.httpHeaders = headers
        }

        VoiceCoreLog.update(
            """
            Sparkle request context refreshed. feedURL=\(selectedFeedURLString), \
            acceptLanguage=\(headers["Accept-Language"] ?? "nil")
            """
        )
    }

    private func startInteractiveUpdatePresentationWatchdog() {
        cancelInteractiveUpdatePresentationWatchdog()
        interactiveUIPresentationWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.interactiveUIPresentationTimeout ?? .seconds(4))
            } catch {
                return
            }

            guard let self,
                  self.isPreparingInteractiveUpdateUI,
                  !self.isPresentingUpdateUI
            else {
                return
            }

            VoiceCoreLog.updateWarning(
                """
                Sparkle interactive update UI did not become active before timeout. \
                source=\(self.lastCheckSource.description)
                """
            )
            self.setPreparingInteractiveUpdateUI(false)
        }
    }

    private func cancelInteractiveUpdatePresentationWatchdog() {
        interactiveUIPresentationWatchdogTask?.cancel()
        interactiveUIPresentationWatchdogTask = nil
    }

    private func isNoUpdateFoundError(_ error: NSError) -> Bool {
        error.domain == SUSparkleErrorDomain && error.code == 1001
    }

    private func beginUpdatePresentationIfNeeded(reason: String) {
        cancelInteractiveUpdatePresentationWatchdog()
        setPreparingInteractiveUpdateUI(false)
        guard !isPresentingUpdateUI else { return }
        isPresentingUpdateUI = true
        NSApp.activate(ignoringOtherApps: true)
        VoiceCoreLog.update("Sparkle update UI became active. reason=\(reason), source=\(lastCheckSource.description)")
        onUpdatePresentationWillBegin?()
    }

    private func finishUpdatePresentationIfNeeded() {
        cancelInteractiveUpdatePresentationWatchdog()
        setPreparingInteractiveUpdateUI(false)
        guard isPresentingUpdateUI else { return }
        isPresentingUpdateUI = false
        VoiceCoreLog.update("Sparkle update UI finished. source=\(lastCheckSource.description)")
        onUpdatePresentationDidEnd?()
    }

    private func focusExistingUpdateUI(using updater: SPUUpdater, reason: String) {
        NSApp.activate(ignoringOtherApps: true)

        // Sparkle documents that invoking checkForUpdates again while an update or its
        // progress is already shown can bring that existing UI back into frontmost focus.
        guard updater.canCheckForUpdates else {
            VoiceCoreLog.update("Sparkle update UI focus request skipped because updater cannot check right now. reason=\(reason)")
            return
        }

        VoiceCoreLog.update("Sparkle update UI focus requested. reason=\(reason)")
        updater.checkForUpdates()
    }

    static func localizedFeedURLString(baseURLString: String, interfaceLanguage: AppInterfaceLanguage) -> String {
        guard var components = URLComponents(string: baseURLString) else {
            return baseURLString
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "lang" }
        queryItems.append(
            URLQueryItem(name: "lang", value: interfaceLanguage.localeIdentifier)
        )
        components.queryItems = queryItems
        return components.url?.absoluteString ?? baseURLString
    }

    static func feedURLString(for channel: UpdateChannel) -> String {
        switch channel {
        case .stable:
            return stableFeedURLString
        case .beta:
            return betaFeedURLString
        }
    }

    static func resolvedUpdateChannel(
        betaUpdatesEnabled: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UpdateChannel {
        if let channel = environment["VOICECORE_UPDATE_CHANNEL"]?.lowercased() {
            switch channel {
            case "beta":
                if canUseBetaFeed(environment: environment) {
                    return .beta
                }
                return betaUpdatesEnabled ? .beta : .stable
            case "stable":
                return .stable
            default:
                break
            }
        }

        return betaUpdatesEnabled ? .beta : .stable
    }

    static func selectedFeedURLString(
        betaUpdatesEnabled: Bool,
        interfaceLanguage: AppInterfaceLanguage,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        localizedFeedURLString(
            baseURLString: feedURLString(
                for: resolvedUpdateChannel(
                    betaUpdatesEnabled: betaUpdatesEnabled,
                    environment: environment
                )
            ),
            interfaceLanguage: interfaceLanguage
        )
    }

    static func shouldEnableSparkle(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty
        else {
            return true
        }

        return bundleIdentifier == "com.kivi.voicecore.VoiceCore" &&
            !bundleIdentifier.hasSuffix(".dev") &&
            !bundleIdentifier.hasSuffix(".testhost") &&
            !bundleIdentifier.hasSuffix(".local")
    }

    private static func canUseBetaFeed(environment: [String: String]) -> Bool {
        let explicitEnable = environment[betaFeedEnableEnvKey]?.lowercased() ?? ""
        return ["1", "true", "yes", "on"].contains(explicitEnable)
    }

    static func updateRequestHeaders(interfaceLanguage: AppInterfaceLanguage) -> [String: String] {
        let localeIdentifier = interfaceLanguage.localeIdentifier
        let baseLanguage = localeIdentifier.split(separator: "-").first.map(String.init) ?? localeIdentifier

        var languagePreferences: [String] = [localeIdentifier]
        if baseLanguage != localeIdentifier {
            languagePreferences.append("\(baseLanguage);q=0.9")
        }
        if baseLanguage != "en" {
            languagePreferences.append("en;q=0.8")
        }

        return [
            "Accept-Language": languagePreferences.joined(separator: ", ")
        ]
    }
}

private extension AppUpdateManager.CheckSource {
    var description: String {
        switch self {
        case .automatic:
            return "automatic"
        case .manual:
            return "manual"
        }
    }
}

extension Notification.Name {
    static let voicecoreUpdateAvailabilityDidChange = Notification.Name("voicecore.update.availability.didChange")
}
