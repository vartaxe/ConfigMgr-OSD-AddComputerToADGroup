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

function Test-ChecksumManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $ManifestPath = Join-Path $Root 'CHECKSUMS.txt'
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw 'CHECKSUMS.txt is missing.'
    }

    $ManifestNames = @()
    foreach ($Line in Get-Content -LiteralPath $ManifestPath) {
        $Entry = [regex]::Match($Line, '^([A-Fa-f0-9]{64})  ([^\\]+)$')
        if (-not $Entry.Success) {
            throw 'CHECKSUMS.txt contains an invalid entry.'
        }

        $RelativePath = $Entry.Groups[2].Value
        if ($RelativePath -eq 'CHECKSUMS.txt' -or
            $RelativePath -match '(^|/)\.\.(/|$)' -or
            $RelativePath -match '^[A-Za-z]:|^/') {
            throw 'CHECKSUMS.txt contains an unsafe path.'
        }

        $FilePath = Join-Path $Root $RelativePath.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            throw "CHECKSUMS.txt references a missing file: $RelativePath"
        }

        if ((Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash -cne $Entry.Groups[1].Value) {
            throw "Checksum verification failed: $RelativePath"
        }

        $ManifestNames += $RelativePath
    }

    if (@($ManifestNames | Sort-Object -Unique).Count -ne $ManifestNames.Count) {
        throw 'CHECKSUMS.txt contains duplicate file entries.'
    }

    $ExpectedNames = @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            Where-Object { $_.Name -notin @('.git', 'CHECKSUMS.txt') -and $_.FullName -notlike "$Root\.git\*" } |
            ForEach-Object { $_.FullName.Substring($Root.Length + 1).Replace('\', '/') }
    )
    if (@(Compare-Object ($ExpectedNames | Sort-Object) ($ManifestNames | Sort-Object)).Count -gt 0) {
        throw 'CHECKSUMS.txt does not match the maintained file list.'
    }

    Write-Output "Checksums: $($ManifestNames.Count) maintained files passed."
}

$Version = (Get-Content -LiteralPath (Join-Path $Root 'VERSION') -Raw).Trim()
$ScriptContent = Get-Content -LiteralPath (Join-Path $Root 'Scripts\Add-ComputerToADGroup.ps1') -Raw
$VersionMatch = [regex]::Match($ScriptContent, '(?m)^\$script:Version\s*=\s*''([^'']+)''\s*$')
if (-not $VersionMatch.Success -or $VersionMatch.Groups[1].Value -cne $Version) {
    throw 'VERSION and the production script version do not match.'
}
if ($Version -cnotmatch '^\d+\.\d+\.\d+$') {
    throw 'VERSION must contain a three-part numeric version.'
}
if ($PSBoundParameters.ContainsKey('Tag') -and $Tag -cne "v$Version") {
    throw 'Tag, VERSION, and the production script version do not match.'
}

Test-ChecksumManifest -Root $Root

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
if ($Result.Result -ne 'Passed' -or
    $Result.TotalCount -eq 0 -or
    $Result.FailedCount -gt 0 -or
    $Result.FailedBlocksCount -gt 0 -or
    $Result.FailedContainersCount -gt 0 -or
    $Result.SkippedCount -gt 0 -or
    $Result.InconclusiveCount -gt 0 -or
    $Result.NotRunCount -gt 0) {
    throw 'Pester did not pass every discovered test.'
}
