<#
.SYNOPSIS
    Build CodexBar CLI for Windows

.DESCRIPTION
    Builds the CodexBar CLI executable for Windows using Swift Package Manager.
    Requires Swift 6.0+ and Visual Studio Build Tools to be installed.

.PARAMETER Configuration
    Build configuration: debug (default) or release

.PARAMETER Clean
    Clean build artifacts before building

.EXAMPLE
    .\build-windows.ps1
    Build in debug mode

.EXAMPLE
    .\build-windows.ps1 -Configuration release
    Build in release mode

.EXAMPLE
    .\build-windows.ps1 -Clean
    Clean and rebuild
#>

param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "debug",

    [switch]$Clean
)

$ErrorActionPreference = "Stop"

# Check Swift installation
try {
    $swiftVersion = swift --version 2>&1
    Write-Host "Found Swift: $($swiftVersion[0])" -ForegroundColor Green
} catch {
    Write-Host "Error: Swift not found. Please install Swift for Windows from https://www.swift.org/download/" -ForegroundColor Red
    exit 1
}

# Project root
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $ProjectRoot

try {
    # Set Windows build flag
    $env:CODEXBAR_WINDOWS_BUILD = "1"

    # Clean if requested
    if ($Clean) {
        Write-Host "Cleaning build artifacts..." -ForegroundColor Yellow
        if (Test-Path ".build") {
            Remove-Item -Recurse -Force ".build"
        }
    }

    # Build
    Write-Host "Building CodexBarCLI ($Configuration)..." -ForegroundColor Cyan

    $buildArgs = @("build", "--product", "CodexBarCLI")
    if ($Configuration -eq "release") {
        $buildArgs += "-c"
        $buildArgs += "release"
    }

    & swift @buildArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    # Find output
    $arch = "x86_64-unknown-windows-msvc"
    $outputDir = ".build\$arch\$Configuration"
    $exePath = "$outputDir\CodexBarCLI.exe"

    if (Test-Path $exePath) {
        $fileInfo = Get-Item $exePath
        Write-Host ""
        Write-Host "Build successful!" -ForegroundColor Green
        Write-Host "Output: $exePath" -ForegroundColor Cyan
        Write-Host "Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Cyan

        # Test it
        Write-Host ""
        Write-Host "Testing executable..." -ForegroundColor Yellow
        & $exePath --version
    } else {
        Write-Host "Warning: Expected output not found at $exePath" -ForegroundColor Yellow
        Write-Host "Searching for executable..." -ForegroundColor Yellow
        Get-ChildItem -Path ".build" -Filter "CodexBarCLI.exe" -Recurse | ForEach-Object {
            Write-Host "Found: $($_.FullName)" -ForegroundColor Cyan
        }
    }

} finally {
    Pop-Location
    Remove-Item Env:\CODEXBAR_WINDOWS_BUILD -ErrorAction SilentlyContinue
}
