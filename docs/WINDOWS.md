# CodexBar CLI for Windows

This document describes how to build and use CodexBar CLI on Windows.

## Prerequisites

### Swift for Windows

1. Download Swift 6.0+ from [swift.org/download](https://www.swift.org/download/)
2. Run the installer and follow the instructions
3. Verify installation:
   ```powershell
   swift --version
   ```

### Visual Studio Build Tools

Swift on Windows requires Visual Studio Build Tools:

1. Download [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022)
2. Install with "Desktop development with C++" workload
3. Include Windows SDK

## Building

### Using PowerShell Script (Recommended)

```powershell
# Debug build
.\scripts\build-windows.ps1

# Release build
.\scripts\build-windows.ps1 -Configuration release

# Clean rebuild
.\scripts\build-windows.ps1 -Clean
```

### Using Batch Script

```cmd
scripts\build-windows.bat
```

### Manual Build

```powershell
$env:CODEXBAR_WINDOWS_BUILD = "1"
swift build --product CodexBarCLI
```

The executable will be at:
```
.build\x86_64-unknown-windows-msvc\debug\CodexBarCLI.exe
```

## Usage

```powershell
# Show help
.\CodexBarCLI.exe --help

# Show usage for all providers
.\CodexBarCLI.exe usage

# JSON output
.\CodexBarCLI.exe usage --json
```

## Configuration

Configuration is stored at:
```
%APPDATA%\CodexBar\config.json
```

Cache is stored at:
```
%LOCALAPPDATA%\CodexBar\Cache\
```

## Limitations on Windows

### No PTY Support

Windows does not support Unix pseudo-terminals (PTY). The following features are **not available** on Windows:

- **TTY-based CLI interaction**: `TTYCommandRunner` throws `notSupportedOnWindows`
- **Claude CLI session capture**: `ClaudeCLISession` throws `notSupportedOnWindows`

### Browser Cookie Extraction (Partial)

Windows cookie extraction infrastructure is in place but requires SQLite support:

- **DPAPI decryption**: Implemented using Windows `CryptUnprotectData`
- **AES-256-GCM decryption**: Implemented using Windows BCrypt API
- **Cookie database reading**: Requires SQLite linking (planned for future release)

Currently, automatic cookie extraction is not functional. Use manual cookie input instead.

### What Works

- HTTP-based API fetching (Claude API, Codex API, etc.)
- OAuth token-based authentication
- API key authentication
- Manual cookie input (paste sessionKey from browser dev tools)
- Configuration management
- JSON output

### Recommended Workflow

On Windows, use one of these authentication methods:

#### Option 1: Manual Cookie Input (for Claude)

1. Open https://claude.ai in your browser
2. Open Developer Tools (F12) → Application → Cookies
3. Copy the `sessionKey` value
4. Pass it to the CLI:
   ```powershell
   .\CodexBarCLI.exe usage --provider claude --cookie "sessionKey=sk-ant-..."
   ```

#### Option 2: API Keys

Set environment variables or use `config.json`:

```json
{
  "tokenAccounts": [
    {
      "label": "my-claude-key",
      "provider": "claude",
      "apiKey": "sk-ant-..."
    }
  ]
}
```

#### Option 3: OAuth Tokens

Configure OAuth tokens in `%APPDATA%\CodexBar\config.json`

## Running Tests

```powershell
$env:CODEXBAR_WINDOWS_BUILD = "1"
swift test --filter CodexBarWindowsTests
```

## Troubleshooting

### "Swift not found"

Ensure Swift is in your PATH:
```powershell
$env:Path += ";C:\Users\<user>\AppData\Local\Programs\Swift\Toolchains\<version>\usr\bin"
```

### "Cannot find Visual Studio"

Install Visual Studio Build Tools with the "Desktop development with C++" workload.

### Build Errors

1. Clean the build:
   ```powershell
   Remove-Item -Recurse -Force .build
   ```

2. Ensure `CODEXBAR_WINDOWS_BUILD=1` is set

3. Check Swift version is 6.0+

## Architecture

### Platform Abstraction

The codebase uses conditional compilation for platform-specific code:

- `#if os(Windows)` - Windows-specific code
- `#if os(macOS)` - macOS-specific code
- `#if canImport(SweetCookieKit)` - Browser cookie support (macOS only)

Key files:
- `Sources/CodexBarCore/Platform/Platform.swift` - Platform enum
- `Sources/CodexBarCore/Platform/PlatformPaths.swift` - Cross-platform paths
- `Sources/CodexBarCore/Platform/WindowsCrypto.swift` - DPAPI and AES-GCM decryption
- `Sources/CodexBarCore/Platform/WindowsBrowserCookie.swift` - Browser cookie extraction
- `Sources/CodexBarCore/BrowserCookieImportOrder.swift` - Browser enum with Windows cases

### Windows-Specific Implementations

- `WindowsDPAPI` - DPAPI decryption using `CryptUnprotectData`
- `WindowsAESGCM` - AES-256-GCM decryption using BCrypt API
- `WindowsBrowserCookieClient` - Chromium cookie extraction (partial)
- `BrowserDetection` (Windows) - Detects installed Chromium browsers

### Windows Stubs

These components have Windows stubs that throw `notSupportedOnWindows`:

- `TTYCommandRunner` - PTY-based CLI runner
- `ClaudeCLISession` - Claude CLI session manager

### Environment Variables

- `CODEXBAR_WINDOWS_BUILD=1` - Exclude macOS-only dependencies from Package.swift
