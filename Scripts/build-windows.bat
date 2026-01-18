@echo off
REM Build CodexBar CLI for Windows
REM Requires Swift 6.0+ and Visual Studio Build Tools

setlocal

REM Check Swift
where swift >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Error: Swift not found. Please install Swift for Windows.
    echo Download from: https://www.swift.org/download/
    exit /b 1
)

REM Set Windows build flag
set CODEXBAR_WINDOWS_BUILD=1

REM Navigate to project root
cd /d "%~dp0.."

REM Build
echo Building CodexBarCLI...
swift build --product CodexBarCLI %*

if %ERRORLEVEL% neq 0 (
    echo Build failed!
    exit /b %ERRORLEVEL%
)

echo.
echo Build successful!
echo Output: .build\x86_64-unknown-windows-msvc\debug\CodexBarCLI.exe

endlocal
