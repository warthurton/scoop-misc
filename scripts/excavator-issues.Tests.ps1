BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot 'excavator-issues.ps1'

    # Stand-in for the GitHub CLI, so the tests never touch the network
    function gh {
        param([Parameter(ValueFromRemainingArguments = $true)][String[]] $Arguments)
    }
}

Describe 'excavator-issues' {
    AfterAll {
        Remove-Variable ExcTest -Scope Global -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock Start-Sleep {}
        Mock Write-Warning {}
        # Mocks run in their own scope, so the state they share with the tests has to be global
        $global:ExcTest = @{}
        $global:ExcTest.logAttempts = 0
        $global:ExcTest.logOutput = { "example: couldn't find version" }
        $global:ExcTest.logExit = { param($attempt) 0 }
        $global:ExcTest.openIssues = '[]'

        Mock gh {
            $global:LASTEXITCODE = 0
            if ($Arguments[1] -like '*/jobs') { return '123' }
            if ($Arguments[1] -like '*/logs') {
                $global:ExcTest.logAttempts++
                $global:LASTEXITCODE = & $global:ExcTest.logExit $global:ExcTest.logAttempts
                if ($global:LASTEXITCODE -eq 0) { & $global:ExcTest.logOutput }
                return
            }
            if ($Arguments[0] -eq 'issue' -and $Arguments[1] -eq 'list') { return $global:ExcTest.openIssues }
        }
    }

    Context 'downloading logs' {
        It 'passes --allow-escape-sequences and parses coloured logs' {
            $global:ExcTest.logOutput = { "2026-10-26T01:00:00.000Z $([char]27)[31mexample: couldn't find version$([char]27)[0m" }
            $global:ExcTest.logExit = { param($attempt) if ($Arguments -contains '--allow-escape-sequences') { 0 } else { 1 } }

            $output = & $scriptPath -RunId '456' -DryRun 6>&1 | Out-String

            $output | Should -Match 'Would open: example: Excavator update failed'
            $output | Should -Match "couldn't find version"
            $output | Should -Not -Match '\x1b'
            $output | Should -Match '1 manifest\(s\) with errors'
            Should -Invoke gh -Times 1 -Exactly -ParameterFilter {
                $Arguments[1] -like '*/logs' -and $Arguments -contains '--allow-escape-sequences'
            }
        }

        It 'still parses plain logs' {
            $output = & $scriptPath -RunId '456' -DryRun 6>&1 | Out-String

            $output | Should -Match 'Would open: example: Excavator update failed'
            $output | Should -Match '1 manifest\(s\) with errors'
        }

        It 'skips jobs that were skipped, as they have no log' {
            & $scriptPath -RunId '456' -DryRun 6>&1 | Out-Null

            Should -Invoke gh -Times 1 -Exactly -ParameterFilter {
                $Arguments[1] -like '*/jobs' -and ($Arguments -join ' ') -match 'skipped'
            }
        }

        It 'retries a failed download' {
            $global:ExcTest.logExit = { param($attempt) if ($attempt -lt 3) { 1 } else { 0 } }

            $output = & $scriptPath -RunId '456' -DryRun 6>&1 | Out-String

            $global:ExcTest.logAttempts | Should -Be 3
            $output | Should -Match '1 manifest\(s\) with errors'
            Should -Invoke Write-Warning -Times 0 -Exactly
        }

        It 'warns and carries on when a log cannot be downloaded' {
            $global:ExcTest.logExit = { param($attempt) 1 }

            { & $scriptPath -RunId '456' -DryRun 6>&1 | Out-Null } | Should -Not -Throw

            $global:ExcTest.logAttempts | Should -Be 3
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*job 123*' }
        }
    }

    Context 'closing issues' {
        BeforeEach {
            $global:ExcTest.openIssues = '[{"number":7,"title":"old: Excavator update failed"}]'
            $global:ExcTest.logOutput = { 'all good' }
        }

        It 'closes issues that are no longer reported' {
            & $scriptPath -RunId '456' 6>&1 | Out-Null

            Should -Invoke gh -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'issue' -and $Arguments[1] -eq 'close' -and $Arguments[2] -eq '7' }
        }

        It 'closes nothing when a log is missing' {
            $global:ExcTest.logExit = { param($attempt) 1 }

            & $scriptPath -RunId '456' 6>&1 | Out-Null

            Should -Invoke gh -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'issue' -and $Arguments[1] -eq 'close' }
        }

        It 'closes nothing when the run failed' {
            & $scriptPath -RunId '456' -RunFailed 6>&1 | Out-Null

            Should -Invoke gh -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'issue' -and $Arguments[1] -eq 'close' }
            Should -Invoke gh -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'issue' -and $Arguments[1] -eq 'create' }
        }
    }
}
