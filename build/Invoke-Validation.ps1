#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Tag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1') {
    throw 'Validation must run in Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.'
}

$Root = Split-Path -Parent $PSScriptRoot
$Files = @(Get-ChildItem -LiteralPath $Root -File -Recurse | Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') })
foreach ($File in $Files) {
    $Tokens = $null
    $ParseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$ParseErrors)
    if ($ParseErrors.Count -gt 0) {
        throw "Parser errors in $($File.FullName): $($ParseErrors.Message -join '; ')"
    }
}
Write-Output "Parser: $($Files.Count) PowerShell files passed."

$Version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$ScriptContent = Get-Content -LiteralPath (Join-Path $Root 'Scripts\Add-ComputerToADGroup.ps1') -Raw
$VersionMatch = [regex]::Match($ScriptContent, '(?m)^\$script:Version\s*=\s*''([^'']+)''\s*$')
if (-not $VersionMatch.Success -or $VersionMatch.Groups[1].Value -cne $Version) {
    throw 'VERSION and the production script version do not match.'
}
if ($Version -cne '1.0.0') {
    throw 'This import must retain version 1.0.0.'
}
if ($PSBoundParameters.ContainsKey('Tag') -and $Tag -cne "v$Version") {
    throw 'Tag, VERSION, and the production script version do not match.'
}

Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -ErrorAction Stop
$Findings = @(
    foreach ($Directory in @('Scripts', 'Tests', 'build')) {
        Invoke-ScriptAnalyzer -Path (Join-Path $Root $Directory) -Recurse -Severity Error, Warning
    }
)
if ($Findings.Count -gt 0) {
    $Findings | Format-Table -AutoSize | Out-Host
    throw 'PSScriptAnalyzer warnings or errors require individual review.'
}
Write-Output 'PSScriptAnalyzer: Scripts, Tests, and build passed.'

Import-Module Pester -RequiredVersion 5.7.1 -ErrorAction Stop
$Configuration = New-PesterConfiguration
$Configuration.Run.Path = Join-Path $Root 'Tests'
$Configuration.Run.PassThru = $true
$Configuration.Output.Verbosity = 'Detailed'
$Result = Invoke-Pester -Configuration $Configuration
if ($Result.Result -ne 'Passed' -or $Result.TotalCount -eq 0 -or $Result.SkippedCount -gt 0 -or $Result.NotRunCount -gt 0) {
    throw 'Pester did not pass every discovered test.'
}
