# CodexBar Windows-Portierung - Evaluierungsplan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** CodexBar auf Windows portieren, um AI Provider Usage Monitoring auch unter Windows zu ermöglichen.

**Architecture:** Evaluierung von drei Hauptansätzen (CLI-only, System Tray App, Web Dashboard) mit unterschiedlichen Technologie-Stacks und Trade-offs.

**Tech Stack:** Swift (bestehend), .NET/WPF, Electron/Tauri, oder Web-basiert je nach gewähltem Ansatz.

---

## Inhaltsverzeichnis

1. [Status Quo Analyse](#1-status-quo-analyse)
2. [Portierungsansätze im Vergleich](#2-portierungsansätze-im-vergleich)
3. [Ansatz A: CLI-only](#3-ansatz-a-cli-only)
4. [Ansatz B: System Tray App](#4-ansatz-b-system-tray-app)
5. [Ansatz C: Web Dashboard](#5-ansatz-c-web-dashboard)
6. [Code-Änderungen im Detail](#6-code-änderungen-im-detail)
7. [Empfehlung](#7-empfehlung)

---

## 1. Status Quo Analyse

### Aktuelle Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                    CodexBar (macOS)                         │
├─────────────────────────────────────────────────────────────┤
│  UI Layer (AppKit)          │  CLI Layer                    │
│  - NSStatusItem (Menu Bar)  │  - codexbar CLI               │
│  - SwiftUI Views            │  - Commander Framework        │
│  - Preferences Window       │                               │
├─────────────────────────────┴───────────────────────────────┤
│                    CodexBarCore                              │
│  - Providers (Claude, Codex, Gemini, Cursor, ...)           │
│  - Config Management                                         │
│  - Process Runner (PTY, Subprocess)                         │
│  - Browser Cookie Detection                                  │
│  - Cost/Usage Scanning                                       │
├─────────────────────────────────────────────────────────────┤
│                    Platform Layer                            │
│  - Keychain (Credentials)                                    │
│  - UserDefaults (Settings)                                   │
│  - FileManager (Paths)                                       │
│  - PTY/Terminal (openpty, fcntl)                            │
└─────────────────────────────────────────────────────────────┘
```

### Plattform-spezifische Abhängigkeiten

| Komponente | macOS API | Windows Äquivalent | Aufwand |
|------------|-----------|-------------------|---------|
| Menu Bar UI | AppKit NSStatusItem | System Tray NotifyIcon | Neu schreiben |
| PTY/Terminal | openpty(), fcntl() | ConPTY / Named Pipes | Groß |
| Credentials | Keychain | Credential Manager / DPAPI | Mittel |
| Settings | UserDefaults | Registry / JSON | Klein |
| Path Resolution | `/usr/bin/env`, `:` separator | `%PATH%`, `;` separator | Klein |
| Browser Cookies | ~/Library/... | %APPDATA%/... | Mittel |
| Process Signals | kill(), SIGTERM | TerminateProcess, Job Objects | Mittel |

### Betroffene Dateien

**Kritisch (komplettes Rewrite für Windows):**
- `Sources/CodexBar/` - Gesamte macOS UI (~50 Dateien)
- `Sources/CodexBarCore/Host/PTY/TTYCommandRunner.swift` - PTY-basierter Prozessstart
- `Sources/CodexBarWidget/` - macOS WidgetKit

**Mittlerer Aufwand:**
- `Sources/CodexBarCore/Host/Process/SubprocessRunner.swift` - Prozess-Management
- `Sources/CodexBarCore/PathEnvironment.swift` - Pfad-Auflösung
- `Sources/CodexBarCore/BrowserDetection.swift` - Browser-Pfade
- `Sources/CodexBarCore/Providers/Claude/ClaudeCLISession.swift` - CLI-Integration

**Geringer Aufwand (hauptsächlich #if os(Windows)):**
- `Sources/CodexBarCore/Config/` - Konfiguration
- `Sources/CodexBarCore/Providers/*/` - Provider-Logik (meist HTTP-basiert)
- `Sources/CodexBarCLI/` - CLI-Framework

---

## 2. Portierungsansätze im Vergleich

| Kriterium | A: CLI-only | B: System Tray | C: Web Dashboard |
|-----------|-------------|----------------|------------------|
| **Entwicklungsaufwand** | Niedrig | Hoch | Mittel |
| **UX-Qualität** | Minimal | Nativ | Gut |
| **Wartbarkeit** | Einfach | Komplex (2 Codebases) | Mittel |
| **Swift-Wiederverwendung** | ~70% | ~40% (Core) | ~60% |
| **Geschätzte Zeit** | 2-4 Wochen | 2-4 Monate | 1-2 Monate |
| **Automatischer Start** | Task Scheduler | Ja, nativ | Dienst + Browser |

---

## 3. Ansatz A: CLI-only

### Beschreibung

Portierung nur der `codexbar` CLI auf Windows. Keine GUI, Nutzung über Terminal/PowerShell.

### Vorteile
- Schnellste Implementierung
- Maximale Code-Wiederverwendung
- Einfache Wartung
- Kann als Basis für andere Ansätze dienen

### Nachteile
- Keine visuelle Anzeige
- Benutzer müssen Terminal öffnen
- Kein automatisches Monitoring im Hintergrund

### Notwendige Änderungen

#### Task A.1: Swift für Windows Build-Setup

**Files:**
- Modify: `Package.swift`
- Create: `Scripts/build-windows.ps1`

**Schritte:**

1. Swift für Windows installieren (Swift 6.0+ unterstützt Windows)
2. Windows-spezifische Conditional Compilation hinzufügen
3. Build-Script für Windows erstellen

```swift
// Package.swift - Windows-Target hinzufügen
#if os(Windows)
    .executableTarget(
        name: "codexbar",
        dependencies: ["CodexBarCore"],
        path: "Sources/CodexBarCLI"
    ),
#endif
```

#### Task A.2: Pfad-Handling Windows-kompatibel machen

**Files:**
- Modify: `Sources/CodexBarCore/PathEnvironment.swift:45-80`

```swift
// Vorher (Unix)
let components = pathEnv.split(separator: ":")

// Nachher (Cross-platform)
#if os(Windows)
let pathSeparator: Character = ";"
let executableExtensions = [".exe", ".cmd", ".bat", ".ps1"]
#else
let pathSeparator: Character = ":"
let executableExtensions = [""]
#endif
let components = pathEnv.split(separator: pathSeparator)
```

#### Task A.3: Prozess-Runner für Windows

**Files:**
- Modify: `Sources/CodexBarCore/Host/Process/SubprocessRunner.swift`

```swift
#if os(Windows)
import WinSDK

extension SubprocessRunner {
    func terminateProcess(_ process: Process) {
        // Windows: TerminateProcess statt kill()
        if let handle = process.processIdentifier {
            TerminateProcess(handle, 1)
        }
    }
}
#else
// Bestehender Unix-Code
#endif
```

#### Task A.4: Config-Pfade für Windows

**Files:**
- Modify: `Sources/CodexBarCore/Config/ConfigPath.swift`

```swift
static var configDirectory: URL {
    #if os(Windows)
    // %APPDATA%\CodexBar
    let appData = ProcessInfo.processInfo.environment["APPDATA"] ?? ""
    return URL(fileURLWithPath: appData).appendingPathComponent("CodexBar")
    #else
    // ~/.codexbar
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codexbar")
    #endif
}
```

#### Task A.5: PTY-Alternative für Windows (ConPTY)

**Files:**
- Create: `Sources/CodexBarCore/Host/PTY/WindowsConPTY.swift`
- Modify: `Sources/CodexBarCore/Host/PTY/TTYCommandRunner.swift`

```swift
#if os(Windows)
import WinSDK

class WindowsConPTYRunner {
    // ConPTY API für Windows Pseudo-Terminal
    // https://devblogs.microsoft.com/commandline/windows-command-line-introducing-the-windows-pseudo-console-conpty/

    func createPseudoConsole(size: COORD) throws -> HPCON {
        var hPC: HPCON = HPCON(bitPattern: 0)!
        let hr = CreatePseudoConsole(size, hInput, hOutput, 0, &hPC)
        guard hr >= 0 else { throw WindowsError(hr) }
        return hPC
    }
}
#endif
```

#### Task A.6: Tests für Windows

**Files:**
- Modify: `Tests/CodexBarTests/`

```swift
#if os(Windows)
func testWindowsPathResolution() {
    let path = PathEnvironment.resolve("cmd.exe")
    XCTAssertNotNil(path)
}
#endif
```

### Build & Distribution

```powershell
# Scripts/build-windows.ps1
swift build -c release
Copy-Item .build\release\codexbar.exe .\dist\
```

---

## 4. Ansatz B: System Tray App

### Beschreibung

Native Windows System Tray Applikation mit ähnlicher UX wie die macOS Menu Bar App.

### Technologie-Optionen

#### Option B.1: .NET / WPF (Empfohlen für native Windows)

**Vorteile:**
- Beste Windows-Integration
- Stabiles Ökosystem
- Native Performance
- Windows Credential Manager Integration

**Nachteile:**
- Keine Swift-Wiederverwendung für UI
- Separate Codebasis für Windows

**Architektur:**
```
┌─────────────────────────────────────────┐
│     CodexBar.Windows (C# / WPF)         │
│  - System Tray (NotifyIcon)             │
│  - WPF Popup/Window                     │
├─────────────────────────────────────────┤
│     CodexBar.Core.Interop               │
│  - P/Invoke zu Swift DLL                │
│  - ODER: C# Reimplementierung           │
├─────────────────────────────────────────┤
│     Shared: HTTP Provider Logic         │
│  (Port zu C# oder Swift DLL)            │
└─────────────────────────────────────────┘
```

#### Option B.2: Electron

**Vorteile:**
- Cross-platform (könnte auch macOS-Version ersetzen)
- Web-Technologien (JS/TS, HTML, CSS)
- Schnelle UI-Entwicklung

**Nachteile:**
- Hoher Speicherverbrauch (~100-200MB)
- Keine native Performance
- Komplette Neuimplementierung

#### Option B.3: Tauri (Rust + Web UI)

**Vorteile:**
- Klein und schnell (~10MB)
- Cross-platform
- Rust-Backend (sicher, performant)

**Nachteile:**
- Rust-Lernkurve
- Keine Swift-Wiederverwendung

#### Option B.4: Swift + WinUI 3 (Experimentell)

**Vorteile:**
- Maximale Swift-Wiederverwendung
- Einheitliche Codebasis

**Nachteile:**
- Swift für Windows noch nicht produktionsreif
- WinUI-Bindings für Swift experimentell
- Wenig Community-Support

### Empfohlene Option: .NET/WPF mit Core-Port

**Begründung:**
- Provider-Logik ist HTTP-basiert → einfach zu portieren
- WPF bietet beste Windows System Tray Integration
- Kann CodexBarCore-Logik als C# Library reimplementieren

### Architektur-Vorschlag

```
CodexBar.Windows/
├── CodexBar.Windows.App/          # WPF System Tray App
│   ├── App.xaml
│   ├── TrayIcon.cs
│   ├── Views/
│   │   ├── ProviderPopup.xaml
│   │   └── SettingsWindow.xaml
│   └── ViewModels/
├── CodexBar.Core/                  # Portierte Core-Logik (C#)
│   ├── Providers/
│   │   ├── IProvider.cs
│   │   ├── ClaudeProvider.cs
│   │   ├── CodexProvider.cs
│   │   └── ...
│   ├── Config/
│   └── UsageTracking/
└── CodexBar.CLI/                   # Windows CLI
```

### Implementierungsplan (B.1: .NET/WPF)

#### Task B.1.1: .NET Solution Setup

```bash
dotnet new sln -n CodexBar.Windows
dotnet new wpf -n CodexBar.Windows.App
dotnet new classlib -n CodexBar.Core
dotnet sln add CodexBar.Windows.App CodexBar.Core
```

#### Task B.1.2: System Tray Implementation

**Files:**
- Create: `CodexBar.Windows.App/TrayIcon.cs`

```csharp
using System.Windows.Forms;
using System.Drawing;

public class TrayIcon : IDisposable
{
    private NotifyIcon _notifyIcon;

    public TrayIcon()
    {
        _notifyIcon = new NotifyIcon
        {
            Icon = LoadIcon(),
            Visible = true,
            Text = "CodexBar"
        };
        _notifyIcon.Click += OnClick;
    }

    private void OnClick(object sender, EventArgs e)
    {
        // Show popup with provider status
    }
}
```

#### Task B.1.3: Provider-Interfaces portieren

**Files:**
- Create: `CodexBar.Core/Providers/IProvider.cs`

```csharp
public interface IProvider
{
    string Name { get; }
    Task<UsageStatus> FetchUsageAsync();
    bool IsConfigured { get; }
}

public record UsageStatus(
    decimal Used,
    decimal Limit,
    TimeSpan? ResetIn
);
```

#### Task B.1.4: HTTP-basierte Provider portieren

Die meisten Provider nutzen HTTP APIs und können 1:1 portiert werden:

```csharp
// Beispiel: Claude Provider
public class ClaudeProvider : IProvider
{
    private readonly HttpClient _client;

    public async Task<UsageStatus> FetchUsageAsync()
    {
        var response = await _client.GetAsync("https://api.anthropic.com/v1/usage");
        // Parse response...
    }
}
```

---

## 5. Ansatz C: Web Dashboard

### Beschreibung

Lokaler Web-Server der ein Browser-basiertes Dashboard bereitstellt.

### Architektur

```
┌─────────────────────────────────────────┐
│           Browser (localhost:8080)       │
│  - React/Vue/Svelte Dashboard           │
│  - Real-time Updates (WebSocket)        │
├─────────────────────────────────────────┤
│           Local HTTP Server              │
│  - Swift (Vapor) oder                   │
│  - Node.js oder                         │
│  - Go                                    │
├─────────────────────────────────────────┤
│           CodexBarCore (portiert)        │
│  - Provider Logic                        │
│  - Config Management                     │
└─────────────────────────────────────────┘
```

### Vorteile
- Maximale Plattform-Unabhängigkeit
- Moderne Web-UI möglich
- Einfache Updates (nur Server neu starten)

### Nachteile
- Kein natives System Tray Icon
- Browser muss geöffnet sein für Anzeige
- Zusätzlicher Dienst im Hintergrund

### Implementierungsplan

#### Task C.1: Web Server mit Swift (Vapor)

```swift
// Sources/CodexBarWeb/main.swift
import Vapor

func routes(_ app: Application) throws {
    app.get("api", "providers") { req -> [ProviderStatus] in
        return await ProviderManager.shared.fetchAll()
    }

    app.webSocket("ws", "updates") { req, ws in
        // Real-time usage updates
    }
}
```

#### Task C.2: Frontend Dashboard

```
codexbar-web/
├── src/
│   ├── App.svelte
│   ├── components/
│   │   ├── ProviderCard.svelte
│   │   ├── UsageMeter.svelte
│   │   └── ResetCountdown.svelte
│   └── stores/
│       └── providers.ts
├── package.json
└── vite.config.js
```

#### Task C.3: Windows Service

```powershell
# Als Windows-Dienst registrieren
New-Service -Name "CodexBar" -BinaryPathName "C:\Program Files\CodexBar\codexbar-server.exe"
```

---

## 6. Code-Änderungen im Detail

### Gemeinsame Änderungen (alle Ansätze)

#### 6.1 Platform Abstraction Layer

**Files:**
- Create: `Sources/CodexBarCore/Platform/Platform.swift`

```swift
public enum Platform {
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
}
```

#### 6.2 Credential Storage Abstraction

**Files:**
- Create: `Sources/CodexBarCore/Platform/CredentialStore.swift`

```swift
public protocol CredentialStore {
    func save(key: String, value: String) throws
    func load(key: String) throws -> String?
    func delete(key: String) throws
}

#if os(macOS)
public class KeychainCredentialStore: CredentialStore { ... }
#elseif os(Windows)
public class WindowsCredentialStore: CredentialStore {
    // Windows Credential Manager via WinSDK
}
#endif
```

#### 6.3 Path Utilities

**Files:**
- Modify: `Sources/CodexBarCore/PathEnvironment.swift`

```swift
public struct PathEnvironment {
    public static var pathSeparator: Character {
        #if os(Windows)
        return ";"
        #else
        return ":"
        #endif
    }

    public static var homeDirectory: URL {
        #if os(Windows)
        if let userProfile = ProcessInfo.processInfo.environment["USERPROFILE"] {
            return URL(fileURLWithPath: userProfile)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var configDirectory: URL {
        #if os(Windows)
        let appData = ProcessInfo.processInfo.environment["APPDATA"] ?? ""
        return URL(fileURLWithPath: appData).appendingPathComponent("CodexBar")
        #else
        return homeDirectory.appendingPathComponent(".codexbar")
        #endif
    }
}
```

#### 6.4 Browser Cookie Paths

**Files:**
- Modify: `Sources/CodexBarCore/BrowserDetection.swift`

```swift
public struct BrowserPaths {
    public static var chromeCookies: URL {
        #if os(Windows)
        let localAppData = ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? ""
        return URL(fileURLWithPath: localAppData)
            .appendingPathComponent("Google/Chrome/User Data/Default/Network/Cookies")
        #elseif os(macOS)
        return homeDirectory
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cookies")
        #else
        return homeDirectory
            .appendingPathComponent(".config/google-chrome/Default/Cookies")
        #endif
    }
}
```

---

## 7. Empfehlung

### Empfohlener Ansatz: Hybrid (A + B)

**Phase 1: CLI-only (2-4 Wochen)**
- Schneller Mehrwert für Windows-Nutzer
- Validiert Cross-Platform-Abstraktion
- Basis für weitere Entwicklung

**Phase 2: System Tray App mit .NET/WPF (2-3 Monate)**
- Native Windows-Erfahrung
- Nutzt portierte Core-Logik
- Parallele Entwicklung möglich

### Begründung

1. **CLI zuerst** ermöglicht frühe Nutzung und testet die Portierung der Core-Logik
2. **WPF für GUI** bietet beste Windows-Integration ohne Electron-Overhead
3. **Geteilte Provider-Logik** reduziert Wartungsaufwand langfristig

### Risiken

| Risiko | Mitigation |
|--------|------------|
| Swift für Windows instabil | Fallback: C# Reimplementierung |
| ConPTY-Komplexität | Alternative: Named Pipes für CLI-Kommunikation |
| Unterschiedliche Cookie-Verschlüsselung | SweetCookieKit erweitern oder Alternativen nutzen |

### Nächste Schritte

1. **Entscheidung:** Welcher Ansatz soll verfolgt werden?
2. **Prototyp:** Kleiner PoC für gewählten Ansatz
3. **Detailplan:** Implementierungsplan mit Task-Granularität erstellen

---

## Anhang: Referenzen

- [Swift für Windows](https://www.swift.org/download/#windows)
- [Windows ConPTY API](https://devblogs.microsoft.com/commandline/windows-command-line-introducing-the-windows-pseudo-console-conpty/)
- [WPF System Tray](https://docs.microsoft.com/en-us/dotnet/api/system.windows.forms.notifyicon)
- [Tauri](https://tauri.app/)
- [Electron](https://www.electronjs.org/)
