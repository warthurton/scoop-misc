#Requires -Version 5.1

<#
.SYNOPSIS
    Generate APPLICATIONS.md file listing all packages in the bucket
.DESCRIPTION
    This script scans all JSON manifest files in the bucket directory and generates
    a markdown file (APPLICATIONS.md) with a table listing all applications.
    The table includes: package name, description, version, last updated date,
    download URL, and homepage.

    For manifests missing required fields, it tracks them for issue reporting.
.PARAMETER BucketPath
    Path to the bucket directory. Defaults to ../bucket relative to script location.
.PARAMETER OutputFile
    Path to output markdown file. Defaults to ../APPLICATIONS.md relative to script location.
.PARAMETER SkipIssueTracking
    If set, skips tracking incomplete manifests for issue creation.
.EXAMPLE
    .\generate-applications-list.ps1
.EXAMPLE
    .\generate-applications-list.ps1 -BucketPath "C:\mybucket" -OutputFile "C:\APPS.md"
#>

param(
    [string]$BucketPath = (Join-Path $PSScriptRoot '..' 'bucket'),
    [string]$OutputFile = (Join-Path $PSScriptRoot '..' 'APPLICATIONS.md'),
    [switch]$SkipIssueTracking
)

# Function to parse a manifest file and extract relevant information
function Get-ManifestInfo {
    param(
        [string]$ManifestPath
    )

    try {
        $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        $fileName = Split-Path $ManifestPath -Leaf
        $packageName = $fileName -replace '\.json$', ''

        # Skip template files
        if ($packageName -match 'template') {
            return $null
        }

        # Extract download URL (handle architecture-specific URLs)
        $downloadUrl = ''
        if ($manifest.url) {
            $downloadUrl = $manifest.url
        } elseif ($manifest.architecture) {
            # Try to get 64bit URL first, then 32bit
            if ($manifest.architecture.'64bit'.url) {
                $downloadUrl = $manifest.architecture.'64bit'.url
            } elseif ($manifest.architecture.'32bit'.url) {
                $downloadUrl = $manifest.architecture.'32bit'.url
            } elseif ($manifest.architecture.arm64.url) {
                $downloadUrl = $manifest.architecture.arm64.url
            }
        }

        # Track missing fields
        $missingFields = @()
        if (-not $manifest.description -or $manifest.description -eq '') {
            $missingFields += 'description'
        }
        if (-not $manifest.homepage -or $manifest.homepage -eq '') {
            $missingFields += 'homepage'
        }
        if (-not $manifest.version -or $manifest.version -eq '' -or $manifest.version -eq '.') {
            $missingFields += 'version'
        }
        if (-not $downloadUrl) {
            $missingFields += 'url'
        }

        # Get last commit date
        $lastCommitDate = Get-LastCommitDate -FilePath $ManifestPath

        # Get last application version date only if version has changed
        $lastAppDate = 'N/A'
        if ($manifest.homepage) {
            # Check if version has changed in the last commit
            $versionChanged = Test-VersionChanged -FilePath $ManifestPath -CurrentVersion $manifest.version
            if ($versionChanged) {
                $lastAppDate = ''
            } else {
                # Version hasn't changed, skip expensive HTTP check
                $lastAppDate = ''
            }
        }

        return [PSCustomObject]@{
            PackageName         = $packageName
            Description         = if ($manifest.description) { $manifest.description } else { 'N/A' }
            Version             = if ($manifest.version) { $manifest.version } else { 'N/A' }
            Homepage            = if ($manifest.homepage) { $manifest.homepage } else { '' }
            DownloadUrl         = $downloadUrl
            LastCommitDate      = $lastCommitDate
            LastApplicationDate = $lastAppDate
            MissingFields       = $missingFields
        }
    } catch {
        Write-Warning "Error parsing manifest $ManifestPath : $_"
        return $null
    }
}

# Function to get the last commit date for a file
function Get-LastCommitDate {
    param(
        [string]$FilePath
    )
    try {
        $commitDate = git log -1 --format="%ci" -- $FilePath
        return ($commitDate -split ' ')[0] # Extract only the date part
    } catch {
        Write-Warning "Failed to get last commit date for ${FilePath}: $($_)"
        return 'N/A'
    }
}

# Function to check if the version has changed in recent commits
function Test-VersionChanged {
    param(
        [string]$FilePath,
        [string]$CurrentVersion
    )
    try {
        # Get the version from the previous commit
        $previousContent = git show HEAD~1:$FilePath 2>$null
        if (-not $previousContent) {
            # File is new or no previous commit, consider version as changed
            return $true
        }

        $previousManifest = $previousContent | ConvertFrom-Json
        $previousVersion = $previousManifest.version

        # Compare versions
        return ($CurrentVersion -ne $previousVersion)
    } catch {
        # If we can't get previous version, assume it changed to be safe
        return $true
    }
}

# Main script logic
Write-Host "Scanning manifests in: $BucketPath"

# Get all JSON files in bucket directory
$manifestFiles = Get-ChildItem -Path $BucketPath -Filter '*.json' |
    Where-Object { $_.Name -notmatch 'template' }

if ($manifestFiles.Count -eq 0) {
    Write-Warning "No manifest files found in $BucketPath"
    exit 1
}

Write-Host "Found $($manifestFiles.Count) manifest files"

# Parse all manifests
$apps = @()
$incompleteApps = @()

foreach ($file in $manifestFiles) {
    $info = Get-ManifestInfo -ManifestPath $file.FullName
    if ($info) {
        $apps += $info
        if ($info.MissingFields.Count -gt 0) {
            $incompleteApps += $info
        }
    }
}

# Sort alphabetically by package name
$apps = $apps | Sort-Object PackageName

Write-Host "Parsed $($apps.Count) applications ($($incompleteApps.Count) with missing fields)"

# Generate markdown content
$markdown = @()
$markdown += "# Applications in this Bucket"
$markdown += ""
$markdown += "This bucket contains **$($apps.Count)** application(s)."
$markdown += ""
$markdown += "Last updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
$markdown += ""
$markdown += "## Application List"
$markdown += ""
$markdown += "| Package Name | Description | Version | Last Commit Date | Download | Homepage |"
$markdown += "|--------------|-------------|---------|------------------|----------|----------|"

foreach ($app in $apps) {
    $description = $app.Description -replace '\|', '\|' # Escape pipes
    $downloadLink = if ($app.DownloadUrl) { "[Download]($($app.DownloadUrl))" } else { "N/A" }
    $homepageLink = if ($app.Homepage) { "[Link]($($app.Homepage))" } else { "N/A" }

    $markdown += "| ``$($app.PackageName)`` | $description | $($app.Version) | $($app.LastCommitDate) | $downloadLink | $homepageLink |"
}

# Add section about incomplete manifests if any exist
if ($incompleteApps.Count -gt 0 -and -not $SkipIssueTracking) {
    $markdown += ""
    $markdown += "## Incomplete Manifests"
    $markdown += ""
    $markdown += "The following manifests are missing some fields and may need to be updated:"
    $markdown += ""
    $markdown += "| Package Name | Missing Fields |"
    $markdown += "|--------------|----------------|"

    foreach ($app in $incompleteApps) {
        $missingFieldsList = $app.MissingFields -join ', '
        $markdown += "| ``$($app.PackageName)`` | $missingFieldsList |"
    }
}

# Write to file
$markdownContent = $markdown -join "`n"
Set-Content -Path $OutputFile -Value $markdownContent -Encoding UTF8

Write-Host "Generated $OutputFile"
Write-Host "Total applications: $($apps.Count)"

if ($incompleteApps.Count -gt 0) {
    Write-Host "Applications with missing fields: $($incompleteApps.Count)"

    # Output JSON for GitHub Actions to use for issue creation
    $issueDataFile = Join-Path $PSScriptRoot '..' 'incomplete-manifests.json'
    $issueData = @{
        Count = $incompleteApps.Count
        Apps  = $incompleteApps | ForEach-Object {
            @{
                PackageName   = $_.PackageName
                MissingFields = $_.MissingFields
            }
        }
    }
    $issueData | ConvertTo-Json -Depth 3 | Set-Content -Path $issueDataFile -Encoding UTF8
    Write-Host "Incomplete manifest data saved to: $issueDataFile"
}

exit 0
