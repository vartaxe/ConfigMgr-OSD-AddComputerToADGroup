BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Content = Get-Content (Join-Path $script:Root 'Scripts\Add-ComputerToADGroup.ps1') -Raw
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseInput($script:Content, [ref]$null, [ref]$null)
}

Describe 'Repository contract' {
    It 'keeps one matching three-part numeric version in the script and manifest' {
        $VersionMatch = [regex]::Match($script:Content, '(?m)^\$script:Version\s*=\s*''(\d+\.\d+\.\d+)''\s*$')
        $VersionMatch.Success | Should -BeTrue
        $ManifestVersion = (Get-Content (Join-Path $script:Root 'VERSION') -Raw).Trim()
        $ManifestVersion | Should -Match '^\d+\.\d+\.\d+$'
        $VersionMatch.Groups[1].Value | Should -BeExactly $ManifestVersion
    }

    It 'requires Windows PowerShell 5.1 and has strict mode and explicit exit' {
        $script:Content | Should -Match '(?m)^#Requires -Version 5\.1'
        $script:Content | Should -Match 'Set-StrictMode'
        $script:Ast.EndBlock.Statements[-1].GetType().Name | Should -Be 'ExitStatementAst'
    }

    It 'uses only documented credential variables and the log path' {
        $script:Content | Should -Match 'Microsoft\.SMS\.TSEnvironment'
        $script:Content | Should -Match "-Name 'ADGroupUserName'"
        $script:Content | Should -Match "-Name 'ADGroupPassword'"
        $script:Content | Should -Not -Match '\.GetVariables\('
        $script:Content | Should -Not -Match '_SMSTS(?!LogPath)\w+'
    }

    It 'retains secure defaults and explicit compatibility parameters' {
        $Parameters = @{}
        foreach ($Parameter in $script:Ast.ParamBlock.Parameters) {
            $Parameters[$Parameter.Name.VariablePath.UserPath] = $Parameter
        }
        $Parameters['AuthenticationMode'].DefaultValue.Value | Should -BeExactly 'Kerberos'
        $Parameters['DirectoryTransport'].DefaultValue.Value | Should -BeExactly 'LDAPS'
        $Parameters.Keys | Should -Contain 'AllowNtlmV2'
    }

    It 'has no forbidden runtime APIs, anonymous bind, or certificate bypass' {
        $script:Content | Should -Not -Match 'cmdkey|net\s+use|Win32_Product|Get-WmiObject|\bwmic(?:\.exe)?\b'
        $script:Content | Should -Not -Match 'AuthType\]::(Basic|Anonymous|Ntlm)\b|VerifyServerCertificate|ServerCertificateValidationCallback'
    }

    It 'has one matching SHA-256 entry for every maintained file except the checksum manifest' {
        $Names = @()
        foreach ($Line in (Get-Content -LiteralPath (Join-Path $script:Root 'CHECKSUMS.txt'))) {
            $Entry = [regex]::Match($Line, '^([A-Fa-f0-9]{64})  ([^\\]+)$')
            $Entry.Success | Should -BeTrue
            $Name = $Entry.Groups[2].Value
            $Name | Should -Not -Be 'CHECKSUMS.txt'
            $Path = Join-Path $script:Root $Name.Replace('/', '\')
            Test-Path -LiteralPath $Path -PathType Leaf | Should -BeTrue
            (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash | Should -Be $Entry.Groups[1].Value
            $Names += $Name
        }
        @($Names | Sort-Object -Unique).Count | Should -Be $Names.Count
        $Expected = @(
            Get-ChildItem -LiteralPath $script:Root -Recurse -File -Force |
                Where-Object {
                    $_.Name -notin @('.git', 'CHECKSUMS.txt') -and
                    $_.FullName -ne (Join-Path $script:Root '.git') -and
                    $_.FullName -notlike "$script:Root\.git\*"
                } |
                ForEach-Object { $_.FullName.Substring($script:Root.Length + 1).Replace('\', '/') }
        )
        @(Compare-Object ($Expected | Sort-Object) ($Names | Sort-Object)).Count | Should -Be 0
    }

    It 'pins checkout actions, retains publisher verification, and preserves release gates' {
        $WorkflowFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:Root '.github\workflows') -Filter '*.yml' -File)
        $WorkflowFiles.Count | Should -BeGreaterThan 0

        foreach ($WorkflowFile in $WorkflowFiles) {
            $WorkflowContent = Get-Content -LiteralPath $WorkflowFile.FullName -Raw
            $WorkflowContent | Should -Match '(?m)^\s*-\s*uses:\s+actions/checkout@[A-Fa-f0-9]{40}(?:\s+#.*)?\s*$'
            $WorkflowContent | Should -Not -Match '(?i)-SkipPublisherCheck'
        }

        $CiWorkflow = Get-Content -LiteralPath (Join-Path $script:Root '.github\workflows\ci.yml') -Raw
        $CiWorkflow | Should -Match '\$ValidationParameters\s*=\s*@\{\}'

        $ReleaseWorkflow = Get-Content -LiteralPath (Join-Path $script:Root '.github\workflows\release.yml') -Raw
        $ReleaseWorkflow | Should -Match "(?m)^\s*-\s*'v\*\.\*\.\*'\s*$"
        $ReleaseWorkflow | Should -Match '(?m)^\s+ref:\s+refs/tags/\$\{\{\s*env\.RELEASE_TAG\s*\}\}\s*$'
        $ReleaseWorkflow | Should -Match '(?m)^\s+git archive[^\r\n]+"refs/tags/\$env:RELEASE_TAG"\s*$'
        foreach ($RequiredText in 'Validate tagged revision', 'Create release archive', 'Get-FileHash', 'Publish GitHub prerelease', 'gh release create', '--verify-tag') {
            $ReleaseWorkflow | Should -Match ([regex]::Escape($RequiredText))
        }

        $ValidationDocumentation = Get-Content -LiteralPath (Join-Path $script:Root 'docs\validation.md') -Raw
        $ValidationDocumentation | Should -Not -Match '(?i)-SkipPublisherCheck'
    }
}
