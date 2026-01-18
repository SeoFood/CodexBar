import Foundation

/// Cross-platform path utilities
public enum PlatformPaths {
    /// PATH environment variable separator
    public static var pathSeparator: Character {
        #if os(Windows)
        return ";"
        #else
        return ":"
        #endif
    }

    /// PATH environment variable separator as String
    public static var pathSeparatorString: String {
        String(pathSeparator)
    }

    /// User's home directory
    public static var homeDirectory: URL {
        #if os(Windows)
        // Windows: Use USERPROFILE or fallback to FileManager
        if let userProfile = ProcessInfo.processInfo.environment["USERPROFILE"],
           !userProfile.isEmpty {
            return URL(fileURLWithPath: userProfile)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Application config directory
    /// - macOS/Linux: ~/.codexbar
    /// - Windows: %APPDATA%\CodexBar
    public static var configDirectory: URL {
        #if os(Windows)
        // Windows: %APPDATA%\CodexBar
        if let appData = ProcessInfo.processInfo.environment["APPDATA"],
           !appData.isEmpty {
            return URL(fileURLWithPath: appData)
                .appendingPathComponent("CodexBar", isDirectory: true)
        }
        return homeDirectory.appendingPathComponent("CodexBar", isDirectory: true)
        #else
        // Unix: ~/.codexbar
        return homeDirectory.appendingPathComponent(".codexbar", isDirectory: true)
        #endif
    }

    /// Application cache directory
    /// - macOS: ~/Library/Caches/CodexBar
    /// - Linux: ~/.cache/codexbar
    /// - Windows: %LOCALAPPDATA%\CodexBar\Cache
    public static var cacheDirectory: URL {
        #if os(Windows)
        // Windows: %LOCALAPPDATA%\CodexBar\Cache
        if let localAppData = ProcessInfo.processInfo.environment["LOCALAPPDATA"],
           !localAppData.isEmpty {
            return URL(fileURLWithPath: localAppData)
                .appendingPathComponent("CodexBar", isDirectory: true)
                .appendingPathComponent("Cache", isDirectory: true)
        }
        return configDirectory.appendingPathComponent("Cache", isDirectory: true)
        #elseif os(macOS)
        // macOS: ~/Library/Caches/CodexBar
        return homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("CodexBar", isDirectory: true)
        #else
        // Linux: ~/.cache/codexbar
        return homeDirectory
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("codexbar", isDirectory: true)
        #endif
    }

    /// Default shell executable
    public static var defaultShell: String {
        #if os(Windows)
        // Windows: PowerShell or cmd.exe
        if let comSpec = ProcessInfo.processInfo.environment["COMSPEC"] {
            return comSpec
        }
        return "C:\\Windows\\System32\\cmd.exe"
        #else
        // Unix: Use SHELL or fallback to /bin/sh
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        #endif
    }

    /// Executable file extensions to try when searching for binaries
    public static var executableExtensions: [String] {
        #if os(Windows)
        return ["", ".exe", ".cmd", ".bat", ".ps1"]
        #else
        return [""]
        #endif
    }

    /// Standard binary search paths
    public static var standardBinaryPaths: [String] {
        #if os(Windows)
        return [
            "C:\\Windows\\System32",
            "C:\\Windows",
        ]
        #else
        return ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/usr/local/bin"]
        #endif
    }

    /// Path component separator
    public static var pathComponentSeparator: String {
        #if os(Windows)
        return "\\"
        #else
        return "/"
        #endif
    }
}
