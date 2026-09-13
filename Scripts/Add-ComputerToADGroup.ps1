<#
.SYNOPSIS
Adds the current computer account to one or more Active Directory groups during a ConfigMgr Task Sequence.

.DESCRIPTION
Reads ADGroupUserName and ADGroupPassword from explicit custom Task Sequence variables.
The script runs as Local System in the full Windows phase of a ConfigMgr Task Sequence after domain join and a restart, connects to Active Directory by using Kerberos over LDAPS on TCP 636, adds the local computer account to the requested group or groups when needed, and verifies direct membership before returning success.

The script intentionally avoids Network Access Account retrieval, hidden reserved Task Sequence credential variables, legacy command-based credential helpers, LDAP fallback, explicit NTLM LDAP mode, and command-line passwords.
Credential variables should be created immediately before the script step and cleared immediately afterward with native Task Sequence steps.

.PARAMETER GroupName
One or more Active Directory group sAMAccountName values.

.PARAMETER RetryCount
Number of full retry passes for transient readiness or directory issues. Default: 3.

.PARAMETER RetryDelaySeconds
Delay between retry passes. Default: 300 seconds.

.PARAMETER TimeoutSeconds
Timeout for each LDAP connection or operation, not for the entire run. Default: 30 seconds.

.PARAMETER AuthenticationMode
Kerberos by default. Negotiate requires AllowNtlmV2 and an explicit NTLMv2-only client policy.

.PARAMETER DirectoryTransport
LDAPS on TCP 636 by default. SignedLdap explicitly selects TCP 389 with signing and sealing.

.PARAMETER AllowNtlmV2
Permits Negotiate when LmCompatibilityLevel is explicitly set to 3, 4, or 5.
The script does not change policy or determine which protocol Negotiate selected.

.EXAMPLE
.\Add-ComputerToADGroup.ps1 -GroupName "Workstation-Certificate-AutoEnroll"

Adds the local computer account to one group and verifies direct membership.

.EXAMPLE
.\Add-ComputerToADGroup.ps1 -GroupName "Group-A","Group-B"

Adds the local computer account to multiple groups and returns success only if all requested operations succeed.

.LINK
https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup

.NOTES
FileName:      Add-ComputerToADGroup.ps1
Author:        Claudio Mendes (vartaxe)
Contact:       vartaxe@outlook.com | https://github.com/vartaxe
Version:       1.0.0
Release:       2026-08-03
Target:        Windows PowerShell 5.1 during a ConfigMgr Task Sequence in full Windows.
LogFile:       AddComputerToADGroup.log
#>
#Requires -Version 5.1
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText',
    '',
    Justification = 'The password is supplied at runtime through a hidden ConfigMgr Task Sequence variable, converted immediately to PSCredential, never logged, and not stored in the script.'
)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$GroupName,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$RetryCount = 3,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$RetryDelaySeconds = 300,

    [Parameter(Mandatory = $false)]
    [ValidateRange(5, 300)]
    [int]$TimeoutSeconds = 30,

    [ValidateSet('Kerberos','Negotiate')]
    [string]$AuthenticationMode = 'Kerberos',

    [ValidateSet('LDAPS','SignedLdap')]
    [string]$DirectoryTransport = 'LDAPS',

    [switch]$AllowNtlmV2
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Version = '1.0.0'
$script:TaskSequenceEnvironment = $null
$script:LogPath = $null
$script:Component = 'AddComputerToADGroup'

function Get-TaskSequenceEnvironment {
    try {
        return New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
    }
    catch {
        throw 'Microsoft.SMS.TSEnvironment is unavailable. Run this script inside an active ConfigMgr Task Sequence.'
    }
}

function Get-TaskSequenceVariable {
    param(
        [Parameter(Mandatory = $true)]
        $Environment,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $Value = [string]$Environment.Value($Name)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Task Sequence variable '$Name' is empty."
    }

    return $Value
}

function Initialize-Log {
    $Folder = Join-Path -Path $env:WINDIR -ChildPath 'Temp'

    try {
        $TaskSequenceLogPath = [string]$script:TaskSequenceEnvironment.Value('_SMSTSLogPath')
        if (-not [string]::IsNullOrWhiteSpace($TaskSequenceLogPath)) {
            if (Test-Path -LiteralPath $TaskSequenceLogPath -PathType Container) {
                $Folder = $TaskSequenceLogPath
            }
        }
    }
    catch {
        Write-Warning 'Cannot read _SMSTSLogPath; using the Windows Temp log location.'
    }

    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
        [void](New-Item -Path $Folder -ItemType Directory -Force)
    }

    $script:LogPath = Join-Path -Path $Folder -ChildPath 'AddComputerToADGroup.log'
}

function Write-Log {
    param([Parameter(Mandatory=$true)][string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    try {
        $Type = switch ($Level) { 'WARN' {2} 'ERROR' {3} default {1} }
        $Now = [DateTimeOffset]::Now
        $Bias = [int]$Now.Offset.TotalMinutes
        $Time = $Now.ToString('HH:mm:ss.fff') + ('{0:+0;-0;+0}' -f $Bias)
        $Safe = $Message -replace '[\r\n]+',' ' -replace '\]LOG\]!>', ']LOG removed>'
        $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="{5}" file="">' -f $Safe,$Time,$Now.ToString('MM-dd-yyyy'),$script:Component,$Type,[Threading.Thread]::CurrentThread.ManagedThreadId
        Add-Content -LiteralPath $script:LogPath -Value $Line -Encoding UTF8 -ErrorAction Stop
    } catch { Write-Warning 'Cannot write AddComputerToADGroup.log; check the log directory and permissions.' }
    if($Level -ne 'INFO'){ Write-Output "[$Level] $Message" }
}

function ConvertTo-LdapFilterValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $Builder = New-Object System.Text.StringBuilder
    foreach ($Character in $Value.ToCharArray()) {
        switch ([int][char]$Character) {
            0 { [void]$Builder.Append('\00') }
            40 { [void]$Builder.Append('\28') }
            41 { [void]$Builder.Append('\29') }
            42 { [void]$Builder.Append('\2a') }
            92 { [void]$Builder.Append('\5c') }
            default { [void]$Builder.Append($Character) }
        }
    }

    return $Builder.ToString()
}

function Get-DomainControllerName {
    $Domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()
    $Names = @(
        $Domain.DomainControllers |
            ForEach-Object { $_.Name.ToLowerInvariant() } |
            Sort-Object -Unique
    )
    return $Names
}

function Connect-LdapServer {
    param([string]$Server,[Management.Automation.PSCredential]$Credential,[int]$Timeout,[string]$Authentication,[string]$Transport)
    $Port=if($Transport -eq 'LDAPS'){636}else{389}
    $Identifier=New-Object DirectoryServices.Protocols.LdapDirectoryIdentifier -ArgumentList $Server,$Port,$true,$false
    $Connection=New-Object DirectoryServices.Protocols.LdapConnection -ArgumentList $Identifier
    try {
        $Connection.AuthType=if($Authentication -eq 'Kerberos'){[DirectoryServices.Protocols.AuthType]::Kerberos}else{[DirectoryServices.Protocols.AuthType]::Negotiate}
        $Connection.Credential=$Credential.GetNetworkCredential(); $Connection.SessionOptions.ProtocolVersion=3; $Connection.Timeout=New-TimeSpan -Seconds $Timeout
        if($Transport -eq 'LDAPS'){$Connection.SessionOptions.SecureSocketLayer=$true}else{$Connection.SessionOptions.Signing=$true;$Connection.SessionOptions.Sealing=$true}
        $Connection.Bind(); return $Connection
    } catch {$Connection.Dispose();throw}
}

function Assert-AuthenticationPolicy {
    param([string]$Authentication, [string]$Transport, [bool]$AllowFallback)

    if ($Authentication -eq 'Negotiate') {
        if (-not $AllowFallback) {
            throw 'Negotiate requires explicit -AllowNtlmV2 permission.'
        }

        $Policy = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction Stop
        $Level = $Policy.PSObject.Properties['LmCompatibilityLevel']
        if ($null -eq $Level -or $Level.Value -isnot [int] -or $Level.Value -notin @(3, 4, 5)) {
            throw 'Negotiate requires an explicit LmCompatibilityLevel of 3, 4, or 5; configure NTLMv2-only client policy before retrying.'
        }

        Write-Log -Level 'WARN' -Message 'Compatibility enabled: Negotiate with NTLMv2-only client policy. The negotiated protocol is not reported.'
    }

    if ($Transport -eq 'SignedLdap') {
        Write-Log -Level 'WARN' -Message 'Compatibility enabled: SignedLdap on TCP 389 with signing and sealing required.'
    }
}

function Get-LdapAttributeValue {
    param(
        [Parameter(Mandatory = $true)]
        $Entry,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Entry.Attributes.Contains($Name)) {
        if ($Entry.Attributes[$Name].Count -gt 0) {
            return [string]$Entry.Attributes[$Name].GetValues([string])[0]
        }
    }
    return $null
}

function Get-DefaultNamingContext {
    param(
        [Parameter(Mandatory = $true)]
        $Connection
    )

    $Request = New-Object System.DirectoryServices.Protocols.SearchRequest -ArgumentList '', '(objectClass=*)', ([System.DirectoryServices.Protocols.SearchScope]::Base), @('defaultNamingContext')
    $Response = $Connection.SendRequest($Request)

    if ($Response.Entries.Count -ne 1) {
        throw 'RootDSE lookup failed.'
    }

    $NamingContext = Get-LdapAttributeValue -Entry $Response.Entries[0] -Name 'defaultNamingContext'
    if ([string]::IsNullOrWhiteSpace($NamingContext)) {
        throw 'RootDSE did not return defaultNamingContext.'
    }

    return $NamingContext
}

function Find-LdapObject {
    param(
        [Parameter(Mandatory = $true)]
        $Connection,

        [Parameter(Mandatory = $true)]
        [string]$SearchBase,

        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $Request = New-Object System.DirectoryServices.Protocols.SearchRequest -ArgumentList $SearchBase, $Filter, ([System.DirectoryServices.Protocols.SearchScope]::Subtree), @('distinguishedName')
    $Response = $Connection.SendRequest($Request)

    if ($Response.Entries.Count -eq 0) {
        throw "$Description was not found."
    }

    if ($Response.Entries.Count -gt 1) {
        throw "$Description returned multiple results."
    }

    return $Response.Entries[0]
}

function Test-DirectMembership {
    param(
        [Parameter(Mandatory = $true)]
        $Connection,

        [Parameter(Mandatory = $true)]
        [string]$GroupDistinguishedName,

        [Parameter(Mandatory = $true)]
        [string]$ComputerDistinguishedName
    )

    $EscapedComputer = ConvertTo-LdapFilterValue -Value $ComputerDistinguishedName
    $Filter = '(&(objectClass=group)(member={0}))' -f $EscapedComputer
    $Request = New-Object System.DirectoryServices.Protocols.SearchRequest -ArgumentList $GroupDistinguishedName, $Filter, ([System.DirectoryServices.Protocols.SearchScope]::Base), @('distinguishedName')
    $Response = $Connection.SendRequest($Request)
    return ($Response.Entries.Count -eq 1)
}

function Invoke-DirectMembershipAdd {
    param(
        [Parameter(Mandatory = $true)]
        $Connection,

        [Parameter(Mandatory = $true)]
        [string]$GroupDistinguishedName,

        [Parameter(Mandatory = $true)]
        [string]$ComputerDistinguishedName
    )

    $Change = New-Object System.DirectoryServices.Protocols.DirectoryAttributeModification
    $Change.Name = 'member'
    $Change.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
    [void]$Change.Add($ComputerDistinguishedName)
    $Request = New-Object System.DirectoryServices.Protocols.ModifyRequest -ArgumentList $GroupDistinguishedName, $Change

    try {
        [void]$Connection.SendRequest($Request)
    }
    catch {
        $Exception = Get-DirectoryException -ErrorRecord $_
        if ($Exception -isnot [System.DirectoryServices.Protocols.DirectoryOperationException] -or
            $null -eq $Exception.Response -or
            $Exception.Response.ResultCode -ne [System.DirectoryServices.Protocols.ResultCode]::AttributeOrValueExists) {
            throw
        }
    }
}

function Get-DirectoryException {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $Exception = $ErrorRecord.Exception
    while ($null -ne $Exception.InnerException) {
        $Exception = $Exception.InnerException
    }
    return $Exception
}

function Get-SafeErrorMessage {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $Exception = Get-DirectoryException -ErrorRecord $ErrorRecord
    if ($Exception -is [System.DirectoryServices.Protocols.LdapException]) {
        return "LDAP error code $($Exception.ErrorCode)."
    }
    if ($Exception -is [System.DirectoryServices.Protocols.DirectoryOperationException] -and $null -ne $Exception.Response) {
        return "Directory result: $($Exception.Response.ResultCode)."
    }

    # Only locally defined, credential-free messages may pass through to either log.
    $KnownMessages = @(
        'Microsoft.SMS.TSEnvironment is unavailable. Run this script inside an active ConfigMgr Task Sequence.',
        "Task Sequence variable 'ADGroupUserName' is empty.",
        "Task Sequence variable 'ADGroupPassword' is empty.",
        'Windows PE is not supported. Run this script after Windows setup, domain join, and a restart.',
        'Negotiate requires explicit -AllowNtlmV2 permission.',
        'Negotiate requires an explicit LmCompatibilityLevel of 3, 4, or 5; configure NTLMv2-only client policy before retrying.',
        'No valid group names were provided.',
        'The computer secure channel is not operational.',
        'No domain controllers were discovered.',
        'RootDSE lookup failed.',
        'RootDSE did not return defaultNamingContext.',
        'Membership verification failed.',
        'One or more group operations failed.'
    )
    if ($Exception.Message -cin $KnownMessages) {
        return $Exception.Message
    }
    if ($Exception.Message -match "^AD group '.*' was not found\.$") {
        return 'Requested AD group was not found.'
    }
    if ($Exception.Message -match "^AD group '.*' returned multiple results\.$") {
        return 'Requested AD group returned multiple results.'
    }
    if ($Exception.Message -match "^Computer account '.*' was not found\.$") {
        return 'Computer account was not found.'
    }
    if ($Exception.Message -match "^Computer account '.*' returned multiple results\.$") {
        return 'Computer account returned multiple results.'
    }
    return "Operation failed ($($Exception.GetType().Name)); raw exception details are omitted to protect credentials."
}

function Test-PermanentDirectoryError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $Exception = Get-DirectoryException -ErrorRecord $ErrorRecord
    if ($Exception -is [System.DirectoryServices.Protocols.LdapException]) {
        if ($Exception.ErrorCode -in @(8, 13, 19, 34, 49, 50, 53, 64, 65, 67)) {
            return $true
        }
    }

    if ($Exception -is [System.DirectoryServices.Protocols.DirectoryOperationException] -and $null -ne $Exception.Response) {
        $PermanentCodes = @(
            [System.DirectoryServices.Protocols.ResultCode]::StrongAuthRequired,
            [System.DirectoryServices.Protocols.ResultCode]::ConfidentialityRequired,
            [System.DirectoryServices.Protocols.ResultCode]::InvalidDNSyntax,
            [System.DirectoryServices.Protocols.ResultCode]::InsufficientAccessRights,
            [System.DirectoryServices.Protocols.ResultCode]::ConstraintViolation,
            [System.DirectoryServices.Protocols.ResultCode]::ObjectClassViolation,
            [System.DirectoryServices.Protocols.ResultCode]::NamingViolation,
            [System.DirectoryServices.Protocols.ResultCode]::UnwillingToPerform
        )

        if ($Exception.Response.ResultCode -in $PermanentCodes) {
            return $true
        }
    }

    if ($Exception.Message -match "^AD group '.*' was not found\.$") {
        return $true
    }

    if ($Exception.Message -match "^AD group '.*' returned multiple results\.$") {
        return $true
    }

    if ($Exception -is [System.UnauthorizedAccessException]) {
        return $true
    }

    return $false
}

function Get-OperationResult {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$Message = ''
    )

    return [pscustomobject]@{
        Success = $Success
        Status = $Status
        Message = $Message
    }
}

$ExitCode = 1

try {
    Add-Type -AssemblyName System.DirectoryServices.Protocols
    Add-Type -AssemblyName System.DirectoryServices

    if ($env:SystemDrive -eq 'X:') {
        throw 'Windows PE is not supported. Run this script after Windows setup, domain join, and a restart.'
    }

    $script:TaskSequenceEnvironment = Get-TaskSequenceEnvironment
    Initialize-Log
    Write-Log -Message "Add-ComputerToADGroup started. Version=$script:Version"
    Assert-AuthenticationPolicy -Authentication $AuthenticationMode -Transport $DirectoryTransport -AllowFallback $AllowNtlmV2.IsPresent

    $UserName = Get-TaskSequenceVariable -Environment $script:TaskSequenceEnvironment -Name 'ADGroupUserName'
    $Password = Get-TaskSequenceVariable -Environment $script:TaskSequenceEnvironment -Name 'ADGroupPassword'
    $SecurePassword = $null

    try {
        $SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $SecurePassword
    }
    finally {
        $Password = $null
        $SecurePassword = $null
    }

    $RequestedGroups = @(
        $GroupName |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    if ($RequestedGroups.Count -eq 0) {
        throw 'No valid group names were provided.'
    }

    $Results = @{}

    for ($Pass = 1; $Pass -le $RetryCount; $Pass++) {
        $PendingGroups = @($RequestedGroups | Where-Object { -not $Results.ContainsKey($_) })
        if ($PendingGroups.Count -eq 0) {
            break
        }

        Write-Log -Message "Pass $Pass of $RetryCount. Pending=$($PendingGroups -join ',')"

        try {
            if (-not (Test-ComputerSecureChannel -ErrorAction Stop)) {
                throw 'The computer secure channel is not operational.'
            }

            $DomainControllers = @(Get-DomainControllerName)
            Write-Log -Message "Discovered domain controllers: $($DomainControllers.Count)"

            if ($DomainControllers.Count -eq 0) {
                throw 'No domain controllers were discovered.'
            }

            foreach ($DomainController in $DomainControllers) {
                if (@($PendingGroups | Where-Object { -not $Results.ContainsKey($_) }).Count -eq 0) {
                    break
                }
                $Connection = $null

                try {
                    $Connection = Connect-LdapServer -Server $DomainController -Credential $Credential -Timeout $TimeoutSeconds -Authentication $AuthenticationMode -Transport $DirectoryTransport
                    $NamingContext = Get-DefaultNamingContext -Connection $Connection
                    $ComputerSam = ConvertTo-LdapFilterValue -Value ($env:COMPUTERNAME + '$')
                    $ComputerFilter = '(&(objectCategory=computer)(sAMAccountName={0}))' -f $ComputerSam
                    $Computer = Find-LdapObject -Connection $Connection -SearchBase $NamingContext -Filter $ComputerFilter -Description "Computer account '$env:COMPUTERNAME'"
                    $ComputerDn = Get-LdapAttributeValue -Entry $Computer -Name 'distinguishedName'

                    foreach ($CurrentGroup in @($PendingGroups | Where-Object { -not $Results.ContainsKey($_) })) {
                        try {
                            $GroupSam = ConvertTo-LdapFilterValue -Value $CurrentGroup
                            $GroupFilter = '(&(objectCategory=group)(sAMAccountName={0}))' -f $GroupSam
                            $GroupEntry = Find-LdapObject -Connection $Connection -SearchBase $NamingContext -Filter $GroupFilter -Description "AD group '$CurrentGroup'"
                            $GroupDn = Get-LdapAttributeValue -Entry $GroupEntry -Name 'distinguishedName'

                            if (Test-DirectMembership -Connection $Connection -GroupDistinguishedName $GroupDn -ComputerDistinguishedName $ComputerDn) {
                                $Results[$CurrentGroup] = Get-OperationResult -Success $true -Status 'AlreadyMember'
                            }
                            else {
                                Invoke-DirectMembershipAdd -Connection $Connection -GroupDistinguishedName $GroupDn -ComputerDistinguishedName $ComputerDn

                                if (-not (Test-DirectMembership -Connection $Connection -GroupDistinguishedName $GroupDn -ComputerDistinguishedName $ComputerDn)) {
                                    throw 'Membership verification failed.'
                                }

                                $Results[$CurrentGroup] = Get-OperationResult -Success $true -Status 'AddedAndVerified'
                            }
                        }
                        catch {
                            if (Test-PermanentDirectoryError -ErrorRecord $_) {
                                $Results[$CurrentGroup] = Get-OperationResult -Success $false -Status 'FailedPermanent' -Message (Get-SafeErrorMessage -ErrorRecord $_)
                            }
                            else {
                                Write-Log -Level 'WARN' -Message "Transient group failure on ${DomainController}: Group=$CurrentGroup; Error=$(Get-SafeErrorMessage -ErrorRecord $_)"
                            }
                        }
                    }
                }
                catch {
                    if (Test-PermanentDirectoryError -ErrorRecord $_) {
                        foreach ($CurrentGroup in @($PendingGroups | Where-Object { -not $Results.ContainsKey($_) })) {
                            $Results[$CurrentGroup] = Get-OperationResult -Success $false -Status 'FailedPermanent' -Message (Get-SafeErrorMessage -ErrorRecord $_)
                        }
                        break
                    }

                    Write-Log -Level 'WARN' -Message "Transient DC failure on ${DomainController}: $(Get-SafeErrorMessage -ErrorRecord $_)"
                }
                finally {
                    if ($null -ne $Connection) {
                        $Connection.Dispose()
                    }
                }
            }
        }
        catch {
            Write-Log -Level 'WARN' -Message "Transient readiness failure: $(Get-SafeErrorMessage -ErrorRecord $_)"
        }

        $RemainingGroups = @($RequestedGroups | Where-Object { -not $Results.ContainsKey($_) })
        if (($RemainingGroups.Count -gt 0) -and ($Pass -lt $RetryCount) -and ($RetryDelaySeconds -gt 0)) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    foreach ($CurrentGroup in $RequestedGroups) {
        if (-not $Results.ContainsKey($CurrentGroup)) {
            $Results[$CurrentGroup] = Get-OperationResult -Success $false -Status 'FailedTransient' -Message 'Retries exhausted.'
        }

        if ($Results[$CurrentGroup].Success) {
            $LogLevel = 'INFO'
        }
        else {
            $LogLevel = 'ERROR'
        }

        Write-Log -Level $LogLevel -Message "Summary: Group=$CurrentGroup; Result=$($Results[$CurrentGroup].Status); Message=$($Results[$CurrentGroup].Message)"
    }

    $FailedGroups = @($RequestedGroups | Where-Object { -not $Results[$_].Success })
    if ($FailedGroups.Count -gt 0) {
        throw 'One or more group operations failed.'
    }

    $ExitCode = 0
}
catch {
    Write-Log -Level 'ERROR' -Message (Get-SafeErrorMessage -ErrorRecord $_)
    $ExitCode = 1
}
finally {
    Write-Log -Message "Script exit code: $ExitCode"
}

if ($ExitCode -eq 0) {
    Write-Output 'AD group operation completed successfully.'
}
else {
    Write-Output 'AD group operation failed. See AddComputerToADGroup.log.'
}

exit $ExitCode
