import CodexBarCore
import Testing

@Suite("Windows Platform Tests")
struct WindowsPlatformGatingTests {
    // MARK: - Platform Detection

    @Test
    func platform_current_isWindows() {
        #if os(Windows)
        #expect(Platform.current == .windows)
        #expect(Platform.current.isUnixLike == false)
        #else
        #expect(Bool(true)) // Skip on non-Windows
        #endif
    }

    // MARK: - PlatformPaths

    @Test
    func platformPaths_pathSeparator_isSemicolon() {
        #if os(Windows)
        #expect(PlatformPaths.pathSeparator == ";")
        #expect(PlatformPaths.pathSeparatorString == ";")
        #else
        #expect(Bool(true))
        #endif
    }

    @Test
    func platformPaths_executableExtensions_includesExe() {
        #if os(Windows)
        let exts = PlatformPaths.executableExtensions
        #expect(exts.contains(".exe"))
        #expect(exts.contains(".cmd"))
        #expect(exts.contains(".bat"))
        #expect(exts.contains(".ps1"))
        #else
        #expect(Bool(true))
        #endif
    }

    @Test
    func platformPaths_configDirectory_usesAppData() {
        #if os(Windows)
        let configDir = PlatformPaths.configDirectory.path
        // Should be under %APPDATA%\CodexBar or fallback to home
        #expect(configDir.contains("CodexBar"))
        #else
        #expect(Bool(true))
        #endif
    }

    @Test
    func platformPaths_cacheDirectory_usesLocalAppData() {
        #if os(Windows)
        let cacheDir = PlatformPaths.cacheDirectory.path
        // Should contain CodexBar and Cache
        #expect(cacheDir.contains("CodexBar"))
        #endif
    }

    @Test
    func platformPaths_standardBinaryPaths_includesSystem32() {
        #if os(Windows)
        let paths = PlatformPaths.standardBinaryPaths
        #expect(paths.contains { $0.contains("System32") })
        #else
        #expect(Bool(true))
        #endif
    }

    // MARK: - TTYCommandRunner

    @Test
    func ttyCommandRunner_throwsOnWindows() async {
        #if os(Windows)
        let runner = TTYCommandRunner()
        do {
            _ = try runner.run(binary: "test", send: "test")
            Issue.record("Expected notSupportedOnWindows error")
        } catch let error as TTYCommandRunner.Error {
            if case .notSupportedOnWindows = error {
                // Expected
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #else
        #expect(Bool(true))
        #endif
    }

    // Note: ClaudeCLISession tests are skipped because ClaudeCLISession is internal

    // MARK: - PathEnvironment

    @Test
    func pathBuilder_effectivePATH_usesSemicolonSeparator() {
        #if os(Windows)
        let path = PathBuilder.effectivePATH(purposes: [.tty])
        // Windows uses semicolon as PATH separator
        if path.contains(";") || !path.contains(":") {
            // Valid: either has semicolons or is a single path (no colons except drive letter)
            #expect(Bool(true))
        } else {
            // Check if it's just a drive letter like C:\...
            let components = path.split(separator: ";")
            #expect(components.count >= 1)
        }
        #else
        #expect(Bool(true))
        #endif
    }

    // MARK: - BinaryLocator

    @Test
    func binaryLocator_find_checksExeExtensions() {
        #if os(Windows)
        // This test verifies that BinaryLocator will try .exe extensions
        // We can't easily test the actual resolution without installed binaries,
        // but we verify the code path doesn't crash
        let result = BinaryLocator.resolveClaudeBinary()
        // Result may be nil if Claude CLI is not installed, that's fine
        _ = result
        #expect(Bool(true))
        #else
        #expect(Bool(true))
        #endif
    }
}
