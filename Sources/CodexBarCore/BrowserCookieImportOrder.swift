#if os(macOS)
import SweetCookieKit

public typealias BrowserCookieImportOrder = [Browser]

#elseif os(Windows)

/// Browser types for Windows - subset of macOS browsers that use Chromium.
public enum Browser: String, Sendable, Hashable, CaseIterable {
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
    // Not supported on Windows:
    case safari
    case firefox
    case arc
    case arcBeta
    case arcCanary
    case chatgptAtlas
    case helium

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
        case .safari: return "Safari"
        case .firefox: return "Firefox"
        case .arc: return "Arc"
        case .arcBeta: return "Arc Beta"
        case .arcCanary: return "Arc Canary"
        case .chatgptAtlas: return "ChatGPT Atlas"
        case .helium: return "Helium"
        }
    }

    /// Preferred import order for Windows (Edge first as most likely to work).
    public static let defaultImportOrder: [Browser] = [
        .edge,
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
}

public typealias BrowserCookieImportOrder = [Browser]

#else

/// Stub Browser for other platforms (Linux, etc.)
public struct Browser: Sendable, Hashable {
    public init() {}
}

public typealias BrowserCookieImportOrder = [Browser]

#endif

extension [Browser] {
    /// Filters a browser list to sources worth attempting for cookie imports.
    ///
    /// This is intentionally stricter than "app installed": it aims to avoid unnecessary Keychain prompts.
    public func cookieImportCandidates(using detection: BrowserDetection) -> [Browser] {
        guard !KeychainAccessGate.isDisabled else { return [] }
        let candidates = self.filter { detection.isCookieSourceAvailable($0) }
        return candidates.filter { BrowserCookieAccessGate.shouldAttempt($0) }
    }

    /// Filters a browser list to sources with usable profile data on disk.
    public func browsersWithProfileData(using detection: BrowserDetection) -> [Browser] {
        self.filter { detection.hasUsableProfileData($0) }
    }
}

#if os(macOS)
extension Browser {
    var usesKeychainForCookieDecryption: Bool {
        switch self {
        case .safari, .firefox:
            return false
        case .chrome, .chromeBeta, .chromeCanary,
             .arc, .arcBeta, .arcCanary,
             .chatgptAtlas,
             .chromium,
             .brave, .braveBeta, .braveNightly,
             .edge, .edgeBeta, .edgeCanary,
             .helium,
             .vivaldi:
            return true
        @unknown default:
            return true
        }
    }
}
#elseif os(Windows)
extension Browser {
    // Windows uses DPAPI, not Keychain
    var usesKeychainForCookieDecryption: Bool { false }
}
#else
extension Browser {
    var usesKeychainForCookieDecryption: Bool { false }
}
#endif
