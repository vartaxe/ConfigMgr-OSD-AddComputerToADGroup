<#
.SYNOPSIS
Adds the local computer account to one or more Active Directory groups during a ConfigMgr Task Sequence.

.DESCRIPTION
Reads ADGroupUserName and ADGroupPassword from custom Task Sequence variables. The script runs in the full Windows phase of a ConfigMgr Task Sequence, connects to Active Directory using Kerberos over LDAPS TCP 636, adds the current computer account to one or more AD groups when required, and verifies direct membership after the update.

.PARAMETER GroupName
One or more Active Directory group sAMAccountName values.

.PARAMETER RetryCount
Number of complete retry passes for transient readiness or directory failures. Default is 3.

.PARAMETER RetryDelaySeconds
Delay between retry passes. Default is 300 seconds.

.PARAMETER TimeoutSeconds
LDAP connection and operation timeout per domain controller. Default is 30 seconds.

.EXAMPLE
.\Add-ComputerToADGroup.ps1 -GroupName "Workstation-Certificate-AutoEnroll"

.EXAMPLE
.\Add-ComputerToADGroup.ps1 -GroupName "Group-A","Group-B"

.LINK
https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup

.NOTES
FileName:      Add-ComputerToADGroup.ps1
Author:        vartaxe
Contact:       https://github.com/vartaxe
Contributors:  Microsoft Copilot
Version:       1.1.0
Release:       2026-08-05
Target:        Windows PowerShell 5.1 during a ConfigMgr Task Sequence in full Windows.
LogFile:       AddComputerToADGroup.log
#>
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
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Version = '1.1.0'
$script:TaskSequenceEnvironment = $null
$script:LogPath = $null

function Get-TaskSequenceEnvironment {
    try {
        return New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
    }
    catch {
        throw 'Microsoft.SMS.TSEnvironment is unavailable. Run this script inside a ConfigMgr Task Sequence.'
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

function Initialize-ScriptLog {
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
        Write-Verbose $_.Exception.Message
    }

    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
        [void](New-Item -Path $Folder -ItemType Directory -Force)
    }

    $script:LogPath = Join-Path -Path $Folder -ChildPath 'AddComputerToADGroup.log'
}

function Write-ScriptLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace($script:LogPath)) {
        $FallbackFolder = Join-Path -Path $env:WINDIR -ChildPath 'Temp'
        if (-not (Test-Path -LiteralPath $FallbackFolder -PathType Container)) {
            [void](New-Item -Path $FallbackFolder -ItemType Directory -Force)
        }
        $script:LogPath = Join-Path -Path $FallbackFolder -ChildPath 'AddComputerToADGroup.log'
    }

    $Line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LogPath -Value $Line -Encoding UTF8
    if ($Level -ne 'INFO') {
        Write-Output $Line
    }
}

function ConvertTo-LdapFilterValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $Builder = New-Object System.Text.StringBuilder
    foreach ($Character in $Value.ToCharArray()) {
        switch ([int][char]$Character) {
            0  { [void]$Builder.Append('\00') }
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
        Status  = $Status
        Message = $Message
    }
}

function Connect-LdapServer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $true)]
        [int]$Timeout
    )

    $Identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier -ArgumentList $Server, 636, $true, $false
    $Connection = New-Object System.DirectoryServices.Protocols.LdapConnection -ArgumentList $Identifier

    try {
        $Connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Kerberos
        $Connection.Credential = $Credential.GetNetworkCredential()
        $Connection.SessionOptions.ProtocolVersion = 3
        $Connection.SessionOptions.SecureSocketLayer = $true
        $Connection.Timeout = New-TimeSpan -Seconds $Timeout
        $Connection.Bind()
        return $Connection
    }
    catch {
        $Connection.Dispose()
        throw
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
            return [string]$Entry.Attributes[$Name][0]
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

function Test-DirectGroupMembership {
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

function Invoke-DirectMembershipUpdate {
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
    catch [System.DirectoryServices.Protocols.DirectoryOperationException] {
        if ($_.Exception.Response.ResultCode -ne [System.DirectoryServices.Protocols.ResultCode]::AttributeOrValueExists) {
            throw
        }
    }
}

function Test-PermanentDirectoryError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if ($ErrorRecord.Exception -is [System.DirectoryServices.Protocols.LdapException]) {
        if ($ErrorRecord.Exception.ErrorCode -eq 49) {
            return $true
        }
    }

    if ($ErrorRecord.Exception -is [System.DirectoryServices.Protocols.DirectoryOperationException]) {
        $PermanentCodes = @(
            [System.DirectoryServices.Protocols.ResultCode]::InsufficientAccessRights,
            [System.DirectoryServices.Protocols.ResultCode]::InvalidCredentials,
            [System.DirectoryServices.Protocols.ResultCode]::ConstraintViolation,
            [System.DirectoryServices.Protocols.ResultCode]::ObjectClassViolation,
            [System.DirectoryServices.Protocols.ResultCode]::NamingViolation,
            [System.DirectoryServices.Protocols.ResultCode]::UnwillingToPerform
        )
        if ($ErrorRecord.Exception.Response.ResultCode -in $PermanentCodes) {
            return $true
        }
    }

    if ($ErrorRecord.Exception.Message -match "AD group '.*' was not found") {
        return $true
    }
    if ($ErrorRecord.Exception.Message -match "AD group '.*' returned multiple results") {
        return $true
    }
    if ($ErrorRecord.Exception.Message -match 'invalid credentials|insufficient access|access is denied') {
        return $true
    }
    return $false
}

$ExitCode = 1
try {
    Add-Type -AssemblyName System.DirectoryServices.Protocols
    Add-Type -AssemblyName System.DirectoryServices

    if ($env:SystemDrive -eq 'X:') {
        throw 'Windows PE is not supported. Run this script after Windows setup and domain join.'
    }

    $script:TaskSequenceEnvironment = Get-TaskSequenceEnvironment
    Initialize-ScriptLog
    Write-ScriptLog -Message "Add-ComputerToADGroup started. Version=$script:Version"

    $UserName = Get-TaskSequenceVariable -Environment $script:TaskSequenceEnvironment -Name 'ADGroupUserName'
    $Password = Get-TaskSequenceVariable -Environment $script:TaskSequenceEnvironment -Name 'ADGroupPassword'
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

        Write-ScriptLog -Message "Pass $Pass of $RetryCount. Pending=$($PendingGroups -join ',')"

        try {
            if (-not (Test-ComputerSecureChannel -ErrorAction Stop)) {
                throw 'The computer secure channel is not operational.'
            }

            $DomainControllers = @(Get-DomainControllerName)
            Write-ScriptLog -Message "Discovered domain controllers: $($DomainControllers.Count)"
            if ($DomainControllers.Count -eq 0) {
                throw 'No domain controllers were discovered.'
            }

            foreach ($DomainController in $DomainControllers) {
                if (@($RequestedGroups | Where-Object { -not $Results.ContainsKey($_) }).Count -eq 0) {
                    break
                }

                $Connection = $null
                try {
                    $Connection = Connect-LdapServer -Server $DomainController -Credential $Credential -Timeout $TimeoutSeconds
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

                            if (Test-DirectGroupMembership -Connection $Connection -GroupDistinguishedName $GroupDn -ComputerDistinguishedName $ComputerDn) {
                                $Results[$CurrentGroup] = Get-OperationResult -Success $true -Status 'AlreadyMember'
                            }
                            else {
                                Invoke-DirectMembershipUpdate -Connection $Connection -GroupDistinguishedName $GroupDn -ComputerDistinguishedName $ComputerDn
                                if (-not (Test-DirectGroupMembership -Connection $Connection -GroupDistinguishedName $GroupDn -ComputerDistinguishedName $ComputerDn)) {
                                    throw 'Membership verification failed.'
                                }
                                $Results[$CurrentGroup] = Get-OperationResult -Success $true -Status 'AddedAndVerified'
                            }
                        }
                        catch {
                            if (Test-PermanentDirectoryError -ErrorRecord $_) {
                                $Results[$CurrentGroup] = Get-OperationResult -Success $false -Status 'FailedPermanent' -Message $_.Exception.Message
                            }
                            else {
                                Write-ScriptLog -Level 'WARN' -Message "Transient group failure on ${DomainController}: Group=$CurrentGroup; Error=$($_.Exception.Message)"
                            }
                        }
                    }
                }
                catch {
                    if (Test-PermanentDirectoryError -ErrorRecord $_) {
                        foreach ($CurrentGroup in @($PendingGroups | Where-Object { -not $Results.ContainsKey($_) })) {
                            $Results[$CurrentGroup] = Get-OperationResult -Success $false -Status 'FailedPermanent' -Message $_.Exception.Message
                        }
                        break
                    }
                    Write-ScriptLog -Level 'WARN' -Message "Transient DC failure on ${DomainController}: $($_.Exception.Message)"
                }
                finally {
                    if ($null -ne $Connection) {
                        $Connection.Dispose()
                    }
                }
            }
        }
        catch {
            Write-ScriptLog -Level 'WARN' -Message "Transient readiness failure: $($_.Exception.Message)"
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

        $LogLevel = 'INFO'
        if (-not $Results[$CurrentGroup].Success) {
            $LogLevel = 'ERROR'
        }
        Write-ScriptLog -Level $LogLevel -Message "Summary: Group=$CurrentGroup; Result=$($Results[$CurrentGroup].Status); Message=$($Results[$CurrentGroup].Message)"
    }

    $FailedGroups = @($RequestedGroups | Where-Object { -not $Results[$_].Success })
    if ($FailedGroups.Count -gt 0) {
        throw 'One or more group operations failed.'
    }

    $ExitCode = 0
}
catch {
    Write-ScriptLog -Level 'ERROR' -Message $_.Exception.Message
    $ExitCode = 1
}
finally {
    if ($null -ne $script:TaskSequenceEnvironment) {
        try {
            $script:TaskSequenceEnvironment.Value('ADGroupUserName') = ''
            $script:TaskSequenceEnvironment.Value('ADGroupPassword') = ''
            Write-ScriptLog -Message 'Task Sequence credential variables cleared.'
        }
        catch {
            Write-ScriptLog -Level 'WARN' -Message "Could not clear Task Sequence credential variables: $($_.Exception.Message)"
        }
    }

    $Credential = $null
    $script:TaskSequenceEnvironment = $null
    Write-ScriptLog -Message "Script exit code: $ExitCode"
}

if ($ExitCode -eq 0) {
    Write-Output 'AD group operation completed successfully.'
}
else {
    Write-Output 'AD group operation failed. See AddComputerToADGroup.log.'
}
exit $ExitCode
