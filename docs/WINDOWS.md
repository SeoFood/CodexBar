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
- **Browser cookie extraction**: `SweetCookieKit` is macOS-only

### What Works

- HTTP-based API fetching (Claude API, Codex API, etc.)
- OAuth token-based authentication
- API key authentication
- Configuration management
- JSON output

### Recommended Workflow

On Windows, use API-based authentication methods:

1. **API Keys**: Set environment variables or use `config.json`
2. **OAuth Tokens**: Configure tokens in `%APPDATA%\CodexBar\config.json`

Example config:
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

### Windows Stubs

These components have Windows stubs that throw `notSupportedOnWindows`:

- `TTYCommandRunner` - PTY-based CLI runner
- `ClaudeCLISession` - Claude CLI session manager

### Environment Variables

- `CODEXBAR_WINDOWS_BUILD=1` - Exclude macOS-only dependencies from Package.swift
