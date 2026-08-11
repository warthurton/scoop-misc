#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Manages patched scripts for Scoop buckets, detecting upstream changes and applying patches.

.DESCRIPTION
    This script downloads upstream scripts, compares them against known versions,
    applies patches, and alerts when changes are detected. Designed to be run in CI/CD pipelines.

.PARAMETER App
    The application name (e.g., 'open-in')

.PARAMETER Repo
    GitHub repo in format owner/repo (e.g., 'andy-portmen/native-client')

.PARAMETER Version
    Version tag to check (e.g., '1.1.2')

.PARAMETER CheckOnly
    Only check for changes without applying patches

.EXAMPLE
    .\manage-scripts.ps1 -App open-in -Repo andy-portmen/native-client -Version 1.1.2
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$App,

    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

# Paths
$scriptsDir = "$PSScriptRoot/../scripts/$App"
$hashFile = "$PSScriptRoot/../.github/hashes/$App.txt"
$tempDir = "$env:TEMP/scoop-scripts-$App-$([guid]::NewGuid())"

try {
    # Create scripts directory if it doesn't exist
    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }

    Write-Host "Checking $App v$Version from $Repo..." -ForegroundColor Cyan

    # Download release
    Write-Host "Downloading release..."
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $release = "https://github.com/$Repo/releases/download/v$Version/windows.zip"
    $zipPath = "$tempDir/windows.zip"

    Invoke-WebRequest -Uri $release -OutFile $zipPath -ErrorAction Stop

    # Extract
    Write-Host "Extracting scripts..."
    $extractPath = "$tempDir/extract"
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # Find scripts
    $upstreamInstall = Get-ChildItem $extractPath -Filter "install.bat" -Recurse | Select-Object -First 1
    $upstreamUninstall = Get-ChildItem $extractPath -Filter "uninstall.bat" -Recurse | Select-Object -First 1

    if (-not $upstreamInstall -or -not $upstreamUninstall) {
        throw "Could not find install.bat or uninstall.bat in extracted files"
    }

    # Calculate hashes
    $installHash = (Get-FileHash $upstreamInstall.FullName).Hash
    $uninstallHash = (Get-FileHash $upstreamUninstall.FullName).Hash

    Write-Host "Upstream hashes:"
    Write-Host "  install.bat:   $installHash"
    Write-Host "  uninstall.bat: $uninstallHash"

    # Load known hashes from text file format
    $knownHashes = @{}
    if (Test-Path $hashFile) {
        Get-Content $hashFile | ForEach-Object {
            if ($_ -match '^(.+?)=(.+)$') {
                $knownHashes[$Matches[1]] = $Matches[2]
            }
        }
    }

    # Check for changes
    $changed = $false
    $knownInstallHash = $knownHashes.installBat -or ""
    $knownUninstallHash = $knownHashes.uninstallBat -or ""

    if ($knownInstallHash -and $knownInstallHash -ne $installHash) {
        Write-Host "⚠️  install.bat has changed!" -ForegroundColor Yellow
        Write-Host "  Old: $knownInstallHash"
        Write-Host "  New: $installHash"
        $changed = $true
    }

    if ($knownUninstallHash -and $knownUninstallHash -ne $uninstallHash) {
        Write-Host "⚠️  uninstall.bat has changed!" -ForegroundColor Yellow
        Write-Host "  Old: $knownUninstallHash"
        Write-Host "  New: $uninstallHash"
        $changed = $true
    }

    if ($changed) {
        Write-Host "::warning::Upstream scripts changed. Review and update $scriptsDir" -ForegroundColor Yellow
    }

    if ($CheckOnly) {
        if ($changed) {
            exit 1
        }
        exit 0
    }

    # Apply patches
    Write-Host "Applying patches..."

    # Read and patch install.bat
    $installContent = Get-Content $upstreamInstall.FullName -Raw
    $installContent = $installContent -replace '(?i)^\\s*pause\\s*$', ''

    # Read and patch uninstall.bat
    $uninstallContent = Get-Content $upstreamUninstall.FullName -Raw
    $uninstallContent = $uninstallContent -replace '(?i)^\\s*pause\\s*$', ''
    $uninstallContent = $uninstallContent -replace '(reg delete .+?)\\s*$', '$1 || exit /b 0'

    # Remove duplicate error handling
    $uninstallContent = $uninstallContent -replace '\|\| exit /b 0 \|\| exit /b 0', '|| exit /b 0'

    # Save patched scripts
    Set-Content "$scriptsDir/install.bat" $installContent -Encoding ASCII
    Set-Content "$scriptsDir/uninstall.bat" $uninstallContent -Encoding ASCII

    # Save hashes in text format
    $hashData = @{
        version = $Version
        timestamp = Get-Date -Format "o"
        installBat = $installHash
        uninstallBat = $uninstallHash
    }

    $hashContent = $hashData.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Join-String -Separator "`n"
    Set-Content $hashFile $hashContent

    Write-Host "✓ Scripts patched and saved to $scriptsDir" -ForegroundColor Green
    Write-Host "✓ Hashes updated in $hashFile" -ForegroundColor Green

} finally {
    # Cleanup
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
