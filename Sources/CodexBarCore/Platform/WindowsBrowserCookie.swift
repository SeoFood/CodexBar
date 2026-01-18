import Foundation

#if os(Windows)
import WinSDK

/// Browser types supported for cookie extraction on Windows.
/// Subset of macOS browsers that use Chromium and work with DPAPI.
public enum WindowsBrowser: String, Sendable, Hashable, CaseIterable {
    case chrome
    case chromeBeta
    case chromeCanary
    case edge
    case edgeBeta
    case edgeCanary
    case brave
    case braveBeta
    case braveNightly
    case vivaldi
    case chromium

    /// Display name for UI or logs.
    public var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .chromeBeta: return "Chrome Beta"
        case .chromeCanary: return "Chrome Canary"
        case .edge: return "Microsoft Edge"
        case .edgeBeta: return "Microsoft Edge Beta"
        case .edgeCanary: return "Microsoft Edge Canary"
        case .brave: return "Brave"
        case .braveBeta: return "Brave Beta"
        case .braveNightly: return "Brave Nightly"
        case .vivaldi: return "Vivaldi"
        case .chromium: return "Chromium"
        }
    }

    /// Preferred order to search for cookies.
    public static let defaultImportOrder: [WindowsBrowser] = [
        .edge,      // Edge is most likely to work (Microsoft's implementation)
        .chrome,
        .brave,
        .vivaldi,
        .chromium,
        .chromeBeta,
        .chromeCanary,
        .edgeBeta,
        .edgeCanary,
        .braveBeta,
        .braveNightly,
    ]

    /// User data directory path relative to %LOCALAPPDATA%.
    var localAppDataPath: String {
        switch self {
        case .chrome:
            return "Google\\Chrome\\User Data"
        case .chromeBeta:
            return "Google\\Chrome Beta\\User Data"
        case .chromeCanary:
            return "Google\\Chrome SxS\\User Data"
        case .edge:
            return "Microsoft\\Edge\\User Data"
        case .edgeBeta:
            return "Microsoft\\Edge Beta\\User Data"
        case .edgeCanary:
            return "Microsoft\\Edge SxS\\User Data"
        case .brave:
            return "BraveSoftware\\Brave-Browser\\User Data"
        case .braveBeta:
            return "BraveSoftware\\Brave-Browser-Beta\\User Data"
        case .braveNightly:
            return "BraveSoftware\\Brave-Browser-Nightly\\User Data"
        case .vivaldi:
            return "Vivaldi\\User Data"
        case .chromium:
            return "Chromium\\User Data"
        }
    }
}

/// A cookie record from a Windows browser.
public struct WindowsCookieRecord: Sendable {
    public let domain: String
    public let name: String
    public let path: String
    public let value: String
    public let expires: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool

    public init(
        domain: String,
        name: String,
        path: String,
        value: String,
        expires: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool
    ) {
        self.domain = domain
        self.name = name
        self.path = path
        self.value = value
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }
}

/// Cookie extraction result from a browser profile.
public struct WindowsCookieStoreRecords: Sendable {
    public let browser: WindowsBrowser
    public let profileName: String
    public let label: String
    public let records: [WindowsCookieRecord]

    public init(browser: WindowsBrowser, profileName: String, label: String, records: [WindowsCookieRecord]) {
        self.browser = browser
        self.profileName = profileName
        self.label = label
        self.records = records
    }
}

/// Errors from Windows cookie extraction.
public enum WindowsCookieError: Swift.Error, LocalizedError {
    case browserNotInstalled(WindowsBrowser)
    case localStateNotFound(String)
    case encryptedKeyNotFound
    case keyDecryptionFailed(Error)
    case cookieDatabaseNotFound(String)
    case databaseReadFailed(Error)
    case cookieDecryptionFailed(Error)
    case appBoundEncryption(String)
    case unsupportedEncryptionVersion(String)

    public var errorDescription: String? {
        switch self {
        case let .browserNotInstalled(browser):
            return "\(browser.displayName) is not installed"
        case let .localStateNotFound(path):
            return "Local State file not found at: \(path)"
        case .encryptedKeyNotFound:
            return "Encrypted key not found in Local State"
        case let .keyDecryptionFailed(error):
            return "Failed to decrypt master key: \(error.localizedDescription)"
        case let .cookieDatabaseNotFound(path):
            return "Cookie database not found at: \(path)"
        case let .databaseReadFailed(error):
            return "Failed to read cookie database: \(error.localizedDescription)"
        case let .cookieDecryptionFailed(error):
            return "Failed to decrypt cookie: \(error.localizedDescription)"
        case let .appBoundEncryption(details):
            return "App-Bound Encryption detected (Chrome 127+): \(details)"
        case let .unsupportedEncryptionVersion(version):
            return "Unsupported cookie encryption version: \(version)"
        }
    }
}

/// Client for extracting cookies from Chromium-based browsers on Windows.
public final class WindowsBrowserCookieClient: Sendable {
    private let localAppData: String
    private let fileManager: FileManager

    /// Creates a new Windows browser cookie client.
    /// - Parameter localAppData: Override for %LOCALAPPDATA% path (for testing)
    public init(localAppData: String? = nil) {
        self.localAppData = localAppData ?? Self.getLocalAppData()
        self.fileManager = FileManager.default
    }

    /// Gets the %LOCALAPPDATA% path.
    private static func getLocalAppData() -> String {
        if let path = ProcessInfo.processInfo.environment["LOCALAPPDATA"] {
            return path
        }
        // Fallback: construct from USERPROFILE
        if let userProfile = ProcessInfo.processInfo.environment["USERPROFILE"] {
            return "\(userProfile)\\AppData\\Local"
        }
        return "C:\\Users\\Default\\AppData\\Local"
    }

    /// Checks if a browser is installed.
    public func isInstalled(_ browser: WindowsBrowser) -> Bool {
        let userDataPath = "\(localAppData)\\\(browser.localAppDataPath)"
        return fileManager.fileExists(atPath: userDataPath)
    }

    /// Lists installed browsers in order of preference.
    public func installedBrowsers(order: [WindowsBrowser] = WindowsBrowser.defaultImportOrder) -> [WindowsBrowser] {
        order.filter { isInstalled($0) }
    }

    /// Extracts cookies matching the given domains from a browser.
    /// - Parameters:
    ///   - browser: The browser to extract cookies from
    ///   - domains: Domain patterns to match (e.g., "claude.ai")
    ///   - logger: Optional logging callback
    /// - Returns: Cookie store records for all matching profiles
    public func extractCookies(
        from browser: WindowsBrowser,
        domains: [String],
        logger: ((String) -> Void)? = nil
    ) throws -> [WindowsCookieStoreRecords] {
        let log: (String) -> Void = { msg in logger?(msg) }

        let userDataPath = "\(localAppData)\\\(browser.localAppDataPath)"
        guard fileManager.fileExists(atPath: userDataPath) else {
            throw WindowsCookieError.browserNotInstalled(browser)
        }

        log("Reading cookies from \(browser.displayName) at \(userDataPath)")

        // Read and decrypt the master key
        let masterKey = try readMasterKey(from: userDataPath, logger: log)
        log("Successfully decrypted master key")

        // Find all profile directories
        let profiles = findProfiles(in: userDataPath)
        log("Found \(profiles.count) profile(s)")

        var results: [WindowsCookieStoreRecords] = []

        for (profileName, profilePath) in profiles {
            do {
                let cookies = try extractCookiesFromProfile(
                    profilePath: profilePath,
                    masterKey: masterKey,
                    domains: domains,
                    logger: log
                )
                if !cookies.isEmpty {
                    let label = "\(browser.displayName) (\(profileName))"
                    results.append(WindowsCookieStoreRecords(
                        browser: browser,
                        profileName: profileName,
                        label: label,
                        records: cookies
                    ))
                    log("Found \(cookies.count) matching cookie(s) in \(profileName)")
                }
            } catch {
                log("Failed to read cookies from \(profileName): \(error.localizedDescription)")
            }
        }

        return results
    }

    /// Reads and decrypts the master encryption key from Local State.
    private func readMasterKey(from userDataPath: String, logger: ((String) -> Void)?) throws -> Data {
        let localStatePath = "\(userDataPath)\\Local State"

        guard fileManager.fileExists(atPath: localStatePath) else {
            throw WindowsCookieError.localStateNotFound(localStatePath)
        }

        let localStateData = try Data(contentsOf: URL(fileURLWithPath: localStatePath))
        guard let json = try JSONSerialization.jsonObject(with: localStateData) as? [String: Any],
              let osCrypt = json["os_crypt"] as? [String: Any],
              let encryptedKeyBase64 = osCrypt["encrypted_key"] as? String
        else {
            throw WindowsCookieError.encryptedKeyNotFound
        }

        // Check for app_bound_encrypted_key (Chrome 127+)
        if osCrypt["app_bound_encrypted_key"] != nil {
            logger?("Warning: App-Bound Encryption detected. Some cookies may not be decryptable.")
        }

        guard let encryptedKeyData = Data(base64Encoded: encryptedKeyBase64) else {
            throw WindowsCookieError.encryptedKeyNotFound
        }

        // The encrypted key has a "DPAPI" prefix (5 bytes) that we need to strip
        guard encryptedKeyData.count > 5 else {
            throw WindowsCookieError.encryptedKeyNotFound
        }

        let prefix = String(data: encryptedKeyData.prefix(5), encoding: .utf8)
        guard prefix == "DPAPI" else {
            throw WindowsCookieError.unsupportedEncryptionVersion(prefix ?? "unknown")
        }

        let dpapiEncryptedKey = encryptedKeyData.dropFirst(5)

        do {
            return try WindowsDPAPI.decrypt(Data(dpapiEncryptedKey))
        } catch {
            throw WindowsCookieError.keyDecryptionFailed(error)
        }
    }

    /// Finds all profile directories in the user data folder.
    private func findProfiles(in userDataPath: String) -> [(name: String, path: String)] {
        var profiles: [(String, String)] = []

        // Check for Default profile
        let defaultPath = "\(userDataPath)\\Default"
        if fileManager.fileExists(atPath: defaultPath) {
            profiles.append(("Default", defaultPath))
        }

        // Check for numbered profiles (Profile 1, Profile 2, etc.)
        guard let contents = try? fileManager.contentsOfDirectory(atPath: userDataPath) else {
            return profiles
        }

        for item in contents where item.hasPrefix("Profile ") {
            let profilePath = "\(userDataPath)\\\(item)"
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: profilePath, isDirectory: &isDirectory), isDirectory.boolValue {
                profiles.append((item, profilePath))
            }
        }

        return profiles
    }

    /// Extracts cookies from a specific profile.
    private func extractCookiesFromProfile(
        profilePath: String,
        masterKey: Data,
        domains: [String],
        logger: ((String) -> Void)?
    ) throws -> [WindowsCookieRecord] {
        // Try Network/Cookies first (newer location), then Cookies (legacy)
        let networkCookiesPath = "\(profilePath)\\Network\\Cookies"
        let legacyCookiesPath = "\(profilePath)\\Cookies"

        let cookiesPath: String
        if fileManager.fileExists(atPath: networkCookiesPath) {
            cookiesPath = networkCookiesPath
        } else if fileManager.fileExists(atPath: legacyCookiesPath) {
            cookiesPath = legacyCookiesPath
        } else {
            throw WindowsCookieError.cookieDatabaseNotFound(profilePath)
        }

        logger?("Reading cookies from: \(cookiesPath)")

        // Copy the database to a temp location to avoid lock issues
        let tempPath = NSTemporaryDirectory() + "\\codexbar_cookies_\(UUID().uuidString).db"
        defer {
            try? fileManager.removeItem(atPath: tempPath)
        }

        do {
            try fileManager.copyItem(atPath: cookiesPath, toPath: tempPath)
        } catch {
            throw WindowsCookieError.databaseReadFailed(error)
        }

        return try readCookiesFromDatabase(
            path: tempPath,
            masterKey: masterKey,
            domains: domains,
            logger: logger
        )
    }

    /// Reads cookies from a SQLite database.
    /// Note: SQLite support on Windows requires additional setup.
    private func readCookiesFromDatabase(
        path: String,
        masterKey: Data,
        domains: [String],
        logger: ((String) -> Void)?
    ) throws -> [WindowsCookieRecord] {
        // SQLite support requires linking against sqlite3.dll
        // For now, we'll return an error indicating this feature needs additional setup
        throw WindowsCookieError.databaseReadFailed(
            NSError(
                domain: "CodexBarCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "SQLite support not yet available on Windows. Use manual cookie input or API keys."]
            )
        )
    }

    /// Decrypts a cookie value.
    private func decryptCookieValue(_ encryptedValue: Data, masterKey: Data) throws -> String {
        guard encryptedValue.count > 3 else {
            // Not encrypted, return as-is
            return String(data: encryptedValue, encoding: .utf8) ?? ""
        }

        let prefix = String(data: encryptedValue.prefix(3), encoding: .utf8)

        if prefix == "v10" || prefix == "v11" {
            // Standard DPAPI + AES-GCM encryption
            let ciphertext = encryptedValue.dropFirst(3)
            let decrypted = try WindowsAESGCM.decrypt(ciphertext: Data(ciphertext), key: masterKey)
            return String(data: decrypted, encoding: .utf8) ?? ""
        } else if prefix == "v20" {
            // App-Bound Encryption (Chrome 127+)
            throw WindowsCookieError.appBoundEncryption(
                "This cookie uses App-Bound Encryption which requires elevated privileges to decrypt."
            )
        } else {
            // Might be unencrypted or unknown format
            if let value = String(data: encryptedValue, encoding: .utf8), !value.isEmpty {
                return value
            }
            throw WindowsCookieError.unsupportedEncryptionVersion(prefix ?? "unknown")
        }
    }
}

// Note: Full SQLite cookie extraction requires linking against sqlite3.dll
// This is planned for a future release. For now, users should use:
// 1. Manual cookie input (paste sessionKey from browser dev tools)
// 2. API key authentication

#endif
