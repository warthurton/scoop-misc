<#
.SYNOPSIS
    Replace Windows Task Manager with Task Manager TMOG, or undo the replacement.
.DESCRIPTION
    TMOG only offers its "Replace Windows Task Manager" option from an all-users
    install in Program Files, so it is unavailable for a Scoop install. This script
    writes the same registry entry TMOG writes itself: a Debugger value under the
    Image File Execution Options key for taskmgr.exe, plus the two TMOG.* values it
    uses to recognise the entry as its own.

    Like TMOG, it leaves the entry alone when another debugger is configured for
    taskmgr.exe or the existing entry is not owned by TMOG.

    Requires administrator rights; the script elevates itself when needed.
.PARAMETER Disable
    Remove the replacement instead of setting it.
.PARAMETER Path
    Path to 'Task Manager.exe'. Defaults to the one next to this script.
.EXAMPLE
    PS> & "$(scoop prefix tmog)\replace-taskmgr.ps1"
.EXAMPLE
    PS> & "$(scoop prefix tmog)\replace-taskmgr.ps1" -Disable
#>
param(
    [switch] $Disable,
    [string] $Path = (Join-Path $PSScriptRoot 'Task Manager.exe')
)

$ErrorActionPreference = 'Stop'

$key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\taskmgr.exe'
$owner = '{A6C8E313-D89B-4913-BD80-249F5A7575C8}'

if (!$Disable -and !(Test-Path -LiteralPath $Path -PathType Leaf)) {
    Write-Error "'$Path' not found."
    exit 1
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal] $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Path', "`"$Path`"")
    if ($Disable) { $arguments += '-Disable' }
    $process = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    switch ($process.ExitCode) {
        0 { Write-Host "Windows Task Manager replacement $(if ($Disable) { 'removed' } else { 'set' })." }
        3 { Write-Warning 'Another Image File Execution Options debugger is configured for taskmgr.exe, or the existing entry is not owned by Task Manager TMOG. It was left unchanged.' }
        default { Write-Warning "Elevated run failed with exit code $($process.ExitCode)." }
    }
    exit $process.ExitCode
}

$debugger = $null
$owned = $false
if (Test-Path $key) {
    $entry = Get-Item $key
    $debugger = $entry.GetValue('Debugger')
    $owned = $entry.GetValue('TMOG.Owner') -eq $owner -and $debugger -eq $entry.GetValue('TMOG.Debugger')
}

# Leave an entry that belongs to something else untouched
if ($debugger -and !$owned) { exit 3 }

if ($Disable) {
    if ($owned) {
        Remove-ItemProperty $key -Name 'Debugger', 'TMOG.Debugger', 'TMOG.Owner'
        $entry = Get-Item $key
        if ($entry.ValueCount -eq 0 -and $entry.SubKeyCount -eq 0) { Remove-Item $key }
    }
    exit 0
}

$command = "`"$Path`""
if (!(Test-Path $key)) { New-Item $key | Out-Null }
Set-ItemProperty $key -Name 'TMOG.Owner' -Value $owner
Set-ItemProperty $key -Name 'TMOG.Debugger' -Value $command
Set-ItemProperty $key -Name 'Debugger' -Value $command
exit 0
