<#
.SYNOPSIS
Adds the local computer account to an Active Directory group during a ConfigMgr Task Sequence.

.DESCRIPTION
Reads ADGroupUserName and ADGroupPassword from custom Task Sequence variables.
Uses LDAPS by default, adds the local computer to the target group if needed, and verifies the result.

.PARAMETER GroupName
AD group sAMAccountName to add the local computer to.

.PARAMETER LogFileName
Optional log file name. Default is AddComputerToADGroup.log.

.PARAMETER AllowInsecureLdapFallback
Optional. If LDAPS on TCP 636 fails, try LDAP on TCP 389.

.EXAMPLE
.\Add-ComputerToADGroup.ps1 -GroupName "Workstation-Certificate-AutoEnroll"

.LINK
https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup

.NOTES
FileName:      Add-ComputerToADGroup.ps1
Author:        Claudio Mendes
Contact:       @vartaxe
Contributors:  Microsoft Copilot

Version history:
1.0.0 - 2026-07-28 - Initial validated release.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GroupName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogFileName = 'AddComputerToADGroup.log',

    [Parameter(Mandatory = $false)]
    [switch]$AllowInsecureLdapFallback
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ComputerName = $env:COMPUTERNAME
$TsUserVariable = 'ADGroupUserName'
$TsPasswordVariable = 'ADGroupPassword'
$MaxPasses = 3
$RetryDelaySeconds = 300

$TsEnvironment = $null
$LogPath = $null
$LdapConnection = $null
$script:NetworkCredential = $null
$AdUserName = $null
$AdPassword = $null
$ExitCode = 1
$PermanentFailure = $false
$script:LogFileName = $LogFileName

function Initialize-GroupLog {
    $DefaultFolder = Join-Path $env:WINDIR 'CCM\Logs'
    $Folder = $DefaultFolder

    try {
        if ($null -ne $script:TsEnvironment) {
            $TsLogFolder = $script:TsEnvironment.Value('_SMSTSLogPath')
            if (-not [string]::IsNullOrWhiteSpace($TsLogFolder)) {
                $Folder = $TsLogFolder
            }
        }
    }
    catch {
        $Folder = $DefaultFolder
    }

    if (-not (Test-Path -Path $Folder)) {
        New-Item -Path $Folder -ItemType Directory -Force | Out-Null
    }

    $script:LogPath = Join-Path $Folder $script:LogFileName
}

function Write-GroupLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace($script:LogPath)) {
        Initialize-GroupLog
    }

    $Line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $script:LogPath -Value $Line -Encoding UTF8
    Write-Output $Line
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
    $Builder.ToString()
}

function Get-LdapAttributeValue {
    param(
        [Parameter(Mandatory = $true)]
        $Entry,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Entry.Attributes.Contains($Name) -and $Entry.Attributes[$Name].Count -gt 0) {
        [string]$Entry.Attributes[$Name][0]
    }
}

function Connect-LdapServer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [System.Net.NetworkCredential]$AuthCredential,

        [Parameter(Mandatory = $true)]
        [bool]$UseSsl
    )

    $Port = if ($UseSsl) { 636 } else { 389 }
    $Identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier(
        $Server,
        $Port,
        $false,
        $false
    )

    $Connection = New-Object System.DirectoryServices.Protocols.LdapConnection($Identifier)

    try {
        $Connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate
        $Connection.Credential = $AuthCredential
        $Connection.SessionOptions.ProtocolVersion = 3
        $Connection.SessionOptions.SecureSocketLayer = $UseSsl
        $Connection.Timeout = New-TimeSpan -Seconds 15
        $Connection.Bind()
        $Connection
    }
    catch {
        $Connection.Dispose()
        throw
    }
}

function Get-DomainControllerList {
    $Domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()
    $List = @(
        $Domain.DomainControllers |
        ForEach-Object { $_.Name.ToLowerInvariant() } |
        Sort-Object -Unique
    )

    if ($List.Count -eq 0) {
        throw 'No domain controllers were discovered.'
    }

    $List
}

function Get-DefaultNamingContext {
    param(
        [Parameter(Mandatory = $true)]
        $Connection
    )

    $Request = New-Object System.DirectoryServices.Protocols.SearchRequest(
        '',
        '(objectClass=*)',
        [System.DirectoryServices.Protocols.SearchScope]::Base,
        @('defaultNamingContext')
    )

    $Response = $Connection.SendRequest($Request)
    if ($Response.Entries.Count -ne 1) {
        throw 'RootDSE did not return exactly one result.'
    }

    $NamingContext = Get-LdapAttributeValue -Entry $Response.Entries[0] -Name 'defaultNamingContext'
    if ([string]::IsNullOrWhiteSpace($NamingContext)) {
        throw 'RootDSE did not return defaultNamingContext.'
    }

    $NamingContext
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

    $Request = New-Object System.DirectoryServices.Protocols.SearchRequest(
        $SearchBase,
        $Filter,
        [System.DirectoryServices.Protocols.SearchScope]::Subtree,
        @('distinguishedName')
    )

    $Response = $Connection.SendRequest($Request)

    if ($Response.Entries.Count -eq 0) {
        throw "$Description was not found."
    }

    if ($Response.Entries.Count -gt 1) {
        throw "$Description returned multiple results."
    }

    $Response.Entries[0]
}

function Test-GroupMembership {
    param(
        [Parameter(Mandatory = $true)]
        $Connection,

        [Parameter(Mandatory = $true)]
        [string]$ComputerDN,

        [Parameter(Mandatory = $true)]
        [string]$GroupDN
    )

    $EscapedGroupDN = ConvertTo-LdapFilterValue -Value $GroupDN
    $Request = New-Object System.DirectoryServices.Protocols.SearchRequest(
        $ComputerDN,
        "(&(objectCategory=computer)(memberOf=$EscapedGroupDN))",
        [System.DirectoryServices.Protocols.SearchScope]::Base,
        @('distinguishedName')
    )

    $Response = $Connection.SendRequest($Request)
    $Response.Entries.Count -eq 1
}

function Invoke-MembershipAdd {
    param(
        [Parameter(Mandatory = $true)]
        $Connection,

        [Parameter(Mandatory = $true)]
        [string]$ComputerDN,

        [Parameter(Mandatory = $true)]
        [string]$GroupDN
    )

    $Change = New-Object System.DirectoryServices.Protocols.DirectoryAttributeModification
    $Change.Name = 'member'
    $Change.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Add
    [void]$Change.Add($ComputerDN)

    $Request = New-Object System.DirectoryServices.Protocols.ModifyRequest($GroupDN, $Change)

    try {
        [void]$Connection.SendRequest($Request)
    }
    catch [System.DirectoryServices.Protocols.DirectoryOperationException] {
        if ($_.Exception.Response.ResultCode -eq [System.DirectoryServices.Protocols.ResultCode]::AttributeOrValueExists) {
            Write-GroupLog -Level 'WARN' -Message 'The directory reported that the membership already exists.'
            return
        }
        throw
    }
}

function Test-StopRetry {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if ($ErrorRecord.Exception -is [System.DirectoryServices.Protocols.LdapException] -and
        $ErrorRecord.Exception.ErrorCode -eq 49) {
        return $true
    }

    if ($ErrorRecord.Exception -is [System.DirectoryServices.Protocols.DirectoryOperationException]) {
        $StopCodes = @(
            [System.DirectoryServices.Protocols.ResultCode]::InsufficientAccessRights,
            [System.DirectoryServices.Protocols.ResultCode]::InvalidCredentials,
            [System.DirectoryServices.Protocols.ResultCode]::ConstraintViolation,
            [System.DirectoryServices.Protocols.ResultCode]::ObjectClassViolation,
            [System.DirectoryServices.Protocols.ResultCode]::NamingViolation,
            [System.DirectoryServices.Protocols.ResultCode]::UnwillingToPerform
        )

        if ($ErrorRecord.Exception.Response.ResultCode -in $StopCodes) {
            return $true
        }
    }

    if ($ErrorRecord.Exception.Message -match 'invalid credentials|user name or password|access is denied|insufficient access|AD group .* was not found|multiple results') {
        return $true
    }

    $false
}

function Invoke-GroupAssignment {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$UseSsl,

        [Parameter(Mandatory = $true)]
        [int]$Passes,

        [Parameter(Mandatory = $true)]
        [int]$DelaySeconds
    )

    $Protocol = if ($UseSsl) { 'LDAPS' } else { 'LDAP' }
    $Port = if ($UseSsl) { 636 } else { 389 }
    $LastError = $null

    for ($Pass = 1; $Pass -le $Passes; $Pass++) {
        Write-GroupLog -Message "$Protocol pass $Pass of $Passes started."

        try {
            $DomainControllerList = Get-DomainControllerList
            Write-GroupLog -Message "Discovered domain controllers: $($DomainControllerList -join ', ')"
        }
        catch {
            $LastError = $_
            Write-GroupLog -Level 'WARN' -Message "Could not discover domain controllers: $($_.Exception.Message)"

            if ($Pass -lt $Passes) {
                Write-GroupLog -Level 'WARN' -Message "Waiting $DelaySeconds seconds before retry."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
            throw
        }

        foreach ($DomainController in $DomainControllerList) {
            try {
                Write-GroupLog -Message "Trying $Protocol connection to $DomainController on TCP $Port."
                if ($null -eq $script:NetworkCredential) {
                    throw 'NetworkCredential is null. Check that ADGroupUserName and ADGroupPassword were read correctly.'
                }
                $script:LdapConnection = Connect-LdapServer -Server $DomainController -AuthCredential $script:NetworkCredential -UseSsl $UseSsl
                Write-GroupLog -Message "$Protocol bind succeeded on $DomainController."

                $NamingContext = Get-DefaultNamingContext -Connection $script:LdapConnection
                Write-GroupLog -Message "Naming context: $NamingContext"

                $ComputerSam = ConvertTo-LdapFilterValue -Value "$script:ComputerName`$"
                $ComputerEntry = Find-LdapObject `
                    -Connection $script:LdapConnection `
                    -SearchBase $NamingContext `
                    -Filter "(&(objectCategory=computer)(sAMAccountName=$ComputerSam))" `
                    -Description "Computer account '$script:ComputerName'"

                $ComputerDN = Get-LdapAttributeValue -Entry $ComputerEntry -Name 'distinguishedName'
                if ([string]::IsNullOrWhiteSpace($ComputerDN)) {
                    throw 'The computer distinguished name is empty.'
                }
                Write-GroupLog -Message "Computer DN: $ComputerDN"

                $GroupSam = ConvertTo-LdapFilterValue -Value $script:GroupName
                $GroupEntry = Find-LdapObject `
                    -Connection $script:LdapConnection `
                    -SearchBase $NamingContext `
                    -Filter "(&(objectCategory=group)(sAMAccountName=$GroupSam))" `
                    -Description "AD group '$script:GroupName'"

                $GroupDN = Get-LdapAttributeValue -Entry $GroupEntry -Name 'distinguishedName'
                if ([string]::IsNullOrWhiteSpace($GroupDN)) {
                    throw 'The group distinguished name is empty.'
                }
                Write-GroupLog -Message "Group DN: $GroupDN"

                $AlreadyMember = Test-GroupMembership -Connection $script:LdapConnection -ComputerDN $ComputerDN -GroupDN $GroupDN

                if ($AlreadyMember) {
                    Write-GroupLog -Message 'Computer is already a direct member. No change needed.'
                }
                else {
                    Write-GroupLog -Message 'Computer is not a member. Adding computer to group.'
                    Invoke-MembershipAdd -Connection $script:LdapConnection -ComputerDN $ComputerDN -GroupDN $GroupDN
                    Write-GroupLog -Message 'Directory modification completed.'

                    $Verified = $false
                    for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
                        Write-GroupLog -Message "Membership verification attempt $Attempt of 3."
                        $Verified = Test-GroupMembership -Connection $script:LdapConnection -ComputerDN $ComputerDN -GroupDN $GroupDN
                        if ($Verified) { break }
                        if ($Attempt -lt 3) { Start-Sleep -Seconds 3 }
                    }

                    if (-not $Verified) {
                        throw 'Membership verification failed after the write.'
                    }
                    Write-GroupLog -Message 'Membership verification succeeded.'
                }

                if (-not (Test-GroupMembership -Connection $script:LdapConnection -ComputerDN $ComputerDN -GroupDN $GroupDN)) {
                    throw 'Final membership verification failed.'
                }

                Write-GroupLog -Message "Membership verified through $DomainController."

                if (-not $UseSsl) {
                    Write-GroupLog -Level 'WARN' -Message 'Operation succeeded using LDAP on TCP 389. Review LDAPS configuration.'
                }

                return $true
            }
            catch {
                $LastError = $_
                Write-GroupLog -Level 'WARN' -Message "$Protocol attempt on $DomainController failed: $($_.Exception.Message)"

                if (Test-StopRetry -ErrorRecord $_) {
                    $script:PermanentFailure = $true
                    Write-GroupLog -Level 'ERROR' -Message 'The error is not expected to be fixed by retrying.'
                    throw
                }
            }
            finally {
                if ($null -ne $script:LdapConnection) {
                    $script:LdapConnection.Dispose()
                    $script:LdapConnection = $null
                }
            }
        }

        if ($Pass -lt $Passes) {
            Write-GroupLog -Level 'WARN' -Message "All $Protocol attempts failed in pass $Pass of $Passes. Waiting $DelaySeconds seconds before retry."
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    if ($null -ne $LastError) {
        throw "$Protocol failed after $Passes pass(es). Last error: $($LastError.Exception.Message)"
    }

    throw "$Protocol failed after $Passes pass(es)."
}

try {
    Add-Type -AssemblyName System.DirectoryServices.Protocols
    Add-Type -AssemblyName System.DirectoryServices

    try {
        $TsEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment
    }
    catch {
        throw 'Could not create Microsoft.SMS.TSEnvironment. This script must run inside a ConfigMgr Task Sequence.'
    }

    Initialize-GroupLog
    Write-GroupLog -Message 'Add computer to AD group started.'
    Write-GroupLog -Message "Log file: $LogPath"
    Write-GroupLog -Message "Process identity: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-GroupLog -Message "Computer name: $ComputerName"
    Write-GroupLog -Message "Requested group: $GroupName"

    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        throw 'The local computer name could not be determined.'
    }

    $AdUserName = $TsEnvironment.Value($TsUserVariable)
    $AdPassword = $TsEnvironment.Value($TsPasswordVariable)

    if ([string]::IsNullOrWhiteSpace($AdUserName)) {
        throw "Task Sequence variable '$TsUserVariable' is empty."
    }

    if ([string]::IsNullOrWhiteSpace($AdPassword)) {
        throw "Task Sequence variable '$TsPasswordVariable' is empty."
    }

    Write-GroupLog -Message "Using AD account: $AdUserName"
    Write-GroupLog -Message 'Password was read from Task Sequence variable: ********'

    $SeparatorIndex = $AdUserName.IndexOf('\')

    if ($SeparatorIndex -gt 0 -and $SeparatorIndex -lt ($AdUserName.Length - 1)) {
        $AdDomain = $AdUserName.Substring(0, $SeparatorIndex)
        $AdAccount = $AdUserName.Substring($SeparatorIndex + 1)
        $script:NetworkCredential = New-Object System.Net.NetworkCredential($AdAccount, $AdPassword, $AdDomain)
    }
    else {
        $script:NetworkCredential = New-Object System.Net.NetworkCredential($AdUserName, $AdPassword)
    }

    $ComputerSystem = Get-CimInstance Win32_ComputerSystem
    if (-not $ComputerSystem.PartOfDomain) {
        throw 'The computer is not joined to an Active Directory domain.'
    }

    Write-GroupLog -Message "Computer domain: $($ComputerSystem.Domain)"

    try {
        if (Test-ComputerSecureChannel -ErrorAction Stop) {
            Write-GroupLog -Message 'Computer secure channel is operational.'
        }
        else {
            Write-GroupLog -Level 'WARN' -Message 'Computer secure channel test returned false. Continuing because explicit AD credentials are used.'
        }
    }
    catch {
        Write-GroupLog -Level 'WARN' -Message "Computer secure channel test failed: $($_.Exception.Message). Continuing because explicit AD credentials are used."
    }

    Invoke-GroupAssignment -UseSsl $true -Passes $MaxPasses -DelaySeconds $RetryDelaySeconds | Out-Null
    Write-GroupLog -Message 'Add computer to AD group completed successfully by using LDAPS.'
    $ExitCode = 0
}
catch {
    if ($AllowInsecureLdapFallback -and -not $PermanentFailure) {
        Write-GroupLog -Level 'WARN' -Message "LDAPS did not complete successfully: $($_.Exception.Message)"
        Write-GroupLog -Level 'WARN' -Message 'Insecure LDAP fallback is enabled. Trying LDAP on TCP 389.'

        try {
            Invoke-GroupAssignment -UseSsl $false -Passes 1 -DelaySeconds 0 | Out-Null
            Write-GroupLog -Level 'WARN' -Message 'Add computer to AD group completed successfully by using LDAP fallback.'
            $ExitCode = 0
        }
        catch {
            $ExitCode = 1
            Write-GroupLog -Level 'ERROR' -Message "LDAP fallback also failed: $($_.Exception.Message)"
            Write-GroupLog -Level 'ERROR' -Message "Exception type: $($_.Exception.GetType().FullName)"
            Write-GroupLog -Level 'ERROR' -Message "Script line: $($_.InvocationInfo.ScriptLineNumber)"
        }
    }
    else {
        $ExitCode = 1
        Write-GroupLog -Level 'ERROR' -Message "ERROR: $($_.Exception.Message)"
        Write-GroupLog -Level 'ERROR' -Message "Exception type: $($_.Exception.GetType().FullName)"
        Write-GroupLog -Level 'ERROR' -Message "Script line: $($_.InvocationInfo.ScriptLineNumber)"

        if ($PermanentFailure) {
            Write-GroupLog -Level 'ERROR' -Message 'LDAP fallback was skipped because the error is permanent.'
        }
        else {
            Write-GroupLog -Level 'ERROR' -Message 'LDAPS failed and LDAP fallback is not enabled.'
        }
    }
}
finally {
    if ($null -ne $LdapConnection) {
        $LdapConnection.Dispose()
    }

    if ($null -ne $TsEnvironment) {
        try {
            $TsEnvironment.Value($TsUserVariable) = ''
            $TsEnvironment.Value($TsPasswordVariable) = ''
            Write-GroupLog -Message 'Task Sequence credential variables cleared.'
        }
        catch {
            Write-GroupLog -Level 'WARN' -Message "Could not clear Task Sequence credential variables: $($_.Exception.Message)"
        }
    }

    $AdPassword = $null
    $AdUserName = $null
    $script:NetworkCredential = $null
    $TsEnvironment = $null

    Write-GroupLog -Message "Script exit code: $ExitCode"
}

exit $ExitCode
