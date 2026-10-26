<#
.SYNOPSIS
    Open, or close, GitHub issues for errors reported by an Excavator run.
.DESCRIPTION
    Excavator logs checkver and autoupdate failures but still finishes successfully.
    This script reads the log of a run, opens one issue per failing manifest and
    closes issues for manifests that no longer fail.
    Requires the GitHub CLI with GH_TOKEN and GH_REPO set, unless -LogPath and -DryRun are used.
.PARAMETER RunId
    Id of the Excavator workflow run to read the log from.
.PARAMETER LogPath
    Read the log from a file instead of downloading it. Useful for testing.
.PARAMETER RunFailed
    The run itself failed, so open an issue for it and do not close any.
.PARAMETER DryRun
    Print what would be done without touching any issue.
#>
param(
    [String] $RunId,
    [String] $LogPath,
    [Switch] $RunFailed,
    [Switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$label = 'excavator'
$general = 'Excavator'

function Get-ExcavatorErrors($lines) {
    $errors = [ordered]@{}
    $add = { param($app, $msg) if (!$errors.Contains($app)) { $errors[$app] = @() }; $errors[$app] += $msg }
    $prev = ''

    foreach ($raw in $lines) {
        # Strip the BOM, the timestamp GitHub prefixes to every line and any colour codes
        $line = ($raw -replace '^﻿', '' -replace '^\d{4}-\d\d-\d\dT[\d:.]+Z ', '' -replace '\x1b\[[0-9;]*m', '').Trim()

        if ($line -match "^(?<app>[^\s:]+): (?<msg>(couldn't |'replace' requires ).*)$") {
            & $add $Matches.app $Matches.msg
        } elseif ($line -match '^ERROR Could not update (?<app>[^,]+), ') {
            $app = $Matches.app
            $msg = $line -replace '^ERROR ', ''
            if ($prev -match '^URL \S+ is not valid$') { $msg = "$msg`n$prev" }
            & $add $app $msg
        } elseif ($line -match '^ERROR (?<msg>(?<app>\S+) checkver expects .*)$') {
            & $add $Matches.app $Matches.msg
        } elseif ($line -match '^ERROR (?<msg>.*)$') {
            & $add $general $Matches.msg
        } elseif ($line -match '^URL \S+ is not valid$' -and $prev -match '^(?<app>[^\s:]+): (?<msg>.+)$' -and $prev -notmatch '\(scoop version is ') {
            # checkver could not download the page: the reason is on the previous line
            & $add $Matches.app "$($Matches.msg)`n$line"
        }

        if ($line) { $prev = $line }
    }

    return $errors
}

function Get-IssueTitle($app) {
    if ($app -eq $general) { return 'Excavator: run reported errors' }
    return "${app}: Excavator update failed"
}

if ($LogPath) {
    $log = Get-Content $LogPath
} else {
    # Skipped jobs have no log to download
    $jobs = gh api "repos/$env:GH_REPO/actions/runs/$RunId/jobs" --paginate --jq '.jobs[] | select(.conclusion != "skipped") | .id'
    if ($LASTEXITCODE -ne 0) { throw "Could not list the jobs of run $RunId" }
    $logIncomplete = $false
    $log = $jobs | ForEach-Object {
        $job = $_
        foreach ($attempt in 1..3) {
            # The logs contain colour codes, which gh refuses to print unless told otherwise
            $jobLog = gh api "repos/$env:GH_REPO/actions/jobs/$job/logs" --allow-escape-sequences
            if ($LASTEXITCODE -eq 0) { $jobLog; return }
            Start-Sleep -Seconds (5 * $attempt)
        }
        Write-Warning "Could not download the log of job $job"
        $script:logIncomplete = $true
    }
}

$errors = Get-ExcavatorErrors $log
if ($RunFailed) {
    $errors[$general] = @('The Excavator workflow run failed.') + @($errors[$general] | Where-Object { $_ })
}

$runUrl = if ($RunId) { "$env:GITHUB_SERVER_URL/$env:GH_REPO/actions/runs/$RunId" }
$fence = '```'
$open = @()
if (!$DryRun) {
    gh label create $label --description 'Reported by the Excavator workflow' --color D93F0B --force | Out-Null
    $open = @(gh issue list --label $label --state open --limit 200 --json 'number,title' | ConvertFrom-Json)
}

foreach ($app in $errors.Keys) {
    $title = Get-IssueTitle $app
    $body = @(
        $(if ($app -eq $general) { 'Excavator reported errors.' } else { "Excavator reported errors for ``$app``." }), ''
        $fence, ($errors[$app] -join "`n"), $fence, ''
        $(if ($app -ne $general) { "Manifest: ``bucket/$app.json``" })
        $(if ($runUrl) { "Run: $runUrl" }), ''
        'This issue is closed automatically once Excavator stops reporting errors for it.'
    ) -join "`n"

    if ($open.title -contains $title) {
        Write-Host "Already open: $title"
    } elseif ($DryRun) {
        Write-Host "Would open: $title`n$body`n"
    } else {
        gh issue create --title $title --body $body --label $label
    }
}

# A failed run may have stopped before reaching every manifest, and a missing log hides errors, so close nothing
if (!$RunFailed -and !$logIncomplete) {
    foreach ($issue in $open) {
        if (@($errors.Keys | ForEach-Object { Get-IssueTitle $_ }) -notcontains $issue.title) {
            gh issue close $issue.number --comment "Excavator no longer reports errors for this.$(if ($runUrl) { " Run: $runUrl" })"
        }
    }
}

Write-Host "$($errors.Count) manifest(s) with errors."
