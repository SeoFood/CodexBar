import Foundation

/// Represents the current operating system platform
public enum Platform: String, Sendable {
    case macOS
    case windows
    case linux

    /// The platform this code is currently running on
    public static var current: Platform {
        #if os(macOS)
        return .macOS
        #elseif os(Windows)
        return .windows
        #else
        return .linux
        #endif
    }

    /// Whether this platform uses Unix-like conventions (paths, signals, etc.)
    public var isUnixLike: Bool {
        switch self {
        case .macOS, .linux: return true
        case .windows: return false
        }
    }
}
