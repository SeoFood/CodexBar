# CodexBar CLI Windows-Portierung - Implementierungsplan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Die `codexbar` CLI auf Windows portieren, sodass Nutzer Provider-Usage über die Kommandozeile abfragen können.

**Architecture:** Cross-Platform Swift mit Conditional Compilation (`#if os(Windows)`). PTY-basierte Provider (Codex CLI) werden auf Windows durch alternative Strategien ersetzt.

**Tech Stack:** Swift 6.0+, Swift Package Manager, Windows ConPTY API (optional), PowerShell Build-Scripts

---

## Übersicht der Änderungen

| Datei | Änderungstyp | Aufwand |
|-------|--------------|---------|
| `Package.swift` | Windows-Platform hinzufügen | Klein |
| `PathEnvironment.swift` | PATH-Separator, Shell-Pfade | Mittel |
| `SubprocessRunner.swift` | Process-Signale für Windows | Mittel |
| `TTYCommandRunner.swift` | ConPTY oder Fallback | Groß |
| `Config/CodexBarConfigStore.swift` | Config-Pfade | Klein |
| Provider-Dateien | Conditional Compilation | Klein-Mittel |
| Build-Scripts | PowerShell-Version | Mittel |

---

## Task 1: Package.swift für Windows anpassen

**Files:**
- Modify: `Package.swift:14-17`

**Step 1.1: Lese aktuelle Package.swift**

Run: `cat Package.swift | head -30`

**Step 1.2: Platform-Definition erweitern**

Ersetze die Platform-Definition um Windows zu unterstützen:

```swift
// Vorher (Zeile 14-17):
let package = Package(
    name: "CodexBar",
    platforms: [
        .macOS(.v14),
    ],

// Nachher:
let package = Package(
    name: "CodexBar",
    platforms: [
        .macOS(.v14),
        // Windows wird implizit unterstützt wenn keine Platform angegeben
    ],
```

**Hinweis:** Swift Package Manager unterstützt Windows implizit. Die `platforms:` Angabe ist nur für Apple-Plattformen relevant.

**Step 1.3: SweetCookieKit für Windows deaktivieren**

SweetCookieKit ist macOS-spezifisch (Browser-Cookie-Entschlüsselung). Für Windows muss es conditional sein:

```swift
// In targets Array, CodexBarCore target (Zeile 29-38):
.target(
    name: "CodexBarCore",
    dependencies: [
        "CodexBarMacroSupport",
        .product(name: "Logging", package: "swift-log"),
    ] + {
        #if os(macOS)
        return [.product(name: "SweetCookieKit", package: "SweetCookieKit")]
        #else
        return []
        #endif
    }(),
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
    ]),
```

**Step 1.4: Verifiziere Build auf Linux (als Proxy für non-macOS)**

Run: `swift build --target CodexBarCLI 2>&1 | head -50`

**Step 1.5: Commit**

```bash
git add Package.swift
git commit -m "feat(windows): prepare Package.swift for Windows support

- Remove strict macOS platform requirement for CLI target
- Make SweetCookieKit dependency conditional on macOS

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Platform-Abstraktionsschicht erstellen

**Files:**
- Create: `Sources/CodexBarCore/Platform/Platform.swift`
- Create: `Sources/CodexBarCore/Platform/PlatformPaths.swift`

**Step 2.1: Erstelle Platform-Enum**

```swift
// Sources/CodexBarCore/Platform/Platform.swift
import Foundation

public enum Platform: String, Sendable {
    case macOS
    case windows
    case linux

    public static var current: Platform {
        #if os(macOS)
        return .macOS
        #elseif os(Windows)
        return .windows
        #else
        return .linux
        #endif
    }

    public var isUnixLike: Bool {
        switch self {
        case .macOS, .linux: return true
        case .windows: return false
        }
    }
}
```

**Step 2.2: Erstelle PlatformPaths**

```swift
// Sources/CodexBarCore/Platform/PlatformPaths.swift
import Foundation

public enum PlatformPaths {
    /// PATH environment variable separator
    public static var pathSeparator: Character {
        #if os(Windows)
        return ";"
        #else
        return ":"
        #endif
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
        #else
        // Unix: ~/.cache/codexbar
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

    /// Executable file extension
    public static var executableExtension: String {
        #if os(Windows)
        return ".exe"
        #else
        return ""
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
}
```

**Step 2.3: Verifiziere Kompilierung**

Run: `swift build --target CodexBarCore 2>&1 | grep -E "(error|warning)" | head -20`

**Step 2.4: Commit**

```bash
git add Sources/CodexBarCore/Platform/
git commit -m "feat(windows): add Platform abstraction layer

- Platform enum for runtime platform detection
- PlatformPaths for cross-platform path handling
- Support for Windows config/cache directories

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: PathEnvironment.swift anpassen

**Files:**
- Modify: `Sources/CodexBarCore/PathEnvironment.swift`

**Step 3.1: Import PlatformPaths und PATH-Separator anpassen**

Ersetze alle `:` PATH-Separator mit `PlatformPaths.pathSeparator`:

```swift
// Zeile 147: existingPATH.split(separator: ":")
// Ändern zu:
existingPATH.split(separator: PlatformPaths.pathSeparator).map(String.init)
```

```swift
// Zeile 337: existing.split(separator: ":")
// Ändern zu:
existing.split(separator: PlatformPaths.pathSeparator).map(String.init)
```

```swift
// Zeile 353: deduped.joined(separator: ":")
// Ändern zu:
deduped.joined(separator: String(PlatformPaths.pathSeparator))
```

```swift
// Zeile 370: login?.joined(separator: ":")
// Ändern zu:
login?.joined(separator: String(PlatformPaths.pathSeparator))
```

```swift
// Zeile 439: value.split(separator: ":")
// Ändern zu:
value.split(separator: PlatformPaths.pathSeparator).map(String.init)
```

**Step 3.2: Shell-Pfade für Windows anpassen**

```swift
// Zeile 236: let shellPath = (shell?.isEmpty == false) ? shell! : "/bin/zsh"
// Ändern zu:
let shellPath: String
#if os(Windows)
shellPath = PlatformPaths.defaultShell
#else
shellPath = (shell?.isEmpty == false) ? shell! : "/bin/zsh"
#endif
```

**Step 3.3: Fallback-Pfade für Windows**

```swift
// Zeile 168: let fallback = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
// Ändern zu:
let fallback = PlatformPaths.standardBinaryPaths
```

**Step 3.4: NSHomeDirectory() durch PlatformPaths ersetzen**

```swift
// Alle Vorkommen von NSHomeDirectory() ersetzen:
// home: String = NSHomeDirectory()
// Ändern zu:
// home: String = PlatformPaths.homeDirectory.path
```

Betroffene Zeilen: 46, 66, 86, 106, 328, 359, 382

**Step 3.5: Windows-spezifische Binary-Suche**

```swift
// In find() Funktion (Zeile 176-184), nach dem candidate hinzufügen:
private static func find(_ binary: String, in paths: [String], fileManager: FileManager) -> String? {
    for path in paths where !path.isEmpty {
        let normalizedPath = path.hasSuffix("/") || path.hasSuffix("\\")
            ? String(path.dropLast())
            : path

        #if os(Windows)
        // Windows: Try with common executable extensions
        let extensions = ["", ".exe", ".cmd", ".bat", ".ps1"]
        for ext in extensions {
            let candidate = "\(normalizedPath)\\\(binary)\(ext)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        #else
        let candidate = "\(normalizedPath)/\(binary)"
        if fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        #endif
    }
    return nil
}
```

**Step 3.6: Shell-Capture für Windows deaktivieren**

Die Login-Shell-Capture-Logik ist Unix-spezifisch. Für Windows überspringen:

```swift
// In runShellCapture (Zeile 235-264), am Anfang hinzufügen:
private static func runShellCapture(_ shell: String?, _ timeout: TimeInterval, _ command: String) -> String? {
    #if os(Windows)
    // Windows does not use login shell PATH capture
    return nil
    #else
    // ... existing Unix code ...
    #endif
}
```

**Step 3.7: Tests ausführen**

Run: `swift test --filter PathEnvironment 2>&1 | tail -30`

**Step 3.8: Commit**

```bash
git add Sources/CodexBarCore/PathEnvironment.swift
git commit -m "feat(windows): make PathEnvironment cross-platform

- Use PlatformPaths for PATH separator (: vs ;)
- Add Windows executable extensions (.exe, .cmd, .bat)
- Replace NSHomeDirectory with PlatformPaths.homeDirectory
- Disable login shell capture on Windows

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: SubprocessRunner.swift für Windows anpassen

**Files:**
- Modify: `Sources/CodexBarCore/Host/Process/SubprocessRunner.swift`

**Step 4.1: Windows-Import hinzufügen**

```swift
// Am Anfang der Datei (Zeile 1-6):
#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import WinSDK
#else
import Glibc
#endif
import Foundation
```

**Step 4.2: setpgid für Windows ersetzen**

```swift
// Zeile 77-81:
var processGroup: pid_t?
let pid = process.processIdentifier
if setpgid(pid, pid) == 0 {
    processGroup = pid
}

// Ändern zu:
#if os(Windows)
// Windows: Process groups handled differently via Job Objects
// For now, we skip process group management on Windows
let processGroup: Int32? = nil
#else
var processGroup: pid_t?
let pid = process.processIdentifier
if setpgid(pid, pid) == 0 {
    processGroup = pid
}
#endif
```

**Step 4.3: kill() für Windows ersetzen**

```swift
// Zeile 111-125:
if process.isRunning {
    process.terminate()
    if let pgid = processGroup {
        kill(-pgid, SIGTERM)
    }
    let killDeadline = Date().addingTimeInterval(0.4)
    while process.isRunning, Date() < killDeadline {
        usleep(50000)
    }
    if process.isRunning {
        if let pgid = processGroup {
            kill(-pgid, SIGKILL)
        }
        kill(process.processIdentifier, SIGKILL)
    }
}

// Ändern zu:
if process.isRunning {
    process.terminate()
    #if !os(Windows)
    if let pgid = processGroup {
        kill(-pgid, SIGTERM)
    }
    #endif
    let killDeadline = Date().addingTimeInterval(0.4)
    while process.isRunning, Date() < killDeadline {
        #if os(Windows)
        Thread.sleep(forTimeInterval: 0.05)
        #else
        usleep(50000)
        #endif
    }
    if process.isRunning {
        #if os(Windows)
        // Windows: Process.terminate() should suffice
        // For forceful termination, we'd need TerminateProcess via WinSDK
        #else
        if let pgid = processGroup {
            kill(-pgid, SIGKILL)
        }
        kill(process.processIdentifier, SIGKILL)
        #endif
    }
}
```

**Step 4.4: Verifiziere Kompilierung**

Run: `swift build --target CodexBarCore 2>&1 | grep -E "SubprocessRunner" | head -10`

**Step 4.5: Commit**

```bash
git add Sources/CodexBarCore/Host/Process/SubprocessRunner.swift
git commit -m "feat(windows): make SubprocessRunner cross-platform

- Add Windows SDK import
- Replace setpgid with no-op on Windows
- Replace kill/SIGTERM/SIGKILL with Thread.sleep on Windows
- Process termination via Process.terminate()

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 5: TTYCommandRunner Windows-Strategie

**Files:**
- Modify: `Sources/CodexBarCore/Host/PTY/TTYCommandRunner.swift`

Die PTY-Logik ist fundamental Unix-spezifisch. Für Windows gibt es zwei Optionen:

**Option A:** ConPTY API implementieren (aufwändig, vollständige Kompatibilität)
**Option B:** TTY-Features auf Windows deaktivieren, Provider nutzen HTTP-APIs (einfacher)

Wir wählen **Option B** für die initiale Portierung.

**Step 5.1: TTYCommandRunner auf Windows deaktivieren**

```swift
// Am Anfang der Datei, nach den Imports (ca. Zeile 8):
#if os(Windows)
/// TTYCommandRunner is not available on Windows.
/// Use HTTP-based provider strategies instead.
public struct TTYCommandRunner {
    public struct Result: Sendable {
        public let text: String
    }

    public struct Options: Sendable {
        public var timeout: TimeInterval = 20.0
        public init(timeout: TimeInterval = 20.0) {
            self.timeout = timeout
        }
    }

    public enum Error: Swift.Error, LocalizedError, Sendable {
        case notSupportedOnWindows

        public var errorDescription: String? {
            "TTY commands are not supported on Windows. Use HTTP-based provider APIs."
        }
    }

    public init() {}

    public func run(
        binary: String,
        send script: String,
        options: Options = Options(),
        onURLDetected: (@Sendable () -> Void)? = nil) throws -> Result
    {
        throw Error.notSupportedOnWindows
    }

    public static func which(_ tool: String) -> String? {
        // Use BinaryLocator for Windows
        if tool == "codex", let located = BinaryLocator.resolveCodexBinary() { return located }
        if tool == "claude", let located = BinaryLocator.resolveClaudeBinary() { return located }
        return nil
    }

    public static func enrichedPath() -> String {
        PathBuilder.effectivePATH(
            purposes: [.tty, .nodeTooling],
            env: ProcessInfo.processInfo.environment)
    }
}
#else
// ... existing Unix implementation ...
#endif
```

**Step 5.2: Conditional Compilation um gesamte Unix-Implementierung**

Wrape den gesamten bestehenden Code (Zeile 10 bis Ende) in `#else` / `#endif`:

```swift
#if os(Windows)
// Windows stub (siehe oben)
#else
// === Bestehender Unix-Code ===
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

public struct TTYCommandRunner {
    // ... gesamter bestehender Code ...
}
#endif // os(Windows)
```

**Step 5.3: Verifiziere Kompilierung**

Run: `swift build --target CodexBarCore 2>&1 | grep -E "(error|TTY)" | head -10`

**Step 5.4: Commit**

```bash
git add Sources/CodexBarCore/Host/PTY/TTYCommandRunner.swift
git commit -m "feat(windows): disable TTY on Windows with stub implementation

- Windows does not support Unix PTY (openpty, fcntl)
- Provide stub that throws notSupportedOnWindows error
- Providers should use HTTP-based strategies on Windows

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Config-Pfade anpassen

**Files:**
- Modify: `Sources/CodexBarCore/Config/CodexBarConfigStore.swift`

**Step 6.1: Lese aktuelle Config-Pfad-Logik**

Run: `grep -n "configDirectory\|\.codexbar" Sources/CodexBarCore/Config/*.swift`

**Step 6.2: PlatformPaths verwenden**

```swift
// Ersetze hardcoded ~/.codexbar mit PlatformPaths.configDirectory
// Suche nach Mustern wie:
// homeDirectory.appendingPathComponent(".codexbar")
// Ersetze durch:
// PlatformPaths.configDirectory
```

**Step 6.3: Verifiziere Config-Loading**

Run: `swift build --target CodexBarCLI && .build/debug/codexbar config validate 2>&1`

**Step 6.4: Commit**

```bash
git add Sources/CodexBarCore/Config/
git commit -m "feat(windows): use PlatformPaths for config directory

- Replace hardcoded ~/.codexbar with PlatformPaths.configDirectory
- Windows uses %APPDATA%\\CodexBar

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Provider HTTP-Strategien priorisieren

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Providers.swift`

Die meisten Provider haben sowohl TTY- als auch HTTP-basierte Strategien. Für Windows müssen HTTP-Strategien bevorzugt werden.

**Step 7.1: Provider-Strategie-Auswahl anpassen**

```swift
// In der Provider-Initialisierung/Strategie-Auswahl:
#if os(Windows)
// Windows: Prefer HTTP-based strategies, skip TTY-based ones
let preferHTTP = true
#else
let preferHTTP = false
#endif
```

**Step 7.2: Betroffene Provider identifizieren**

Provider mit TTY-Abhängigkeit:
- Codex (CodexCLISession via TTYCommandRunner)
- Claude (ClaudeCLISession via TTYCommandRunner)

Diese Provider müssen auf Windows ihre HTTP/API-Strategien nutzen.

**Step 7.3: Conditional Compilation in Provider-Descriptors**

```swift
// Beispiel für CodexProviderDescriptor:
public var availableStrategies: [CodexStrategy] {
    #if os(Windows)
    // Windows: Only HTTP-based strategies
    return [.httpAPI, .webDashboard]
    #else
    return [.cli, .httpAPI, .webDashboard]
    #endif
}
```

**Step 7.4: Commit**

```bash
git add Sources/CodexBarCore/Providers/
git commit -m "feat(windows): prefer HTTP strategies on Windows

- Skip TTY-based provider strategies on Windows
- Codex/Claude use HTTP APIs instead of CLI probes

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Windows Build-Script erstellen

**Files:**
- Create: `Scripts/build-windows.ps1`
- Create: `Scripts/build-windows.bat`

**Step 8.1: PowerShell Build-Script**

```powershell
# Scripts/build-windows.ps1
# CodexBar Windows Build Script

param(
    [switch]$Release,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

Write-Host "CodexBar Windows Build" -ForegroundColor Cyan

# Check Swift installation
$swiftVersion = swift --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Swift is not installed. Please install Swift for Windows from https://www.swift.org/download/"
    exit 1
}
Write-Host "Swift: $($swiftVersion[0])" -ForegroundColor Green

# Clean if requested
if ($Clean) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    if (Test-Path ".build") {
        Remove-Item -Recurse -Force ".build"
    }
}

# Build configuration
$config = if ($Release) { "release" } else { "debug" }
Write-Host "Building in $config mode..." -ForegroundColor Yellow

# Build CLI target only (skip macOS-specific targets)
swift build -c $config --target CodexBarCLI

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed!"
    exit 1
}

# Copy executable to dist
$distDir = "dist\windows"
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}

$exePath = ".build\$config\CodexBarCLI.exe"
if (Test-Path $exePath) {
    Copy-Item $exePath "$distDir\codexbar.exe"
    Write-Host "Build successful! Executable at: $distDir\codexbar.exe" -ForegroundColor Green
} else {
    # Swift on Windows may use different naming
    $altPath = ".build\$config\codexbar.exe"
    if (Test-Path $altPath) {
        Copy-Item $altPath "$distDir\codexbar.exe"
        Write-Host "Build successful! Executable at: $distDir\codexbar.exe" -ForegroundColor Green
    } else {
        Write-Warning "Executable not found at expected path. Check .build\$config\ directory."
    }
}
```

**Step 8.2: Batch-Wrapper für einfachen Aufruf**

```batch
@echo off
REM Scripts/build-windows.bat
REM Simple wrapper for PowerShell build script

powershell -ExecutionPolicy Bypass -File "%~dp0build-windows.ps1" %*
```

**Step 8.3: Ausführbar machen und testen (auf Windows)**

```powershell
# Auf Windows ausführen:
.\Scripts\build-windows.ps1
.\dist\windows\codexbar.exe --help
```

**Step 8.4: Commit**

```bash
git add Scripts/build-windows.ps1 Scripts/build-windows.bat
git commit -m "feat(windows): add Windows build scripts

- PowerShell build script with Release/Debug modes
- Batch wrapper for easy invocation
- Outputs to dist/windows/codexbar.exe

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Windows-spezifische Tests

**Files:**
- Create: `TestsWindows/PlatformTests.swift`
- Create: `TestsWindows/PathEnvironmentWindowsTests.swift`

**Step 9.1: Test-Verzeichnis erstellen**

```bash
mkdir -p TestsWindows
```

**Step 9.2: Platform-Tests**

```swift
// TestsWindows/PlatformTests.swift
import Testing
@testable import CodexBarCore

@Suite("Platform Tests")
struct PlatformTests {
    @Test("Current platform detection")
    func testCurrentPlatform() {
        #if os(Windows)
        #expect(Platform.current == .windows)
        #expect(!Platform.current.isUnixLike)
        #elseif os(macOS)
        #expect(Platform.current == .macOS)
        #expect(Platform.current.isUnixLike)
        #else
        #expect(Platform.current == .linux)
        #expect(Platform.current.isUnixLike)
        #endif
    }

    @Test("Path separator")
    func testPathSeparator() {
        #if os(Windows)
        #expect(PlatformPaths.pathSeparator == ";")
        #else
        #expect(PlatformPaths.pathSeparator == ":")
        #endif
    }

    @Test("Config directory exists or can be created")
    func testConfigDirectory() {
        let configDir = PlatformPaths.configDirectory
        #expect(!configDir.path.isEmpty)

        #if os(Windows)
        #expect(configDir.path.contains("CodexBar"))
        #else
        #expect(configDir.path.contains(".codexbar"))
        #endif
    }
}
```

**Step 9.3: PathEnvironment Windows-Tests**

```swift
// TestsWindows/PathEnvironmentWindowsTests.swift
import Testing
@testable import CodexBarCore

#if os(Windows)
@Suite("PathEnvironment Windows Tests")
struct PathEnvironmentWindowsTests {
    @Test("Binary resolution with .exe extension")
    func testBinaryResolutionWithExtension() {
        // Test that Windows adds .exe when searching
        let fm = FileManager.default

        // cmd.exe should be findable
        let cmdPath = BinaryLocator.resolveClaudeBinary(
            env: ["PATH": "C:\\Windows\\System32"],
            loginPATH: nil,
            fileManager: fm)

        // This test is informational - claude may not be installed
        // The important thing is no crash
    }

    @Test("PATH splitting uses semicolon")
    func testPathSplitting() {
        let testPath = "C:\\Users\\Test;C:\\Windows;C:\\Program Files"
        let components = testPath.split(separator: PlatformPaths.pathSeparator)
        #expect(components.count == 3)
        #expect(components[0] == "C:\\Users\\Test")
    }
}
#endif
```

**Step 9.4: Package.swift Test-Target hinzufügen**

```swift
// In Package.swift, nach CodexBarLinuxTests:
.testTarget(
    name: "CodexBarWindowsTests",
    dependencies: ["CodexBarCore", "CodexBarCLI"],
    path: "TestsWindows",
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
        .enableExperimentalFeature("SwiftTesting"),
    ]),
```

**Step 9.5: Tests ausführen (auf Windows)**

```powershell
swift test --filter Windows
```

**Step 9.6: Commit**

```bash
git add TestsWindows/ Package.swift
git commit -m "test(windows): add Windows-specific tests

- Platform detection tests
- PATH separator tests
- Binary resolution tests

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 10: Dokumentation aktualisieren

**Files:**
- Modify: `README.md` (falls vorhanden)
- Create: `docs/WINDOWS.md`

**Step 10.1: Windows-Dokumentation erstellen**

```markdown
# CodexBar on Windows

## Requirements

- Windows 10 or later
- Swift 6.0+ for Windows ([Download](https://www.swift.org/download/))
- Visual Studio Build Tools (for Swift compilation)

## Installation

### From Source

```powershell
git clone https://github.com/steipete/CodexBar.git
cd CodexBar
.\Scripts\build-windows.ps1 -Release
```

The executable will be at `dist\windows\codexbar.exe`.

### Add to PATH

```powershell
# Add to user PATH
$env:Path += ";C:\path\to\CodexBar\dist\windows"
[Environment]::SetEnvironmentVariable("Path", $env:Path, [EnvironmentVariableTarget]::User)
```

## Usage

```powershell
# Show usage for all providers
codexbar usage

# JSON output
codexbar usage --json

# Specific provider
codexbar usage --provider claude
```

## Configuration

Config file location: `%APPDATA%\CodexBar\config.json`

```json
{
  "providers": {
    "claude": {
      "enabled": true,
      "apiKey": "sk-..."
    }
  }
}
```

## Limitations on Windows

- **No TTY-based probes**: Codex/Claude CLI probes require Unix PTY. Use HTTP API strategies instead.
- **No browser cookie import**: Browser cookie extraction is macOS-only.
- **No system tray**: CLI-only on Windows (GUI planned for future release).

## Troubleshooting

### Swift not found

Ensure Swift is installed and added to PATH:

```powershell
swift --version
```

### Build errors

Make sure Visual Studio Build Tools are installed with C++ workload.
```

**Step 10.2: Commit**

```bash
git add docs/WINDOWS.md
git commit -m "docs(windows): add Windows installation and usage guide

- Build instructions for Windows
- Configuration file location
- Known limitations
- Troubleshooting tips

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 11: CI/CD für Windows (Optional)

**Files:**
- Create: `.github/workflows/windows.yml`

**Step 11.1: GitHub Actions Workflow**

```yaml
# .github/workflows/windows.yml
name: Windows Build

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Swift
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: "6.0"

      - name: Build
        run: swift build --target CodexBarCLI

      - name: Test
        run: swift test --filter CodexBarWindowsTests

      - name: Package
        if: github.ref == 'refs/heads/main'
        run: |
          mkdir -p dist/windows
          cp .build/debug/CodexBarCLI.exe dist/windows/codexbar.exe

      - name: Upload Artifact
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: codexbar-windows
          path: dist/windows/codexbar.exe
```

**Step 11.2: Commit**

```bash
git add .github/workflows/windows.yml
git commit -m "ci(windows): add Windows build workflow

- Build and test on windows-latest
- Upload artifact for main branch

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Zusammenfassung

Nach Abschluss aller Tasks:

| Task | Beschreibung | Status |
|------|--------------|--------|
| 1 | Package.swift anpassen | ⬜ |
| 2 | Platform-Abstraktionsschicht | ⬜ |
| 3 | PathEnvironment cross-platform | ⬜ |
| 4 | SubprocessRunner cross-platform | ⬜ |
| 5 | TTYCommandRunner Windows-Stub | ⬜ |
| 6 | Config-Pfade | ⬜ |
| 7 | Provider HTTP-Strategien | ⬜ |
| 8 | Windows Build-Scripts | ⬜ |
| 9 | Windows-Tests | ⬜ |
| 10 | Dokumentation | ⬜ |
| 11 | CI/CD (Optional) | ⬜ |

## Nächste Schritte nach CLI-Portierung

1. **Testen auf echtem Windows** - Virtuelle Maschine oder physisches System
2. **Provider-Kompatibilität prüfen** - Welche Provider funktionieren mit HTTP-only?
3. **System Tray App planen** - Wenn CLI funktioniert, kann GUI-Arbeit beginnen
