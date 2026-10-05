#Requires -Version 5.1

<#
.SYNOPSIS
Validates the source tree using Windows PowerShell 5.1.
.PARAMETER Tag
Optional numeric version tag prefixed with v, checked against VERSION and the script.
.PARAMETER SkipChecksums
Skips only this validator's final checksum phase. Repository-contract tests still verify the manifest.
Regenerate CHECKSUMS.txt before full-tree validation, and do not use this switch for final validation.
#>
[CmdletBinding()]
param(
    [string]$Tag,
    [switch]$SkipChecksums
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

try {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or
        $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
        throw 'Validation requires Windows PowerShell 5.1 (powershell.exe).'
    }

    Import-Module Pester -RequiredVersion 5.7.1 -ErrorAction Stop
    Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -ErrorAction Stop
    $Root = Split-Path -Parent $PSScriptRoot
    $Files = @(Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -ne '.git' } |
            ForEach-Object {
                if ($_.PSIsContainer) {
                    Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Force
                }
                else { $_ }
            })

    $ScriptAst = $null
    $ScriptPath = Join-Path $Root 'Scripts\Add-ComputerToADGroup.ps1'
    foreach ($File in @($Files | Where-Object { $_.Extension -eq '.ps1' })) {
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [Management.Automation.Language.Parser]::ParseFile(
            $File.FullName, [ref]$Tokens, [ref]$ParseErrors)
        if ($ParseErrors.Count) {
            throw "Parser errors in $($File.FullName): $($ParseErrors.Message -join '; ')"
        }
        if ($File.FullName -eq $ScriptPath) { $ScriptAst = $Ast }
    }
    if ($null -eq $ScriptAst) { throw 'Production script is missing.' }

    $RepositoryVersion = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
    if ($RepositoryVersion -cnotmatch '^\d+\.\d+\.\d+$') {
        throw 'VERSION must contain a three-part numeric version.'
    }
    $Assignments = @($ScriptAst.FindAll({
                param($Node)
                $Node -is [Management.Automation.Language.AssignmentStatementAst] -and
                $Node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
                $Node.Left.VariablePath.UserPath -ieq 'script:Version'
            }, $true))
    if ($Assignments.Count -ne 1 -or
        $Assignments[0].Right -isnot [Management.Automation.Language.CommandExpressionAst] -or
        $Assignments[0].Right.Expression -isnot [Management.Automation.Language.StringConstantExpressionAst]) {
        throw 'The script must have exactly one literal $script:Version assignment.'
    }
    $ScriptVersion = $Assignments[0].Right.Expression.Value
    if ($RepositoryVersion -cne $ScriptVersion) { throw 'VERSION and script version differ.' }
    if ($PSBoundParameters.ContainsKey('Tag')) {
        if ($Tag -cnotmatch '^v\d+\.\d+\.\d+$' -or $Tag.Substring(1) -cne $RepositoryVersion) {
            throw 'Tag does not match VERSION and script version.'
        }
    }

    $Findings = @(
        foreach ($Path in 'Scripts', 'Tests', 'build') {
            Invoke-ScriptAnalyzer -Path (Join-Path $Root $Path) -Recurse -Severity Error, Warning -ErrorAction Stop
        }
    )
    if ($Findings.Count) {
        $Findings | Format-Table
        throw 'PSScriptAnalyzer findings require review.'
    }

    $Configuration = New-PesterConfiguration
    $Configuration.Run.Path = Join-Path $Root 'Tests'
    $Configuration.Run.PassThru = $true
    $Configuration.Run.Exit = $false
    $Configuration.Output.Verbosity = 'Detailed'
    $Result = Invoke-Pester -Configuration $Configuration
    if ($null -eq $Result -or $Result.Result -ne 'Passed' -or $Result.TotalCount -eq 0 -or
        $Result.FailedCount -gt 0 -or $Result.FailedContainersCount -gt 0 -or $Result.FailedBlocksCount -gt 0 -or
        $Result.SkippedCount -gt 0 -or $Result.NotRunCount -gt 0) {
        throw 'Pester did not pass every discovered test.'
    }

    if (-not $SkipChecksums) {
        $Expected = @{}
        foreach ($File in $Files) {
            $RelativePath = $File.FullName.Substring($Root.Length + 1).Replace('\', '/')
            if ($RelativePath -ne 'CHECKSUMS.txt') { $Expected[$RelativePath] = $File.FullName }
        }
        $Seen = @{}
        foreach ($Line in Get-Content -LiteralPath (Join-Path $Root 'CHECKSUMS.txt')) {
            if ($Line -cnotmatch '^([A-Fa-f0-9]{64})  (.+)$') { throw 'Malformed checksum entry.' }
            $Hash = $Matches[1]
            $RelativePath = $Matches[2]
            if ($Seen.ContainsKey($RelativePath)) { throw "Duplicate checksum entry: $RelativePath" }
            if (-not $Expected.ContainsKey($RelativePath)) { throw "Unexpected checksum entry: $RelativePath" }
            $Seen[$RelativePath] = $true
            if ((Get-FileHash -LiteralPath $Expected[$RelativePath] -Algorithm SHA256).Hash -ine $Hash) {
                throw "Checksum mismatch: $RelativePath"
            }
        }
        foreach ($RelativePath in $Expected.Keys) {
            if (-not $Seen.ContainsKey($RelativePath)) { throw "Missing checksum entry: $RelativePath" }
        }
        Write-Output 'SHA-256 manifest verified against exact source bytes.'
    }
    else { Write-Warning 'Checksums skipped for developer loop; not final validation.' }
    Write-Output 'Validation passed.'
    exit 0
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
