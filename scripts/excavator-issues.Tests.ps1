BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot 'excavator-issues.ps1'

    function gh {
        param([Parameter(ValueFromRemainingArguments = $true)][String[]] $Arguments)
    }
}

Describe 'Excavator log downloads' {
    BeforeEach {
        Mock gh {
            $global:LASTEXITCODE = 0
            '123'
        } -ParameterFilter { $Arguments[1] -like '*/jobs' }
    }

    It 'downloads and parses colored logs' {
        Mock gh {
            if ($Arguments -notcontains '--allow-escape-sequences') {
                $global:LASTEXITCODE = 1
                return
            }
            $global:LASTEXITCODE = 0
            "2026-10-26T01:00:00.000Z $([char]27)[31mexample: couldn't find version$([char]27)[0m"
        } -ParameterFilter { $Arguments[1] -like '*/logs' }

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
        Mock gh {
            $global:LASTEXITCODE = 0
            "example: couldn't find version"
        } -ParameterFilter { $Arguments[1] -like '*/logs' }

        $output = & $scriptPath -RunId '456' -DryRun 6>&1 | Out-String

        $output | Should -Match 'Would open: example: Excavator update failed'
        $output | Should -Match '1 manifest\(s\) with errors'
    }

    It 'still stops when downloading a log fails' {
        Mock gh {
            $global:LASTEXITCODE = 1
        } -ParameterFilter { $Arguments[1] -like '*/logs' }

        { & $scriptPath -RunId '456' -DryRun } | Should -Throw 'Could not download the log of job 123'
    }
}
