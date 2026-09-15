BeforeAll {
    $script:ValidationSource = Join-Path $PSScriptRoot '..\build\Invoke-Validation.ps1'

    function ConvertFrom-ValidationProcessOutput {
        param([AllowEmptyString()][string]$Text)

        if (-not $Text.StartsWith('#< CLIXML', [StringComparison]::Ordinal)) { return $Text }
        $Records = [System.Management.Automation.PSSerializer]::Deserialize(
            ($Text -replace '^#< CLIXML\r?\n', ''))
        return (@($Records | Where-Object { $null -ne $_ } | ForEach-Object { $_.ToString() }) -join "`n")
    }

    function Initialize-ValidationFixture {
        param(
            [string]$ManifestVersion = '1.0.0',
            [string]$ScriptVersion = '1.0.0',
            [AllowEmptyString()]
            [string]$TestContent = 'Describe ''Fixture'' { It ''passes'' { $true | Should -BeTrue } }'
        )

        foreach ($FixtureDirectory in @('Scripts', 'Tests', 'build')) {
            [void](New-Item -Path (Join-Path $script:FixtureRoot $FixtureDirectory) -ItemType Directory -Force)
        }
        Copy-Item -LiteralPath $script:ValidationSource -Destination (Join-Path $script:FixtureRoot 'build\Invoke-Validation.ps1')
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'VERSION') -Value $ManifestVersion
        $VersionAssignment = '$script:Version = ''{0}''' -f $ScriptVersion.Replace("'", "''")
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Scripts\Add-ComputerToADGroup.ps1') -Value $VersionAssignment
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Tests\Fixture.Tests.ps1') -Value $TestContent
    }

    function Invoke-ValidationFixture {
        param(
            [string]$Tag = 'v1.0.0',

            [switch]$SkipChecksums
        )

        $StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $StartInfo.FileName = Join-Path $PSHOME 'powershell.exe'
        $StartInfo.Arguments = '-NoProfile -NonInteractive -OutputFormat XML -ExecutionPolicy Bypass -File "' +
            (Join-Path $script:FixtureRoot 'build\Invoke-Validation.ps1') + '" -Tag "' + $Tag + '"'
        if ($SkipChecksums) {
            $StartInfo.Arguments += ' -SkipChecksums'
        }
        $StartInfo.UseShellExecute = $false
        $StartInfo.CreateNoWindow = $true
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
                Output = (ConvertFrom-ValidationProcessOutput $OutputTask.Result) + "`n" +
                    (ConvertFrom-ValidationProcessOutput $ErrorTask.Result)
            }
        }
        finally {
            $Process.Dispose()
        }
    }

    function Get-FixtureChecksumManifest {
        $Entries = @(
            Get-ChildItem -LiteralPath $script:FixtureRoot -Recurse -File |
                Where-Object { $_.Name -ne 'CHECKSUMS.txt' } |
                ForEach-Object {
                    $RelativePath = $_.FullName.Substring($script:FixtureRoot.Length + 1).Replace('\', '/')
                    '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $RelativePath
                }
        )

        return $Entries | Sort-Object
    }
}

Describe 'Validation process output decoding' {
    It 'preserves complete diagnostics from structured process output' {
        $Message = 'Fixture diagnostic: ' + ('long diagnostic ' * 20)
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [InvalidOperationException]::new($Message), 'FixtureError',
            [System.Management.Automation.ErrorCategory]::InvalidData, $null)
        $Xml = [System.Management.Automation.PSSerializer]::Serialize(@('Output marker', $ErrorRecord))

        $Output = ConvertFrom-ValidationProcessOutput ("#< CLIXML`r`n" + $Xml)

        $Output | Should -Match 'Output marker'
        $Output | Should -Match ([regex]::Escape($Message))
    }

    It 'retains unstructured startup errors and empty streams' {
        ConvertFrom-ValidationProcessOutput 'Native startup failure' | Should -BeExactly 'Native startup failure'
        ConvertFrom-ValidationProcessOutput '' | Should -BeExactly ''
        $EmptyXml = [System.Management.Automation.PSSerializer]::Serialize(@())
        ConvertFrom-ValidationProcessOutput ("#< CLIXML`n" + $EmptyXml) | Should -BeExactly ''
    }

    It 'does not hide malformed structured process output' {
        { ConvertFrom-ValidationProcessOutput "#< CLIXML`n<broken>" } | Should -Throw
    }
}

Describe 'Validation process exit gates' {
    BeforeEach {
        $script:FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    It 'exits zero only after parsing, analysis, tests, checksums, and matching tag succeed' {
        Initialize-ValidationFixture
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'CHECKSUMS.txt') -Value (Get-FixtureChecksumManifest)

        $Result = Invoke-ValidationFixture

        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Result.Output | Should -Match 'SHA-256 manifest verified'
        $Result.Output | Should -Match 'Validation passed'
    }

    It 'fails the process for a parser error' {
        Initialize-ValidationFixture
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'Scripts\Invalid.ps1') -Value 'function {'
        $Result = Invoke-ValidationFixture -SkipChecksums
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Parser errors'
    }

    It 'fails for an unreviewed analyzer warning under <Directory>' -ForEach @(
        @{ Directory = 'Scripts' }, @{ Directory = 'Tests' }, @{ Directory = 'build' }
    ) {
        Initialize-ValidationFixture
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot "$Directory\Warning.ps1") -Value 'function Get-Sample { $UnusedValue = 1 }'
        $Result = Invoke-ValidationFixture -SkipChecksums
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'PSScriptAnalyzer findings require review'
    }

    It 'fails for a Pester assertion failure' {
        Initialize-ValidationFixture -TestContent 'Describe ''Fixture'' { It ''fails'' { $false | Should -BeTrue } }'
        $Result = Invoke-ValidationFixture -SkipChecksums
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Pester did not pass'
    }

    It 'fails for a Pester discovery failure' {
        Initialize-ValidationFixture -TestContent 'throw ''Deliberate discovery failure'''
        $Result = Invoke-ValidationFixture -SkipChecksums
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Pester did not pass'
    }

    It 'fails for an empty Pester suite' {
        Initialize-ValidationFixture -TestContent ''
        $Result = Invoke-ValidationFixture -SkipChecksums
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Pester did not pass'
    }

    It 'fails for a skipped Pester test' {
        Initialize-ValidationFixture -TestContent 'Describe ''Fixture'' { It ''skips'' -Skip { $true | Should -BeTrue } }'
        $Result = Invoke-ValidationFixture -SkipChecksums
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Pester did not pass'
    }

    It 'rejects a tag that disagrees with the version' {
        Initialize-ValidationFixture
        $Result = Invoke-ValidationFixture -Tag 'v9.9.9'
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Tag does not match VERSION and script version'
    }

    It 'rejects mismatched script and manifest versions' {
        Initialize-ValidationFixture -ManifestVersion '9.9.9'
        $Result = Invoke-ValidationFixture -SkipChecksums
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'VERSION and script version differ'
    }

    It 'rejects a non-numeric version string' {
        Initialize-ValidationFixture -ManifestVersion 'not-semver' -ScriptVersion 'not-semver'
        $Result = Invoke-ValidationFixture -SkipChecksums
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'three-part numeric version'
    }

    It 'accepts a matching future version tag' {
        Initialize-ValidationFixture -ManifestVersion '9.9.9' -ScriptVersion '9.9.9'
        $Result = Invoke-ValidationFixture -Tag 'v9.9.9' -SkipChecksums
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
    }

    It 'rejects a matching version without the required v tag prefix' {
        Initialize-ValidationFixture
        $Result = Invoke-ValidationFixture -Tag '1.0.0' -SkipChecksums

        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Tag does not match VERSION and script version'
    }

    It 'fails when a maintained file is absent from the checksum manifest' {
        Initialize-ValidationFixture
        $Entries = @(Get-FixtureChecksumManifest)
        Set-Content -LiteralPath (Join-Path $script:FixtureRoot 'CHECKSUMS.txt') -Value $Entries[1..($Entries.Count - 1)]

        $Result = Invoke-ValidationFixture

        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Missing checksum entry'
    }
}
