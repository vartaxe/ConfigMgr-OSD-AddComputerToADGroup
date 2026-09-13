[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ScriptPath
)

$ErrorActionPreference = 'Stop'
$Failed = $false

if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $Root = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = (Get-Location).Path
    }
    $Scripts = @(Get-ChildItem -Path (Join-Path -Path $Root -ChildPath 'Scripts') -Filter '*.ps1' -ErrorAction Stop)
    if ($Scripts.Count -ne 1) {
        throw 'Expected exactly one script in the Scripts folder.'
    }
    $ScriptPath = $Scripts[0].FullName
}

$Content = Get-Content -LiteralPath $ScriptPath -Raw
$Tokens = $null
$ParserErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$Tokens, [ref]$ParserErrors)

if ($ParserErrors.Count -eq 0) {
    Write-Host 'PASS: PowerShell parser - 0 error(s)' -ForegroundColor Green
}
else {
    Write-Host "FAIL: PowerShell parser - $($ParserErrors.Count) error(s)" -ForegroundColor Red
    $ParserErrors | Format-List Extent, ErrorId, Message
    $Failed = $true
}

if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
    $Findings = @(Invoke-ScriptAnalyzer -Path $ScriptPath -Severity Error, Warning)
    if ($Findings.Count -eq 0) {
        Write-Host 'PASS: PSScriptAnalyzer - 0 finding(s)' -ForegroundColor Green
    }
    else {
        Write-Host "FAIL: PSScriptAnalyzer - $($Findings.Count) finding(s)" -ForegroundColor Red
        $Findings | Format-Table RuleName, Severity, ScriptName, Line, Message -Wrap
        $Failed = $true
    }
}
else {
    Write-Host 'SKIP: PSScriptAnalyzer is not installed.' -ForegroundColor Yellow
}

$RequiredPatterns = @(
    'RetryCount\s*=\s*3',
    'RetryDelaySeconds\s*=\s*300',
    'TimeoutSeconds\s*=\s*30',
    'Set-StrictMode -Version 2.0'
)

if ($Content -match 'Add-ComputerToADGroup') {
    $RequiredPatterns += @(
        'AuthType.*Kerberos',
        'SecureSocketLayer\s*=\s*\$true',
        'LdapDirectoryIdentifier'
    )
}
else {
    $RequiredPatterns += @(
        'OSDLogFileShare',
        'OSDLogUserName',
        'OSDLogPassword',
        'Manifest.json',
        'IncludeExtendedLogs',
        'Test-TcpPort'
    )
}

foreach ($Pattern in $RequiredPatterns) {
    if ($Content -match $Pattern) {
        Write-Host "PASS: Required pattern $Pattern" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL: Required pattern $Pattern" -ForegroundColor Red
        $Failed = $true
    }
}

$ForbiddenPatterns = @(
    '_SMSTSReserved',
    'cmdkey',
    'net\s+use',
    'SLShare',
    'AllowInsecureLdapFallback',
    'AuthType.*Ntlm'
)

foreach ($Pattern in $ForbiddenPatterns) {
    if ($Content -match $Pattern) {
        Write-Host "FAIL: Forbidden pattern $Pattern" -ForegroundColor Red
        $Failed = $true
    }
    else {
        Write-Host "PASS: Forbidden pattern $Pattern" -ForegroundColor Green
    }
}

$Hash = Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256
Write-Host "SHA256: $($Hash.Hash)" -ForegroundColor Cyan

if ($Failed) {
    Write-Host 'OVERALL: FAIL' -ForegroundColor Red
    exit 1
}
else {
    Write-Host 'OVERALL: PASS' -ForegroundColor Green
    exit 0
}
