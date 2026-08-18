// VoiceCoreNetworkSession.swift
// Provides VoiceCore Network Session for core app behavior.

import Foundation
import CFNetwork
import Network
import Darwin

enum VoiceCoreNetworkSession {
    struct RequestTiming: Sendable {
        let stage: String
        let totalMilliseconds: Int
        let dnsMilliseconds: Int?
        let connectMilliseconds: Int?
        let tlsMilliseconds: Int?
        let uploadMilliseconds: Int?
        let serverWaitMilliseconds: Int?
        let downloadMilliseconds: Int?
        let reusedConnection: Bool
        let negotiatedProtocol: String?

        var logSummary: String {
            func value(_ milliseconds: Int?) -> String {
                milliseconds.map(String.init) ?? "n/a"
            }
            return "stage=\(stage), totalMs=\(totalMilliseconds), dnsMs=\(value(dnsMilliseconds)), connectMs=\(value(connectMilliseconds)), tlsMs=\(value(tlsMilliseconds)), uploadMs=\(value(uploadMilliseconds)), serverWaitMs=\(value(serverWaitMilliseconds)), downloadMs=\(value(downloadMilliseconds)), reused=\(reusedConnection), protocol=\(negotiatedProtocol ?? "unknown")"
        }
    }

    @TaskLocal static var requestTimingObserver: (@Sendable (RequestTiming) -> Void)?

    private final class RequestMetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var metrics: URLSessionTaskMetrics?

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            lock.lock()
            self.metrics = metrics
            lock.unlock()
        }

        func timing(stage: String, fallbackTotalMilliseconds: Int) -> RequestTiming {
            lock.lock()
            let captured = metrics
            lock.unlock()
            guard let transaction = captured?.transactionMetrics.last else {
                return RequestTiming(
                    stage: stage,
                    totalMilliseconds: fallbackTotalMilliseconds,
                    dnsMilliseconds: nil,
                    connectMilliseconds: nil,
                    tlsMilliseconds: nil,
                    uploadMilliseconds: nil,
                    serverWaitMilliseconds: nil,
                    downloadMilliseconds: nil,
                    reusedConnection: false,
                    negotiatedProtocol: nil
                )
            }
            return RequestTiming(
                stage: stage,
                totalMilliseconds: Self.milliseconds(from: captured?.taskInterval.duration)
                    ?? fallbackTotalMilliseconds,
                dnsMilliseconds: Self.interval(
                    start: transaction.domainLookupStartDate,
                    end: transaction.domainLookupEndDate
                ),
                connectMilliseconds: Self.interval(
                    start: transaction.connectStartDate,
                    end: transaction.connectEndDate
                ),
                tlsMilliseconds: Self.interval(
                    start: transaction.secureConnectionStartDate,
                    end: transaction.secureConnectionEndDate
                ),
                uploadMilliseconds: Self.interval(
                    start: transaction.requestStartDate,
                    end: transaction.requestEndDate
                ),
                serverWaitMilliseconds: Self.interval(
                    start: transaction.requestEndDate,
                    end: transaction.responseStartDate
                ),
                downloadMilliseconds: Self.interval(
                    start: transaction.responseStartDate,
                    end: transaction.responseEndDate
                ),
                reusedConnection: transaction.isReusedConnection,
                negotiatedProtocol: transaction.networkProtocolName
            )
        }

        private static func interval(start: Date?, end: Date?) -> Int? {
            guard let start, let end else { return nil }
            return milliseconds(from: end.timeIntervalSince(start))
        }

        private static func milliseconds(from seconds: TimeInterval?) -> Int? {
            guard let seconds else { return nil }
            return max(0, Int((seconds * 1_000).rounded()))
        }
    }

    private actor TransportPrewarmer {
        private var lastWarmAtByOrigin: [String: Date] = [:]
        private let cooldown: TimeInterval = 60

        func warm(endpoint: String) async {
            guard let originURL = Self.originURL(from: endpoint) else { return }
            let key = originURL.absoluteString
            if let lastWarmAt = lastWarmAtByOrigin[key], Date().timeIntervalSince(lastWarmAt) < cooldown {
                return
            }
            lastWarmAtByOrigin[key] = Date()

            var request = URLRequest(url: originURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                _ = try await VoiceCoreNetworkSession.data(for: request, stage: "transport-prewarm")
            } catch {
                // A transport-only warm-up is successful for our purpose once DNS/TCP/TLS
                // has been attempted. Authentication and endpoint HTTP errors are irrelevant.
                VoiceCoreLog.network("Transport prewarm finished with HTTP/connection result. origin=\(key), detail=\(error.localizedDescription)")
            }
        }

        private static func originURL(from endpoint: String) -> URL? {
            guard var components = URLComponents(string: endpoint),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" || scheme == "ws" || scheme == "wss",
                  components.host != nil
            else { return nil }
            components.scheme = scheme == "ws" ? "http" : (scheme == "wss" ? "https" : scheme)
            components.path = "/"
            components.query = nil
            components.fragment = nil
            return components.url
        }
    }

    private static let transportPrewarmer = TransportPrewarmer()
    private static let customSessionCacheLock = NSLock()
    private static var customSessionCache: [String: URLSession] = [:]
    private enum SecureField: String {
        case customProxyUsername
        case customProxyPassword
    }

    final class ManagedWebSocketTask {
        let session: URLSession
        let task: URLSessionWebSocketTask

        init(session: URLSession, task: URLSessionWebSocketTask) {
            self.session = session
            self.task = task
        }
    }

    enum ProxyMode: String, CaseIterable, Identifiable {
        case system
        case disabled
        case custom

        var id: String { rawValue }
    }

    enum ProxyScheme: String, CaseIterable, Identifiable {
        case http
        case https
        case socks5

        var id: String { rawValue }
    }

    private static let processProxyEnvironmentKeys = [
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "no_proxy",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY"
    ]

    struct ProxySettings {
        let mode: ProxyMode
        let scheme: ProxyScheme
        let host: String
        let port: Int?
        let username: String
        let password: String

        nonisolated var hasValidCustomEndpoint: Bool {
            !host.isEmpty && port != nil
        }

        var hasCredentials: Bool {
            !username.isEmpty && !password.isEmpty
        }
    }

    struct SystemProxyStatus {
        let httpHost: String
        let httpPort: Int?
        let httpsHost: String
        let httpsPort: Int?
        let socksHost: String
        let socksPort: Int?

        var hasEnabledProxy: Bool {
            !httpHost.isEmpty || !httpsHost.isEmpty || !socksHost.isEmpty
        }

        var preferredSummary: String? {
            if let value = endpointSummary(host: socksHost, port: socksPort, scheme: "SOCKS") {
                return value
            }
            if let value = endpointSummary(host: httpsHost, port: httpsPort, scheme: "HTTPS") {
                return value
            }
            if let value = endpointSummary(host: httpHost, port: httpPort, scheme: "HTTP") {
                return value
            }
            return nil
        }

        private func endpointSummary(host: String, port: Int?, scheme: String) -> String? {
            guard !host.isEmpty else { return nil }
            if let port {
                return "\(scheme) \(host):\(port)"
            }
            return "\(scheme) \(host)"
        }
    }

    private final class ProxyAuthenticationDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
        private let settings: ProxySettings

        init(settings: ProxySettings) {
            self.settings = settings
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            handle(challenge: challenge, completionHandler: completionHandler)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            handle(challenge: challenge, completionHandler: completionHandler)
        }

        private func handle(
            challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard settings.hasCredentials, isProxyAuthenticationChallenge(challenge.protectionSpace) else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            let credential = URLCredential(
                user: settings.username,
                password: settings.password,
                persistence: .forSession
            )
            completionHandler(.useCredential, credential)
        }

        private func isProxyAuthenticationChallenge(_ protectionSpace: URLProtectionSpace) -> Bool {
            protectionSpace.proxyType != nil
        }
    }

    // Force direct outbound network requests and bypass system HTTP/HTTPS/SOCKS proxies.
    static let direct: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        applyDirectProxyBypass(to: configuration)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static let system: URLSession = {
        URLSession(configuration: .default)
    }()

    static func clearProcessProxyEnvironmentOverridesIfNeeded(log: Bool = false) {
        var clearedKeys: [String] = []
        for key in processProxyEnvironmentKeys {
            guard getenv(key) != nil else { continue }
            unsetenv(key)
            clearedKeys.append(key)
        }
        if log, !clearedKeys.isEmpty {
            VoiceCoreLog.info("Cleared process proxy environment overrides. keys=\(clearedKeys.joined(separator: ","))")
        }
    }

    static var currentSystemProxyStatus: SystemProxyStatus {
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
        return SystemProxyStatus(
            httpHost: proxyHost(settings, enabledKey: kCFNetworkProxiesHTTPEnable, hostKey: kCFNetworkProxiesHTTPProxy),
            httpPort: proxyPort(settings, enabledKey: kCFNetworkProxiesHTTPEnable, portKey: kCFNetworkProxiesHTTPPort),
            httpsHost: proxyHost(settings, enabledKey: kCFNetworkProxiesHTTPSEnable, hostKey: kCFNetworkProxiesHTTPSProxy),
            httpsPort: proxyPort(settings, enabledKey: kCFNetworkProxiesHTTPSEnable, portKey: kCFNetworkProxiesHTTPSPort),
            socksHost: proxyHost(settings, enabledKey: kCFNetworkProxiesSOCKSEnable, hostKey: kCFNetworkProxiesSOCKSProxy),
            socksPort: proxyPort(settings, enabledKey: kCFNetworkProxiesSOCKSEnable, portKey: kCFNetworkProxiesSOCKSPort)
        )
    }

    static func directModeConflictMessage(for error: Error) -> String? {
        guard currentProxySettings.mode == .disabled else { return nil }
        let status = currentSystemProxyStatus
        guard status.hasEnabledProxy, let proxySummary = status.preferredSummary else { return nil }

        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()
        let socketNotConnected = description.contains("socket is not connected")
            || description.contains("socket未连接")
        let likelyProxyConflict =
            socketNotConnected
            || nsError.code == NSURLErrorCannotConnectToHost
            || nsError.code == NSURLErrorNetworkConnectionLost
            || nsError.code == NSURLErrorCannotFindHost

        guard likelyProxyConflict else { return nil }
        return AppLocalization.format(
            "VoiceCore is set to direct connection, but macOS system proxy is still enabled (%@). This WebSocket request was still routed to that proxy. Disable the system proxy or TUN mode in Clash/your proxy app, or switch VoiceCore to System Proxy mode.",
            proxySummary
        )
    }

    static func activeProxyUnavailableMessage(for error: Error) -> String? {
        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()
        let socketNotConnected = description.contains("socket is not connected")
            || description.contains("socket未连接")
        let likelyProxyFailure =
            socketNotConnected
            || nsError.code == NSURLErrorCannotConnectToHost
            || nsError.code == NSURLErrorNetworkConnectionLost
            || nsError.code == NSURLErrorCannotFindHost

        guard likelyProxyFailure else { return nil }

        let settings = currentProxySettings
        switch settings.mode {
        case .system:
            let status = currentSystemProxyStatus
            guard status.hasEnabledProxy, let proxySummary = status.preferredSummary else { return nil }
            return AppLocalization.format(
                "VoiceCore is using the macOS system proxy (%@), but that proxy is unreachable. Make sure Clash/your proxy app is running, or switch VoiceCore to Direct Connection if you don't need a proxy.",
                proxySummary
            )
        case .custom:
            guard settings.hasValidCustomEndpoint, let port = settings.port else { return nil }
            return AppLocalization.format(
                "VoiceCore is using the custom proxy (%@://%@:%d), but that proxy is unreachable. Check the proxy address, port, and whether the proxy app is running.",
                settings.scheme.rawValue.uppercased(),
                settings.host,
                port
            )
        case .disabled:
            return nil
        }
    }

    static var currentProxySettings: ProxySettings {
        let credentials = currentProxyCredentials()
        let defaults = UserDefaults.standard
        let mode = ProxyMode(rawValue: defaults.string(forKey: AppPreferenceKey.networkProxyMode) ?? "") ?? .system
        let scheme = ProxyScheme(rawValue: defaults.string(forKey: AppPreferenceKey.customProxyScheme) ?? "") ?? .http
        let host = (defaults.string(forKey: AppPreferenceKey.customProxyHost) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = (defaults.string(forKey: AppPreferenceKey.customProxyPort) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ProxySettings(
            mode: mode,
            scheme: scheme,
            host: host,
            port: Int(portText),
            username: credentials.username,
            password: credentials.password
        )
    }

    static func currentProxyCredentials() -> (username: String, password: String) {
        proxyCredentials(defaults: .standard)
    }

    static func proxyCredentials(defaults: UserDefaults) -> (username: String, password: String) {
        (
            secureValue(
                for: .customProxyUsername,
                fallbackDefaultsKey: AppPreferenceKey.customProxyUsername,
                defaults: defaults
            ),
            secureValue(
                for: .customProxyPassword,
                fallbackDefaultsKey: AppPreferenceKey.customProxyPassword,
                defaults: defaults
            )
        )
    }

    static func setCustomProxyCredentials(
        username: String,
        password: String,
        defaults: UserDefaults = .standard
    ) {
        if VoiceCoreSecureStorage.set(username, for: secureAccount(for: .customProxyUsername)) {
            defaults.removeObject(forKey: AppPreferenceKey.customProxyUsername)
        }
        if VoiceCoreSecureStorage.set(password, for: secureAccount(for: .customProxyPassword)) {
            defaults.removeObject(forKey: AppPreferenceKey.customProxyPassword)
        }
    }

    static func migrateLegacyProxyCredentials(defaults: UserDefaults = .standard) {
        migrateLegacyValue(for: .customProxyUsername, defaultsKey: AppPreferenceKey.customProxyUsername, defaults: defaults)
        migrateLegacyValue(for: .customProxyPassword, defaultsKey: AppPreferenceKey.customProxyPassword, defaults: defaults)
    }

    static var isUsingSystemProxy: Bool {
        currentProxySettings.mode == .system
    }

    static var modeDescription: String {
        let settings = currentProxySettings
        switch settings.mode {
        case .system:
            return "system"
        case .disabled:
            return "direct"
        case .custom:
            guard settings.hasValidCustomEndpoint, let port = settings.port else {
                return "custom(incomplete)"
            }
            return "custom(\(settings.scheme.rawValue)://\(settings.host):\(port))"
        }
    }

    static var active: URLSession {
        clearProcessProxyEnvironmentOverridesIfNeeded()
        let settings = currentProxySettings
        switch settings.mode {
        case .system:
            return system
        case .disabled:
            return direct
        case .custom:
            guard settings.hasValidCustomEndpoint else {
                return direct
            }
            return customSession(settings: settings)
        }
    }

    static func data(
        for request: URLRequest,
        stage: String
    ) async throws -> (Data, URLResponse) {
        let metricsDelegate = RequestMetricsDelegate()
        let startedAt = Date()
        do {
            let result = try await active.data(for: request, delegate: metricsDelegate)
            reportTiming(
                metricsDelegate.timing(
                    stage: stage,
                    fallbackTotalMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
                )
            )
            return result
        } catch {
            reportTiming(
                metricsDelegate.timing(
                    stage: stage,
                    fallbackTotalMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
                )
            )
            throw error
        }
    }

    static func upload(
        for request: URLRequest,
        fromFile fileURL: URL,
        stage: String
    ) async throws -> (Data, URLResponse) {
        let metricsDelegate = RequestMetricsDelegate()
        let startedAt = Date()
        do {
            let result = try await active.upload(for: request, fromFile: fileURL, delegate: metricsDelegate)
            reportTiming(
                metricsDelegate.timing(
                    stage: stage,
                    fallbackTotalMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
                )
            )
            return result
        } catch {
            reportTiming(
                metricsDelegate.timing(
                    stage: stage,
                    fallbackTotalMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
                )
            )
            throw error
        }
    }

    static func prewarmTransport(endpoint: String) async {
        await transportPrewarmer.warm(endpoint: endpoint)
    }

    private static func reportTiming(_ timing: RequestTiming) {
        VoiceCoreLog.network("HTTP timing. \(timing.logSummary)")
        requestTimingObserver?(timing)
    }

    static func makeWebSocketTask(with request: URLRequest) -> ManagedWebSocketTask {
        clearProcessProxyEnvironmentOverridesIfNeeded()
        let settings = currentProxySettings
        let session = makeSession(for: settings)
        let task = session.webSocketTask(with: request)
        return ManagedWebSocketTask(session: session, task: task)
    }

    private static func customSession(settings: ProxySettings) -> URLSession {
        let cacheKey = [
            settings.scheme.rawValue,
            settings.host,
            settings.port.map(String.init) ?? "",
            settings.username,
            String(settings.password.hashValue)
        ].joined(separator: "|")
        customSessionCacheLock.lock()
        if let cached = customSessionCache[cacheKey] {
            customSessionCacheLock.unlock()
            return cached
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = customProxyDictionary(settings: settings)
        configuration.proxyConfigurations = customProxyConfigurations(settings: settings)
        let delegate = settings.hasCredentials ? ProxyAuthenticationDelegate(settings: settings) : nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        customSessionCache[cacheKey] = session
        customSessionCacheLock.unlock()
        return session
    }

    private static func makeSession(for settings: ProxySettings) -> URLSession {
        switch settings.mode {
        case .system:
            return URLSession(configuration: .default)
        case .disabled:
            let configuration = URLSessionConfiguration.ephemeral
            applyDirectProxyBypass(to: configuration)
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: configuration)
        case .custom:
            guard settings.hasValidCustomEndpoint else {
                let configuration = URLSessionConfiguration.ephemeral
                applyDirectProxyBypass(to: configuration)
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                return URLSession(configuration: configuration)
            }
            return customSession(settings: settings)
        }
    }

    private static func applyDirectProxyBypass(to configuration: URLSessionConfiguration) {
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
            kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false,
            kCFNetworkProxiesHTTPProxy as String: "",
            kCFNetworkProxiesHTTPPort as String: 0,
            kCFNetworkProxiesHTTPSProxy as String: "",
            kCFNetworkProxiesHTTPSPort as String: 0,
            kCFNetworkProxiesSOCKSProxy as String: "",
            kCFNetworkProxiesSOCKSPort as String: 0,
            kCFNetworkProxiesProxyAutoConfigURLString as String: "",
            kCFNetworkProxiesExceptionsList as String: [],
            kCFNetworkProxiesExcludeSimpleHostnames as String: false
        ]
        configuration.proxyConfigurations = []
    }

    private static func proxyEnabled(_ settings: [String: Any], key: CFString) -> Bool {
        if let value = settings[key as String] as? NSNumber {
            return value.boolValue
        }
        if let value = settings[key as String] as? Bool {
            return value
        }
        return false
    }

    private static func proxyHost(
        _ settings: [String: Any],
        enabledKey: CFString,
        hostKey: CFString
    ) -> String {
        guard proxyEnabled(settings, key: enabledKey) else { return "" }
        return (settings[hostKey as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func proxyPort(
        _ settings: [String: Any],
        enabledKey: CFString,
        portKey: CFString
    ) -> Int? {
        guard proxyEnabled(settings, key: enabledKey) else { return nil }
        if let value = settings[portKey as String] as? NSNumber {
            return value.intValue
        }
        if let value = settings[portKey as String] as? Int {
            return value
        }
        return nil
    }

    private static func secureValue(
        for field: SecureField,
        fallbackDefaultsKey: String,
        defaults: UserDefaults
    ) -> String {
        if let stored = VoiceCoreSecureStorage.string(for: secureAccount(for: field)) {
            return stored
        }

        let legacyValue = defaults.string(forKey: fallbackDefaultsKey) ?? ""
        if !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if VoiceCoreSecureStorage.set(legacyValue, for: secureAccount(for: field)) {
                defaults.removeObject(forKey: fallbackDefaultsKey)
            }
        }
        return legacyValue
    }

    private static func migrateLegacyValue(for field: SecureField, defaultsKey: String, defaults: UserDefaults) {
        let legacyValue = defaults.string(forKey: defaultsKey) ?? ""
        if !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard VoiceCoreSecureStorage.set(legacyValue, for: secureAccount(for: field)) else {
                return
            }
        }
        defaults.removeObject(forKey: defaultsKey)
    }

    private static func secureAccount(for field: SecureField) -> String {
        "network-proxy.\(field.rawValue)"
    }

    private static func customProxyDictionary(settings: ProxySettings) -> [AnyHashable: Any] {
        guard let port = settings.port else {
            return [:]
        }

        var dictionary: [AnyHashable: Any] = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
            kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false
        ]

        switch settings.scheme {
        case .http, .https:
            dictionary[kCFNetworkProxiesHTTPEnable as String] = true
            dictionary[kCFNetworkProxiesHTTPProxy as String] = settings.host
            dictionary[kCFNetworkProxiesHTTPPort as String] = port
            dictionary[kCFNetworkProxiesHTTPSEnable as String] = true
            dictionary[kCFNetworkProxiesHTTPSProxy as String] = settings.host
            dictionary[kCFNetworkProxiesHTTPSPort as String] = port
        case .socks5:
            dictionary[kCFNetworkProxiesSOCKSEnable as String] = true
            dictionary[kCFNetworkProxiesSOCKSProxy as String] = settings.host
            dictionary[kCFNetworkProxiesSOCKSPort as String] = port
        }

        return dictionary
    }

    private static func customProxyConfigurations(settings: ProxySettings) -> [ProxyConfiguration] {
        guard
            let portValue = settings.port,
            let port = NWEndpoint.Port(rawValue: UInt16(portValue))
        else {
            return []
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(settings.host), port: port)
        var configuration: ProxyConfiguration
        switch settings.scheme {
        case .http, .https:
            configuration = ProxyConfiguration(httpCONNECTProxy: endpoint)
        case .socks5:
            configuration = ProxyConfiguration(socksv5Proxy: endpoint)
        }
        configuration.allowFailover = false
        if settings.hasCredentials {
            configuration.applyCredential(username: settings.username, password: settings.password)
        }
        return [configuration]
    }

    /// Errors that are almost always caused by a flaky local network hop
    /// (a proxy dropping a connection mid-handshake, a transient DNS blip)
    /// rather than the remote server or the request itself being broken —
    /// safe to retry without changing the request.
    private static let transientErrorCodes: Set<Int> = [
        NSURLErrorSecureConnectionFailed,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorTimedOut,
        NSURLErrorCannotConnectToHost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorNotConnectedToInternet
    ]

    nonisolated static func isTransientNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && transientErrorCodes.contains(nsError.code)
    }

    /// Retries `operation` up to `attempts` times when it throws a transient
    /// network error (see `isTransientNetworkError`). Non-transient errors
    /// (HTTP 4xx/5xx surfaced as regular return values, decoding failures,
    /// etc.) are not retried and propagate immediately.
    static func withTransientRetry<T>(
        attempts: Int = 3,
        delaySeconds: Double = 1.0,
        stage: String,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...max(1, attempts) {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < attempts, isTransientNetworkError(error) else {
                    throw error
                }
                VoiceCoreLog.asrWarning(
                    "Transient network error on \(stage), retrying (attempt \(attempt)/\(attempts)). error=\(error.localizedDescription)"
                )
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
        throw lastError ?? NSError(domain: "VoiceCore.Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Retry failed with no error captured."])
    }
}
