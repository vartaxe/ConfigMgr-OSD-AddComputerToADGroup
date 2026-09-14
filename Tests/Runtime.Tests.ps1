BeforeAll {
    Add-Type -AssemblyName System.DirectoryServices.Protocols
    $script:RuntimePath = Join-Path $PSScriptRoot '..\Scripts\Add-ComputerToADGroup.ps1'
    $script:RuntimeAst = [System.Management.Automation.Language.Parser]::ParseFile($script:RuntimePath, [ref]$null, [ref]$null)
    foreach ($Definition in $script:RuntimeAst.EndBlock.Statements) {
        if ($Definition -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            . ([scriptblock]::Create($Definition.Extent.Text))
        }
    }
    # Exercise the original orchestration with mocked boundaries, returning rather than exiting Pester.
    $script:RuntimeBody = [scriptblock]::Create((@(
        foreach ($Statement in $script:RuntimeAst.EndBlock.Statements) {
            if ($Statement -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $Statement -isnot [System.Management.Automation.Language.ExitStatementAst]) {
                $Statement.Extent.Text
            }
        }
        '$ExitCode'
    ) -join "`r`n"))

    function Invoke-TestScript {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'The production script block resolves these parameters from this caller scope.')]
        param(
            [string[]]$GroupName = @('Group-A'),
            [int]$RetryCount = 3,
            [int]$RetryDelaySeconds = 1,
            [int]$TimeoutSeconds = 5,
            [string]$AuthenticationMode = 'Kerberos',
            [string]$DirectoryTransport = 'LDAPS',
            [switch]$AllowNtlmV2
        )
        & $script:RuntimeBody
    }

    function Get-TestConnection {
        $Connection = [pscustomobject]@{
            AuthType = [DirectoryServices.Protocols.AuthType]::Anonymous
            Credential = $null
            Timeout = [timespan]::Zero
            SessionOptions = [pscustomobject]@{ ProtocolVersion = 0; SecureSocketLayer = $false; Signing = $false; Sealing = $false }
            BindCount = 0
            DisposeCount = 0
            Failure = $null
            Requests = [System.Collections.Generic.List[object]]::new()
            Responses = [System.Collections.Generic.Queue[object]]::new()
        }
        $Connection | Add-Member ScriptMethod Bind {
            $this.BindCount++
            if ($null -ne $this.Failure) { throw $this.Failure }
        }
        $Connection | Add-Member ScriptMethod Dispose { $this.DisposeCount++ }
        $Connection | Add-Member ScriptMethod SendRequest {
            $this.Requests.Add($args[0])
            if ($null -ne $this.Failure) { throw $this.Failure }
            return $this.Responses.Dequeue()
        }
        return $Connection
    }

    function Get-TestDirectoryError {
        param([DirectoryServices.Protocols.ResultCode]$Code)
        # DirectoryResponse has no public constructor; build a real response without contacting AD.
        $Response = [Activator]::CreateInstance(
            [DirectoryServices.Protocols.ModifyResponse],
            [Reflection.BindingFlags]'Instance,NonPublic', $null,
            @('CN=Group-A,DC=contoso,DC=com', [DirectoryServices.Protocols.DirectoryControl[]]@(), $Code, 'test-only detail', [uri[]]@()),
            [Globalization.CultureInfo]::InvariantCulture)
        return [DirectoryServices.Protocols.DirectoryOperationException]::new($Response)
    }
}

Describe 'LDAP filters and attributes' {
    It 'escapes NUL, parentheses, asterisk and backslash without damaging Unicode' {
        ConvertTo-LdapFilterValue ("a" + [char]0 + '(*\)' + [char]0x00e9) |
            Should -BeExactly ('a\00\28\2a\5c\29' + [char]0x00e9)
    }

    It 'decodes returned byte-valued directory attributes as strings' {
        $Attribute = [DirectoryServices.Protocols.DirectoryAttribute]::new()
        [void]$Attribute.Add([Text.Encoding]::UTF8.GetBytes('DC=contoso,DC=com'))
        $Entry = [pscustomobject]@{ Attributes = @{ defaultNamingContext = $Attribute } }
        Get-LdapAttributeValue $Entry 'defaultNamingContext' | Should -BeExactly 'DC=contoso,DC=com'
        Get-LdapAttributeValue $Entry 'missing' | Should -BeNullOrEmpty
    }

    It 'uses a base-scope escaped membership query' {
        $Connection = Get-TestConnection
        $Connection.Responses.Enqueue([pscustomobject]@{ Entries = @([pscustomobject]@{}) })
        Test-DirectMembership $Connection 'CN=Group,DC=contoso,DC=com' 'CN=PC*(A),DC=contoso,DC=com' | Should -BeTrue
        $Connection.Requests[0].Scope | Should -Be ([DirectoryServices.Protocols.SearchScope]::Base)
        $Connection.Requests[0].Filter | Should -BeExactly '(&(objectClass=group)(member=CN=PC\2a\28A\29,DC=contoso,DC=com))'
    }

    It 'reads RootDSE at base scope and searches for exactly one directory object' {
        $Attribute = [DirectoryServices.Protocols.DirectoryAttribute]::new()
        [void]$Attribute.Add('DC=contoso,DC=com')
        $Entry = [pscustomobject]@{ Attributes = @{ defaultNamingContext = $Attribute } }
        $Connection = Get-TestConnection
        $Connection.Responses.Enqueue([pscustomobject]@{ Entries = @($Entry) })
        Get-DefaultNamingContext $Connection | Should -BeExactly 'DC=contoso,DC=com'
        $Connection.Requests[0].DistinguishedName | Should -BeNullOrEmpty
        $Connection.Requests[0].Scope | Should -Be ([DirectoryServices.Protocols.SearchScope]::Base)
        $Connection.Responses.Enqueue([pscustomobject]@{ Entries = @($Entry) })
        Find-LdapObject $Connection 'DC=contoso,DC=com' '(sAMAccountName=Group-A)' 'AD group' | Should -Be $Entry
        $Connection.Requests[1].Scope | Should -Be ([DirectoryServices.Protocols.SearchScope]::Subtree)
    }

    It 'rejects missing or ambiguous group search results' {
        $Connection = Get-TestConnection
        $Connection.Responses.Enqueue([pscustomobject]@{ Entries = @() })
        { Find-LdapObject $Connection 'DC=contoso,DC=com' '(sAMAccountName=Group-A)' "AD group 'Group-A'" } |
            Should -Throw "*was not found*"
        $Connection.Responses.Enqueue([pscustomobject]@{ Entries = @([pscustomobject]@{}, [pscustomobject]@{}) })
        { Find-LdapObject $Connection 'DC=contoso,DC=com' '(sAMAccountName=Group-A)' "AD group 'Group-A'" } |
            Should -Throw "*returned multiple results*"
    }

    It 'sends exactly one add for exactly one member' {
        $Connection = Get-TestConnection
        $Connection.Responses.Enqueue($null)
        Invoke-DirectMembershipAdd $Connection 'CN=Group,DC=contoso,DC=com' 'CN=PC,DC=contoso,DC=com'
        $Connection.Requests.Count | Should -Be 1
        $Request = $Connection.Requests[0]
        $Request.Modifications.Count | Should -Be 1
        $Request.Modifications[0].Name | Should -BeExactly 'member'
        $Request.Modifications[0].Operation | Should -Be ([DirectoryServices.Protocols.DirectoryAttributeOperation]::Add)
        $Request.Modifications[0][0] | Should -BeExactly 'CN=PC,DC=contoso,DC=com'
    }

    It 'tolerates an attribute-exists race but propagates other modification errors' {
        $Connection = Get-TestConnection
        $Connection.Failure = Get-TestDirectoryError AttributeOrValueExists
        { Invoke-DirectMembershipAdd $Connection 'CN=Group' 'CN=PC' } | Should -Not -Throw
        $Connection.Failure = Get-TestDirectoryError InsufficientAccessRights
        { Invoke-DirectMembershipAdd $Connection 'CN=Group' 'CN=PC' } | Should -Throw
    }
}

Describe 'Domain controller preference' {
    BeforeAll {
        function Get-TestController {
            param([string]$Name, [string]$Site)
            $Controller = [pscustomobject]@{ Name = $Name }
            if ($PSBoundParameters.ContainsKey('Site')) {
                $Controller | Add-Member NoteProperty SiteName $Site
            }
            return $Controller
        }
    }

    It 'puts local-site controllers first, then the rest, each sorted by name' {
        $Controllers = @(
            (Get-TestController 'dc-remote-b.contoso.com' 'Branch')
            (Get-TestController 'dc-local-b.contoso.com' 'HQ')
            (Get-TestController 'dc-remote-a.contoso.com' 'Branch')
            (Get-TestController 'dc-local-a.contoso.com' 'HQ')
        )
        Get-PreferredDomainControllerOrder -Controller $Controllers -SiteName 'HQ' |
            Should -Be @('dc-local-a.contoso.com', 'dc-local-b.contoso.com', 'dc-remote-a.contoso.com', 'dc-remote-b.contoso.com')
    }

    It 'keeps every discovered controller reachable as failover rather than filtering by site' {
        $Controllers = @((Get-TestController 'dc2.contoso.com' 'Branch'), (Get-TestController 'dc1.contoso.com' 'HQ'))
        @(Get-PreferredDomainControllerOrder -Controller $Controllers -SiteName 'HQ').Count | Should -Be 2
    }

    It 'falls back to name order when the local site is <Reason>' -ForEach @(
        @{ Reason = 'unknown'; Site = $null }, @{ Reason = 'empty'; Site = '' }, @{ Reason = 'unmatched'; Site = 'Nowhere' }
    ) {
        $Controllers = @((Get-TestController 'dc2.contoso.com' 'HQ'), (Get-TestController 'dc1.contoso.com' 'Branch'))
        Get-PreferredDomainControllerOrder -Controller $Controllers -SiteName $Site |
            Should -Be @('dc1.contoso.com', 'dc2.contoso.com')
    }

    It 'matches site names case-insensitively and lowercases controller names' {
        Get-PreferredDomainControllerOrder -Controller @((Get-TestController 'DC2.CONTOSO.COM' 'Branch'), (Get-TestController 'DC1.CONTOSO.COM' 'hq')) -SiteName 'HQ' |
            Should -Be @('dc1.contoso.com', 'dc2.contoso.com')
    }

    It 'treats a controller without a readable site as remote instead of dropping it' {
        Get-PreferredDomainControllerOrder -Controller @((Get-TestController 'dc-nosite.contoso.com'), (Get-TestController 'dc-local.contoso.com' 'HQ')) -SiteName 'HQ' |
            Should -Be @('dc-local.contoso.com', 'dc-nosite.contoso.com')
    }

    It 'removes duplicates and ignores null or unnamed entries' {
        $Controllers = @(
            (Get-TestController 'dc1.contoso.com' 'HQ')
            (Get-TestController 'DC1.contoso.com' 'HQ')
            $null
            (Get-TestController '   ' 'HQ')
            (Get-TestController 'dc2.contoso.com' 'Branch')
        )
        Get-PreferredDomainControllerOrder -Controller $Controllers -SiteName 'HQ' |
            Should -Be @('dc1.contoso.com', 'dc2.contoso.com')
    }

    It 'returns an empty collection when nothing was discovered' {
        @(Get-PreferredDomainControllerOrder -Controller @() -SiteName 'HQ').Count | Should -Be 0
    }
}

Describe 'LDAP connection security' {
    BeforeEach {
        $script:Connection = Get-TestConnection
        $Secret = [Security.SecureString]::new()
        foreach ($Character in 'test-only-password'.ToCharArray()) { $Secret.AppendChar($Character) }
        $script:TestCredential = [pscredential]::new('CONTOSO\test-account', $Secret)
        Mock New-Object {
            $script:Identifier = $ArgumentList[0]
            $script:Connection
        } -ParameterFilter { $TypeName -eq 'DirectoryServices.Protocols.LdapConnection' }
    }

    It 'uses Kerberos over LDAPS 636 without a certificate override' {
        $Result = Connect-LdapServer 'dc1.contoso.com' $script:TestCredential 5 Kerberos LDAPS
        $script:Identifier.PortNumber | Should -Be 636
        $Result.AuthType | Should -Be ([DirectoryServices.Protocols.AuthType]::Kerberos)
        $Result.SessionOptions.SecureSocketLayer | Should -BeTrue
        $Result.SessionOptions.ProtocolVersion | Should -Be 3
        $Result.Timeout.TotalSeconds | Should -Be 5
        $Result.BindCount | Should -Be 1
        $Result.Credential.Domain | Should -BeExactly 'CONTOSO'
        $Result.Credential.UserName | Should -BeExactly 'test-account'
    }

    It 'requires both signing and sealing for SignedLdap 389' {
        $Result = Connect-LdapServer 'dc1.contoso.com' $script:TestCredential 5 Negotiate SignedLdap
        $script:Identifier.PortNumber | Should -Be 389
        $Result.AuthType | Should -Be ([DirectoryServices.Protocols.AuthType]::Negotiate)
        $Result.SessionOptions.SecureSocketLayer | Should -BeFalse
        $Result.SessionOptions.Signing | Should -BeTrue
        $Result.SessionOptions.Sealing | Should -BeTrue
    }

    It 'disposes a failed bind and does not fall back to another authentication or transport' {
        $script:Connection.Failure = [DirectoryServices.Protocols.LdapException]::new(49)
        { Connect-LdapServer 'dc1.contoso.com' $script:TestCredential 5 Kerberos LDAPS } | Should -Throw
        $script:Connection.BindCount | Should -Be 1
        $script:Connection.DisposeCount | Should -Be 1
    }
}

Describe 'Permanent and transient errors' {
    It 'recognizes wrapped LDAP permanent error <Code>' -ForEach @(8, 13, 19, 34, 49, 50, 53, 64, 65, 67 | ForEach-Object { @{ Code = $_ } }) {
        $Connection = Get-TestConnection
        $Connection.Failure = [DirectoryServices.Protocols.LdapException]::new($Code)
        try { $Connection.Bind() } catch { Test-PermanentDirectoryError $_ | Should -BeTrue }
    }

    It 'keeps wrapped transient LDAP error <Code> retryable' -ForEach @(51, 52, 81, 85, 91 | ForEach-Object { @{ Code = $_ } }) {
        $Connection = Get-TestConnection
        $Connection.Failure = [DirectoryServices.Protocols.LdapException]::new($Code)
        try { $Connection.Bind() } catch { Test-PermanentDirectoryError $_ | Should -BeFalse }
    }

    It 'recognizes a wrapped insufficient-access directory response' {
        $Connection = Get-TestConnection
        $Connection.Failure = Get-TestDirectoryError InsufficientAccessRights
        try { $Connection.Bind() } catch { Test-PermanentDirectoryError $_ | Should -BeTrue }
    }

    It 'does not throw when a directory exception has no response' {
        try { throw [DirectoryServices.Protocols.DirectoryOperationException]::new() }
        catch { Test-PermanentDirectoryError $_ | Should -BeFalse }
    }

    It 'does not classify arbitrary server error text as a permanent credential failure' {
        try { throw [DirectoryServices.Protocols.LdapException]::new(81, 'invalid credentials in a remote message') }
        catch { Test-PermanentDirectoryError $_ | Should -BeFalse }
    }
}

Describe 'Orchestration with mocked Task Sequence and LDAP boundaries' {
    BeforeEach {
        $script:LogEntries = [System.Collections.Generic.List[string]]::new()
        $script:Connection = Get-TestConnection
        Mock Get-TaskSequenceEnvironment { [pscustomobject]@{} }
        Mock Initialize-Log {}
        Mock Write-Log { $script:LogEntries.Add("$Level $Message") }
        Mock Get-TaskSequenceVariable {
            if ($Name -eq 'ADGroupUserName') { 'CONTOSO\test-account' } else { 'test-only-password' }
        }
        Mock Test-ComputerSecureChannel { $true }
        Mock Get-DomainControllerName { 'dc1.contoso.com'; 'dc2.contoso.com' }
        Mock Connect-LdapServer { $script:Connection }
        Mock Get-DefaultNamingContext { 'DC=contoso,DC=com' }
        Mock Find-LdapObject { [pscustomobject]@{} }
        Mock Get-LdapAttributeValue { 'CN=Test,DC=contoso,DC=com' }
        Mock Test-DirectMembership { $true }
        Mock Invoke-DirectMembershipAdd {}
        Mock Start-Sleep {}
        Mock Get-ItemProperty { [pscustomobject]@{ LmCompatibilityLevel = 5 } }
    }

    It 'handles multiple groups, trims duplicates and looks up the computer-account name' {
        (Invoke-TestScript -GroupName @(' Group-A ', 'Group-A', 'Group-B'))[-1] | Should -Be 0
        Should -Invoke Find-LdapObject -Times 3 -Exactly
        Should -Invoke Find-LdapObject -Times 1 -Exactly -ParameterFilter {
            $Filter -ceq ('(&(objectCategory=computer)(sAMAccountName={0}))' -f ($env:COMPUTERNAME + '$'))
        }
        Should -Invoke Get-TaskSequenceVariable -Times 2 -Exactly
        Should -Invoke Connect-LdapServer -Times 1 -Exactly -ParameterFilter { $Authentication -eq 'Kerberos' -and $Transport -eq 'LDAPS' }
        Should -Invoke Get-ItemProperty -Times 0 -Exactly
        Should -Invoke Invoke-DirectMembershipAdd -Times 0 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
        $script:Connection.DisposeCount | Should -Be 1
    }

    It 'escapes group input when constructing its filter' {
        (Invoke-TestScript -GroupName 'Group*(A)')[-1] | Should -Be 0
        Should -Invoke Find-LdapObject -Times 1 -Exactly -ParameterFilter {
            $Filter -ceq '(&(objectCategory=group)(sAMAccountName=Group\2a\28A\29))'
        }
    }

    It 'adds missing membership once and verifies before success' {
        $script:MembershipChecks = 0
        Mock Test-DirectMembership { $script:MembershipChecks++; $script:MembershipChecks -gt 1 }
        (Invoke-TestScript)[-1] | Should -Be 0
        Should -Invoke Test-DirectMembership -Times 2 -Exactly
        Should -Invoke Invoke-DirectMembershipAdd -Times 1 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'AddedAndVerified'
    }

    It 'fails when a modification is not verified' {
        Mock Test-DirectMembership { $false }
        (Invoke-TestScript -RetryCount 1)[-1] | Should -Be 1
        $script:LogEntries -join "`n" | Should -Not -Match 'AddedAndVerified'
        $script:LogEntries -join "`n" | Should -Match 'Membership verification failed'
    }

    It 'tries the next DC after a transient bind failure' {
        Mock Connect-LdapServer {
            if ($Server -eq 'dc1.contoso.com') { throw [DirectoryServices.Protocols.LdapException]::new(81) }
            $script:Connection
        }
        (Invoke-TestScript)[-1] | Should -Be 0
        Should -Invoke Connect-LdapServer -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'bounds transient retries to passes times discovered DCs' {
        Mock Connect-LdapServer { throw [DirectoryServices.Protocols.LdapException]::new(81) }
        (Invoke-TestScript -RetryCount 3 -RetryDelaySeconds 2)[-1] | Should -Be 1
        Should -Invoke Connect-LdapServer -Times 6 -Exactly
        Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 2 }
    }

    It 'tries the next DC when the computer account is not yet visible' {
        $script:ComputerLookups = 0
        Mock Find-LdapObject {
            if ($Description -like 'Computer account *') {
                $script:ComputerLookups++
                if ($script:ComputerLookups -eq 1) { throw "$Description was not found." }
            }
            [pscustomobject]@{}
        }
        (Invoke-TestScript)[-1] | Should -Be 0
        Should -Invoke Connect-LdapServer -Times 2 -Exactly
        Should -Invoke Test-DirectMembership -Times 1 -Exactly
        Should -Invoke Invoke-DirectMembershipAdd -Times 0 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'Computer account was not found\.'
    }

    It 'bounds missing computer account retries and reports the lookup failure' {
        Mock Find-LdapObject { throw "$Description was not found." } -ParameterFilter {
            $Description -like 'Computer account *'
        }
        (Invoke-TestScript -RetryCount 2)[-1] | Should -Be 1
        Should -Invoke Connect-LdapServer -Times 4 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly
        Should -Invoke Invoke-DirectMembershipAdd -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'Computer account was not found\.'
        $script:LogEntries -join "`n" | Should -Match 'FailedTransient'
    }

    It 'bounds readiness retries without contacting LDAP' {
        Mock Test-ComputerSecureChannel { $false }
        (Invoke-TestScript -RetryCount 3)[-1] | Should -Be 1
        Should -Invoke Test-ComputerSecureChannel -Times 3 -Exactly
        Should -Invoke Connect-LdapServer -Times 0 -Exactly
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'does not retry wrapped invalid credentials or log the raw credential-bearing error' {
        Mock Connect-LdapServer {
            $script:Connection.Failure = [DirectoryServices.Protocols.LdapException]::new(49, 'CONTOSO\test-account test-only-password')
            $script:Connection.Bind()
        }
        (Invoke-TestScript)[-1] | Should -Be 1
        Should -Invoke Connect-LdapServer -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'LDAP error code 49'
        $script:LogEntries -join "`n" | Should -Not -Match 'test-account|test-only-password'
    }

    It 'does not retry a missing group but completes the other groups' {
        Mock Find-LdapObject {
            if ($Description -eq "AD group 'Group-A'") { throw "AD group 'Group-A' was not found." }
            [pscustomobject]@{}
        }
        (Invoke-TestScript -GroupName @('Group-A', 'Group-B'))[-1] | Should -Be 1
        Should -Invoke Find-LdapObject -Times 1 -Exactly -ParameterFilter { $Description -eq "AD group 'Group-A'" }
        Should -Invoke Start-Sleep -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'Group=Group-B; Result=AlreadyMember'
    }

    It 'does not retry a permanent delegated-permission failure' {
        Mock Test-DirectMembership { $false }
        Mock Invoke-DirectMembershipAdd { throw (Get-TestDirectoryError InsufficientAccessRights) }
        (Invoke-TestScript)[-1] | Should -Be 1
        Should -Invoke Invoke-DirectMembershipAdd -Times 1 -Exactly
        Should -Invoke Connect-LdapServer -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'InsufficientAccessRights'
    }

    It 'rechecks membership on retry without re-adding after a lost verification response' {
        Mock Get-DomainControllerName { 'dc1.contoso.com' }
        $script:MembershipChecks = 0
        Mock Test-DirectMembership {
            $script:MembershipChecks++
            if ($script:MembershipChecks -eq 1) { return $false }
            if ($script:MembershipChecks -eq 2) { throw [DirectoryServices.Protocols.LdapException]::new(81) }
            return $true
        }
        (Invoke-TestScript)[-1] | Should -Be 0
        Should -Invoke Invoke-DirectMembershipAdd -Times 1 -Exactly
        Should -Invoke Test-DirectMembership -Times 3 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly
    }

    It 'blocks Negotiate without explicit permission before reading credentials or binding' {
        (Invoke-TestScript -AuthenticationMode Negotiate)[-1] | Should -Be 1
        Should -Invoke Get-TaskSequenceVariable -Times 0 -Exactly
        Should -Invoke Connect-LdapServer -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'requires explicit -AllowNtlmV2'
    }

    It 'blocks unconfigured or unsafe NTLM policy <Level>' -ForEach @(
        @{ Level = $null }, @{ Level = 0 }, @{ Level = 1 }, @{ Level = 2 }, @{ Level = 6 }, @{ Level = '5' }
    ) {
        $script:PolicyLevel = $Level
        Mock Get-ItemProperty {
            if ($null -eq $script:PolicyLevel) { [pscustomobject]@{} }
            else { [pscustomobject]@{ LmCompatibilityLevel = $script:PolicyLevel } }
        }
        (Invoke-TestScript -AuthenticationMode Negotiate -AllowNtlmV2)[-1] | Should -Be 1
        Should -Invoke Connect-LdapServer -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'LmCompatibilityLevel of 3, 4, or 5'
    }

    It 'allows explicit compatibility with policy <Level> and logs both modes' -ForEach @(
        @{ Level = 3 }, @{ Level = 4 }, @{ Level = 5 }
    ) {
        $script:PolicyLevel = $Level
        Mock Get-ItemProperty { [pscustomobject]@{ LmCompatibilityLevel = $script:PolicyLevel } }
        (Invoke-TestScript -AuthenticationMode Negotiate -AllowNtlmV2 -DirectoryTransport SignedLdap)[-1] | Should -Be 0
        Should -Invoke Connect-LdapServer -Times 1 -Exactly -ParameterFilter { $Authentication -eq 'Negotiate' -and $Transport -eq 'SignedLdap' }
        $script:LogEntries -join "`n" | Should -Match 'WARN Compatibility enabled: Negotiate'
        $script:LogEntries -join "`n" | Should -Match 'WARN Compatibility enabled: SignedLdap'
    }
}

Describe 'Dedicated logging and credential boundaries' {
    BeforeEach {
        $script:TestLogFolder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        [void](New-Item -Path $script:TestLogFolder -ItemType Directory)
        $script:LogPath = Join-Path $script:TestLogFolder 'AddComputerToADGroup.log'
        $script:Component = 'AddComputerToADGroup'
        $script:TaskSequenceEnvironment = [pscustomobject]@{ LogFolder = $script:TestLogFolder }
        $script:TaskSequenceEnvironment | Add-Member ScriptMethod Value { return $this.LogFolder }
    }

    It 'prefers _SMSTSLogPath' {
        Initialize-Log
        $script:LogPath | Should -BeExactly (Join-Path $script:TestLogFolder 'AddComputerToADGroup.log')
    }

    It 'writes native one-line CMTrace records and neutralizes record terminators' {
        Write-Log -Message "Line1`r`nLine2]LOG]!>"
        $Lines = @(Get-Content -LiteralPath $script:LogPath)
        $Lines.Count | Should -Be 1
        $Lines[0] | Should -Match '^<!\[LOG\[Line1 Line2'
        $Lines[0] | Should -Match '\]LOG\]!><time="\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d+" date="\d{2}-\d{2}-\d{4}" component="AddComputerToADGroup" context="" type="1" thread="\d+" file="">$'
        ([regex]::Matches($Lines[0], '\]LOG\]!>')).Count | Should -Be 1
    }

    It 'uses the sanitized message for warning and error output' {
        $Console = @(Write-Log -Level WARN -Message "Line1`r`nLine2]LOG]!>")
        $Console.Count | Should -Be 1
        $Console[0] | Should -BeExactly '[WARN] Line1 Line2]LOG removed>'
        $Console[0] | Should -Not -Match '\]LOG\]!>'
    }

    It 'keeps credential-bearing exception messages out of both dedicated and console logs' {
        try { throw [InvalidOperationException]::new('CONTOSO\test-account test-only-password') }
        catch { $Console = Write-Log -Level ERROR -Message (Get-SafeErrorMessage $_) }
        (Get-Content -LiteralPath $script:LogPath -Raw) | Should -Not -Match 'test-account|test-only-password'
        $Console | Should -Not -Match 'test-account|test-only-password'
    }

    It 'reports a safe computer lookup diagnostic for <Count> results' -ForEach @(
        @{ Count = 0; Expected = 'Computer account was not found.' },
        @{ Count = 2; Expected = 'Computer account returned multiple results.' }
    ) {
        $Connection = Get-TestConnection
        $Connection.Responses.Enqueue([pscustomobject]@{ Entries = @(@(1, 2) | Select-Object -First $Count) })
        $LookupError = $null
        try {
            $null = Find-LdapObject $Connection 'DC=contoso,DC=com' '(objectCategory=computer)' "Computer account 'CONTOSO\test-account test-only-password'"
        }
        catch { $LookupError = $_ }
        $LookupError | Should -Not -BeNullOrEmpty
        Get-SafeErrorMessage $LookupError | Should -BeExactly $Expected
        $Console = Write-Log -Level ERROR -Message (Get-SafeErrorMessage $LookupError)
        (Get-Content -LiteralPath $script:LogPath -Raw) | Should -Match ([regex]::Escape($Expected))
        (Get-Content -LiteralPath $script:LogPath -Raw) | Should -Not -Match 'test-account|test-only-password'
        $Console | Should -Not -Match 'test-account|test-only-password'
        if ($Count -eq 0) { Test-PermanentDirectoryError $LookupError | Should -BeFalse }
    }

    It 'surfaces log write failures without echoing raw exception details' {
        Mock Add-Content { throw 'test-only-password' }
        Mock Write-Warning {}
        Write-Log -Message 'Safe status'
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -notmatch 'test-only-password' }
    }

    It 'reads the named custom variable and rejects an empty credential without disclosing its value' {
        $Environment = [pscustomobject]@{}
        $Environment | Add-Member ScriptMethod Value { return '' }
        { Get-TaskSequenceVariable $Environment 'ADGroupPassword' } | Should -Throw "*'ADGroupPassword' is empty*"
    }
}
