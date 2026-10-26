BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot 'excavator-issues.ps1'

    function gh {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [String[]] $Arguments
        )
    }
}

Describe 'Excavator job log downloads' {
    BeforeEach {
        Mock gh {
            $global:LASTEXITCODE = 0
            if ($Arguments[1] -like '*/logs') {
                if ($Arguments -notcontains '--allow-escape-sequences') {
                    $global:LASTEXITCODE = 1
                    return
                }
                $jobLog
            } else {
                '123'
            }
        }
    }

    It 'reports errors from <name> logs' -TestCases @(
        @{ name = 'plain'; jobLog = 'ERROR example checkver expects a version' }
        @{ name = 'colored'; jobLog = "2026-10-26T01:05:00.000Z $([char]27)[31mERROR example checkver expects a version$([char]27)[0m" }
    ) {
        param($name, $jobLog)

        $output = & $scriptPath -RunId '456' -DryRun 6>&1 | Out-String

        $output | Should -Match 'Would open: example: Excavator update failed'
        $output | Should -Match '1 manifest\(s\) with errors\.'
        $output | Should -Not -Match '\x1b'
        Should -Invoke gh -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'api' -and
            $Arguments[1] -like '*/actions/jobs/123/logs' -and
            $Arguments -contains '--allow-escape-sequences'
        }
        Should -Invoke gh -Times 2 -Exactly
    }

    It 'still fails when a job log cannot be downloaded' {
        Mock gh {
            $global:LASTEXITCODE = 1
        } -ParameterFilter { $Arguments[1] -like '*/logs' }

        { & $scriptPath -RunId '456' -DryRun } |
            Should -Throw '*Could not download the log of job 123*'
    }
}
