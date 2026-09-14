BeforeAll {
    $script:ValidationSource = Join-Path $PSScriptRoot '..\build\Invoke-Validation.ps1'

    function Invoke-ValidationFixture {
        param([string]$Tag = 'v1.0.0')
        $StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $StartInfo.FileName = Join-Path $PSHOME 'powershell.exe'
        $StartInfo.Arguments = '-NoProfile -NonInteractive -File "' + (Join-Path $script:FixtureRoot 'build\Invoke-Validation.ps1') + '" -Tag "' + $Tag + '"'
        $StartInfo.UseShellExecute = $false
        $StartInfo.RedirectStandardOutput = $true
        $StartInfo.RedirectStandardError = $true
        $Process = [Diagnostics.Process]::Start($StartInfo)
        try {
            $OutputTask = $Process.StandardOutput.ReadToEndAsync()
            $ErrorTask = $Process.StandardError.ReadToEndAsync()
            if (-not $Process.WaitForExit(60000)) {
                $Process.Kill()
                throw 'Validation fixture exceeded its 60-second timeout.'
            }
            return [pscustomobject]@{
                ExitCode = $Process.ExitCode
                Output = $OutputTask.Result + $ErrorTask.Result
            }
        }
        finally {
            $Process.Dispose()
        }
    }
}

Describe 'Validation process exit gates' {
    BeforeEach {
        $script:FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        foreach ($FixtureDirectory in @('Scripts', 'Tests', 'build')) {
            [void](New-Item -Path (Join-Path $script:FixtureRoot $FixtureDirectory) -ItemType Directory -Force)
        }
        Copy-Item -LiteralPath $script:ValidationSource -Destination (Join-Path $script:FixtureRoot 'build\Invoke-Validation.ps1')
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'VERSION') -Value '1.0.0'
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Scripts\Add-ComputerToADGroup.ps1') -Value '$script:Version = ''1.0.0'''
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Tests\Fixture.Tests.ps1') -Value 'Describe ''Fixture'' { It ''passes'' { $true | Should -BeTrue } }'
    }

    It 'exits zero only after parsing, analysis, tests and matching tag succeed' {
        $Result = Invoke-ValidationFixture
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Result.Output | Should -Match 'PSScriptAnalyzer: Scripts, Tests, and build passed'
    }

    It 'fails the process for a parser error' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Scripts\Invalid.ps1') -Value 'function {'
        $Result = Invoke-ValidationFixture
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Parser errors'
    }

    It 'fails for an unreviewed analyzer warning under <Directory>' -ForEach @(
        @{ Directory = 'Scripts' }, @{ Directory = 'Tests' }, @{ Directory = 'build' }
    ) {
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot "$Directory\Warning.ps1") -Value 'function Get-Sample { $UnusedValue = 1 }'
        $Result = Invoke-ValidationFixture
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'PSScriptAnalyzer warnings or errors'
    }

    It 'fails for a Pester assertion failure' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Tests\Fixture.Tests.ps1') -Value 'Describe ''Fixture'' { It ''fails'' { $false | Should -BeTrue } }'
        $Result = Invoke-ValidationFixture
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Pester did not pass'
    }

    It 'fails for a Pester discovery failure' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Tests\Fixture.Tests.ps1') -Value 'throw ''Deliberate discovery failure'''
        $Result = Invoke-ValidationFixture
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Pester did not pass'
    }

    It 'fails for an empty Pester suite' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Tests\Fixture.Tests.ps1') -Value ''
        $Result = Invoke-ValidationFixture
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Pester did not pass'
    }

    It 'fails for a skipped Pester test' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Tests\Fixture.Tests.ps1') -Value 'Describe ''Fixture'' { It ''skips'' -Skip { $true | Should -BeTrue } }'
        $Result = Invoke-ValidationFixture
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Pester did not pass'
    }

    It 'rejects a tag that disagrees with the version' {
        $Result = Invoke-ValidationFixture -Tag 'v9.9.9'
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Tag, VERSION, and the production script version'
    }

    It 'rejects mismatched script and manifest versions' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'VERSION') -Value '9.9.9'
        $Result = Invoke-ValidationFixture
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'VERSION and the production script version'
    }

    It 'rejects a non-numeric version string' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'VERSION') -Value 'not-semver'
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Scripts\Add-ComputerToADGroup.ps1') -Value '$script:Version = ''not-semver'''
        $Result = Invoke-ValidationFixture
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'three-part numeric version'
    }

    It 'accepts a matching future version tag' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'VERSION') -Value '9.9.9'
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Scripts\Add-ComputerToADGroup.ps1') -Value '$script:Version = ''9.9.9'''
        $Result = Invoke-ValidationFixture -Tag 'v9.9.9'
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
    }
}
