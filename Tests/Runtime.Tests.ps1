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

    function Get-TestDirectoryResource {
        param([hashtable]$Property)

        $Resource = [pscustomobject]$Property
        $Resource | Add-Member NoteProperty DisposeCount 0
        $Resource | Add-Member ScriptMethod Dispose { $this.DisposeCount++ }
        return $Resource
    }

    function Get-TestDirectoryError {
        param(
            [DirectoryServices.Protocols.ResultCode]$Code,
            [Exception]$InnerException
        )
        # DirectoryResponse has no public constructor; build a real response without contacting AD.
        $Response = [Activator]::CreateInstance(
            [DirectoryServices.Protocols.ModifyResponse],
            [Reflection.BindingFlags]'Instance,NonPublic', $null,
            @('CN=Group-A,DC=contoso,DC=com', [DirectoryServices.Protocols.DirectoryControl[]]@(), $Code, 'test-only detail', [uri[]]@()),
            [Globalization.CultureInfo]::InvariantCulture)
        if ($null -ne $InnerException) {
            return [DirectoryServices.Protocols.DirectoryOperationException]::new($Response, 'test-only detail', $InnerException)
        }
        return [DirectoryServices.Protocols.DirectoryOperationException]::new($Response)
    }
}

Describe 'Entry-point parameter validation' {
    BeforeAll {
        # Bind the actual production parameters without executing the Task Sequence entry point.
        $script:ParameterBinding = [scriptblock]::Create($script:RuntimeAst.ParamBlock.Extent.Text + "`r`n'Bound'")
    }

    It 'rejects <Case> before initialization' -ForEach @(
        @{ Case = 'a null group'; Name = 'GroupName'; Value = $null }
        @{ Case = 'an empty group array'; Name = 'GroupName'; Value = @() }
        @{ Case = 'an empty group name'; Name = 'GroupName'; Value = @('') }
        @{ Case = 'a null array element'; Name = 'GroupName'; Value = @('Group-A', $null) }
        @{ Case = 'zero passes'; Name = 'RetryCount'; Value = 0 }
        @{ Case = 'eleven passes'; Name = 'RetryCount'; Value = 11 }
        @{ Case = 'a negative delay'; Name = 'RetryDelaySeconds'; Value = -1 }
        @{ Case = 'an excessive delay'; Name = 'RetryDelaySeconds'; Value = 3601 }
        @{ Case = 'an undersized timeout'; Name = 'TimeoutSeconds'; Value = 4 }
        @{ Case = 'an excessive timeout'; Name = 'TimeoutSeconds'; Value = 301 }
        @{ Case = 'explicit NTLM authentication'; Name = 'AuthenticationMode'; Value = 'Ntlm' }
        @{ Case = 'unprotected LDAP transport'; Name = 'DirectoryTransport'; Value = 'Ldap' }
    ) {
        $Parameters = @{ GroupName = @('Group-A') }
        $Parameters[$Name] = $Value
        { & $script:ParameterBinding @Parameters } | Should -Throw
    }

    It 'accepts the <Boundary> numeric limits' -ForEach @(
        @{ Boundary = 'minimum'; Passes = 1; Delay = 0; Timeout = 5 }
        @{ Boundary = 'maximum'; Passes = 10; Delay = 3600; Timeout = 300 }
    ) {
        & $script:ParameterBinding -GroupName 'Group-A' -RetryCount $Passes -RetryDelaySeconds $Delay -TimeoutSeconds $Timeout |
            Should -BeExactly 'Bound'
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

    It 'rejects RootDSE with <Count> entries and no usable naming context' -ForEach @(
        @{ Count = 0; Expected = 'RootDSE lookup failed.' }
        @{ Count = 2; Expected = 'RootDSE lookup failed.' }
        @{ Count = 1; Expected = 'RootDSE did not return defaultNamingContext.' }
    ) {
        $Entry = [pscustomobject]@{
            Attributes = @{ defaultNamingContext = [DirectoryServices.Protocols.DirectoryAttribute]::new() }
        }
        $Connection = Get-TestConnection
        $Entries = @(@($Entry, $Entry) | Select-Object -First $Count)
        $Connection.Responses.Enqueue([pscustomobject]@{ Entries = $Entries })
        { Get-DefaultNamingContext $Connection } | Should -Throw $Expected
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

Describe 'Domain controller discovery diagnostics' -Tag 'DiagnosticStreams' {
    BeforeAll {
        $Definition = $script:RuntimeAst.EndBlock.Statements |
            Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Get-DomainControllerName' }
        $DomainCalls = @($Definition.Body.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $Node.Static -and $Node.Member.Value -eq 'GetComputerDomain'
                }, $false))
        $DomainCalls.Count | Should -Be 1
        # Substitute only the static domain lookup; discovery, ordering, and logging remain production-sourced.
        $Body = $Definition.Body.Extent.Text
        $script:DiscoveryBody = [scriptblock]::Create(
            $Body.Substring(1, $Body.Length - 2).Replace($DomainCalls[0].Extent.Text, '(Get-TestComputerDomain)'))

        function Get-TestComputerDomain {
            return $script:DiscoveryDomain
        }
    }

    BeforeEach {
        $script:LogPath = Join-Path $TestDrive ('discovery-{0}.log' -f [guid]::NewGuid())
        $script:Component = 'AddComputerToADGroup'
        $script:DiscoveryDomain = Get-TestDirectoryResource @{ DomainControllers = @() }
        Mock Get-ComputerSiteName { return $script:DiscoverySite }
    }

    It 'returns only controller names with <Scenario>' -ForEach @(
        @{
            Scenario = 'an unknown site and two controllers'
            Site = $null
            ControllerCount = 2
            ExpectedNames = @('dc-a.contoso.com', 'dc-b.contoso.com')
            WarningCount = 1
        }
        @{
            Scenario = 'an unknown site and no controllers'
            Site = $null
            ControllerCount = 0
            ExpectedNames = @()
            WarningCount = 1
        }
        @{
            Scenario = 'a known site and two controllers'
            Site = 'HQ'
            ControllerCount = 2
            ExpectedNames = @('dc-b.contoso.com', 'dc-a.contoso.com')
            WarningCount = 0
        }
    ) {
        $script:DiscoverySite = $Site
        $script:DiscoveryDomain.DomainControllers = @(@(
                (Get-TestDirectoryResource @{ Name = 'dc-b.contoso.com'; SiteName = 'HQ' })
                (Get-TestDirectoryResource @{ Name = 'dc-a.contoso.com'; SiteName = 'Branch' })
            ) | Select-Object -First $ControllerCount)
        $Records = @(& $script:DiscoveryBody 3>&1)
        $Controllers = @($Records | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
        $Warnings = @($Records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $Controllers.Count | Should -Be $ControllerCount
        ($Controllers -join ',') | Should -BeExactly ($ExpectedNames -join ',')
        $Warnings.Count | Should -Be $WarningCount
        if ($WarningCount -gt 0) {
            $Warnings[0].Message | Should -BeExactly '[WARN] The local Active Directory site could not be determined; using name-ordered domain controller discovery.'
            (Get-Content -LiteralPath $script:LogPath -Raw) | Should -Match 'name-ordered domain controller discovery\..*type="2"'
        }
    }

    It 'disposes discovery objects after <Outcome>' -Tag 'ResourceDisposal' -ForEach @(
        @{ Outcome = 'successful ordering'; FailOrdering = $false }
        @{ Outcome = 'failed ordering'; FailOrdering = $true }
    ) {
        $script:DiscoverySite = 'HQ'
        $Controllers = @(
            (Get-TestDirectoryResource @{ Name = 'dc-b.contoso.com'; SiteName = 'HQ' })
            (Get-TestDirectoryResource @{ Name = 'dc-a.contoso.com'; SiteName = 'Branch' })
        )
        $script:DiscoveryDomain.DomainControllers = $Controllers
        if ($FailOrdering) {
            Mock Get-PreferredDomainControllerOrder { throw 'Test ordering failure.' }
            { & $script:DiscoveryBody } | Should -Throw '*ordering failure*'
        }
        else {
            (& $script:DiscoveryBody) | Should -Be @('dc-b.contoso.com', 'dc-a.contoso.com')
        }
        $script:DiscoveryDomain.DisposeCount | Should -Be 1
        foreach ($Controller in $Controllers) { $Controller.DisposeCount | Should -Be 1 }
    }

    It 'disposes the domain when controller enumeration fails' -Tag 'ResourceDisposal' {
        $script:DiscoverySite = 'HQ'
        function Get-TestControllerEnumeration { throw 'Test enumeration failure.' }
        # Replace the failing API boundary; PowerShell script-property getters suppress getter exceptions.
        $Body = [scriptblock]::Create($script:DiscoveryBody.ToString().Replace(
                '$Domain.DomainControllers', '(Get-TestControllerEnumeration)'))
        { & $Body } | Should -Throw '*enumeration failure*'
        $script:DiscoveryDomain.DisposeCount | Should -Be 1
    }
}

Describe 'Computer site resource ownership' -Tag 'ResourceDisposal' {
    BeforeAll {
        $Definition = $script:RuntimeAst.EndBlock.Statements |
            Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Get-ComputerSiteName' }
        $SiteCalls = @($Definition.Body.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $Node.Static -and $Node.Member.Value -eq 'GetComputerSite'
                }, $false))
        $SiteCalls.Count | Should -Be 1
        $Body = $Definition.Body.Extent.Text
        $script:SiteBody = [scriptblock]::Create(
            $Body.Substring(1, $Body.Length - 2).Replace($SiteCalls[0].Extent.Text, '(Get-TestComputerSite)'))

        function Get-TestComputerSite { return $script:DiscoverySiteObject }
    }

    It 'disposes the site when its name is <Outcome>' -ForEach @(
        @{ Outcome = 'readable'; FailName = $false }
        @{ Outcome = 'unreadable'; FailName = $true }
    ) {
        $script:DiscoverySiteObject = Get-TestDirectoryResource @{ Name = 'HQ' }
        if ($FailName) {
            $script:DiscoverySiteObject | Add-Member ScriptProperty Name { throw 'Test site name failure.' } -Force
            (& $script:SiteBody) | Should -BeNullOrEmpty
        }
        else { (& $script:SiteBody) | Should -BeExactly 'HQ' }
        $script:DiscoverySiteObject.DisposeCount | Should -Be 1
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
    It 'preserves LDAP code <Code> even when a wrapped exception has an inner cause' -Tag 'ExceptionClassification' -ForEach @(
        @{ Code = 49; Permanent = $true }
        @{ Code = 81; Permanent = $false }
    ) {
        $Connection = Get-TestConnection
        $Connection.Failure = [DirectoryServices.Protocols.LdapException]::new(
            $Code, 'test-only detail', [InvalidOperationException]::new('test-only-password'))
        $Failure = $null
        try { $Connection.Bind() } catch { $Failure = $_ }
        $Failure | Should -Not -BeNullOrEmpty
        Test-PermanentDirectoryError $Failure | Should -Be $Permanent
        Get-SafeErrorMessage $Failure | Should -BeExactly "LDAP error code $Code."
    }

    It 'preserves an insufficient-access response with an inner cause' -Tag 'ExceptionClassification' {
        $Connection = Get-TestConnection
        $Connection.Failure = Get-TestDirectoryError InsufficientAccessRights ([InvalidOperationException]::new('test-only-password'))
        $Failure = $null
        try { $Connection.Bind() } catch { $Failure = $_ }
        $Failure | Should -Not -BeNullOrEmpty
        Test-PermanentDirectoryError $Failure | Should -BeTrue
        Get-SafeErrorMessage $Failure | Should -BeExactly 'Directory result: InsufficientAccessRights.'
    }

    It 'preserves an attribute-exists race response with an inner cause' -Tag 'ExceptionClassification' {
        $Connection = Get-TestConnection
        $Connection.Failure = Get-TestDirectoryError AttributeOrValueExists ([InvalidOperationException]::new('test-only-password'))
        { Invoke-DirectMembershipAdd $Connection 'CN=Group' 'CN=PC' } | Should -Not -Throw
    }

    It 'does not let server text override a transient <Kind> code' -Tag 'ExceptionClassification' -ForEach @(
        @{ Kind = 'LDAP' }, @{ Kind = 'directory response' }
    ) {
        $Connection = Get-TestConnection
        $Text = "AD group 'Group-A' was not found."
        if ($Kind -eq 'LDAP') {
            $Connection.Failure = [DirectoryServices.Protocols.LdapException]::new(81, $Text)
        }
        else {
            $Connection.Failure = [DirectoryServices.Protocols.DirectoryOperationException]::new(
                (Get-TestDirectoryError Busy).Response, $Text)
        }
        $Failure = $null
        try { $Connection.Bind() } catch { $Failure = $_ }
        $Failure | Should -Not -BeNullOrEmpty
        Test-PermanentDirectoryError $Failure | Should -BeFalse
    }

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
        $script:ObservedCredential = $null
        $script:ObservedSecurePassword = $null
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

    AfterEach {
        if ($null -ne $script:ObservedCredential) { $script:ObservedCredential.Password.Dispose() }
        if ($null -ne $script:ObservedSecurePassword) { $script:ObservedSecurePassword.Dispose() }
    }

    It 'rejects WinPE before accessing Task Sequence credentials' {
        $OriginalDrive = $env:SystemDrive
        try {
            $env:SystemDrive = 'X:'
            (Invoke-TestScript)[-1] | Should -Be 1
        }
        finally { $env:SystemDrive = $OriginalDrive }
        Should -Invoke Get-TaskSequenceEnvironment -Times 0 -Exactly
        Should -Invoke Get-TaskSequenceVariable -Times 0 -Exactly
        Should -Invoke Connect-LdapServer -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'Windows PE is not supported'
    }

    It 'fails safely when the Task Sequence environment is unavailable' {
        Mock Get-TaskSequenceEnvironment {
            throw 'Microsoft.SMS.TSEnvironment is unavailable. Run this script inside an active ConfigMgr Task Sequence.'
        }
        (Invoke-TestScript)[-1] | Should -Be 1
        Should -Invoke Get-TaskSequenceVariable -Times 0 -Exactly
        Should -Invoke Connect-LdapServer -Times 0 -Exactly
    }

    It 'rejects whitespace-only groups without contacting LDAP' {
        (Invoke-TestScript -GroupName @(' ', "`t"))[-1] | Should -Be 1
        Should -Invoke Connect-LdapServer -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'No valid group names were provided'
    }

    It 'bounds empty domain-controller discovery and suppresses delays when configured' {
        Mock Get-DomainControllerName { @() }
        (Invoke-TestScript -RetryCount 3 -RetryDelaySeconds 0)[-1] | Should -Be 1
        Should -Invoke Get-DomainControllerName -Times 3 -Exactly
        Should -Invoke Connect-LdapServer -Times 0 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'No domain controllers were discovered'
        $script:LogEntries -join "`n" | Should -Match 'FailedTransient'
    }

    It 'retains completed groups while retrying only unresolved groups' {
        Mock Get-DomainControllerName { 'dc1.contoso.com' }
        $script:PendingLookups = 0
        Mock Find-LdapObject {
            $script:PendingLookups++
            if ($script:PendingLookups -lt 3) { throw [DirectoryServices.Protocols.LdapException]::new(81) }
            [pscustomobject]@{}
        } -ParameterFilter { $Description -eq "AD group 'Group-B'" }
        (Invoke-TestScript -GroupName @('Group-A', 'Group-B'))[-1] | Should -Be 0
        Should -Invoke Find-LdapObject -Times 1 -Exactly -ParameterFilter { $Description -eq "AD group 'Group-A'" }
        Should -Invoke Find-LdapObject -Times 3 -Exactly -ParameterFilter { $Description -eq "AD group 'Group-B'" }
        Should -Invoke Start-Sleep -Times 2 -Exactly
        $script:Connection.DisposeCount | Should -Be 3
    }

    It 'returns only final status and the test exit marker on the success stream' {
        $Output = @(Invoke-TestScript)
        $Output.Count | Should -Be 2
        $Output[0] | Should -BeExactly 'AD group operation completed successfully.'
        $Output[1] | Should -BeOfType [int]
        $Output[1] | Should -Be 0
    }

    It 'handles case-variant group duplicates once while retaining input order' -Tag 'GroupNormalization' {
        (Invoke-TestScript -GroupName @(' Group-B ', 'group-b', 'GROUP-A', 'group-a'))[-1] | Should -Be 0
        Should -Invoke Find-LdapObject -Times 3 -Exactly
        $Summaries = @($script:LogEntries | Where-Object { $_ -like '*Summary:*' })
        $Summaries.Count | Should -Be 2
        $Summaries[0] | Should -Match 'Group=Group-B;'
        $Summaries[1] | Should -Match 'Group=GROUP-A;'
    }

    It 'releases the secure credential after <Outcome>' -Tag 'ResourceDisposal' -ForEach @(
        @{ Outcome = 'success'; FailBind = $false; ExpectedExit = 0 }
        @{ Outcome = 'bind failure'; FailBind = $true; ExpectedExit = 1 }
    ) {
        $script:FailObservedBind = $FailBind
        Mock Connect-LdapServer {
            $script:ObservedCredential = $Credential
            if ($script:FailObservedBind) { throw [DirectoryServices.Protocols.LdapException]::new(49) }
            $script:Connection
        }
        (Invoke-TestScript)[-1] | Should -Be $ExpectedExit
        $script:ObservedCredential | Should -Not -BeNullOrEmpty
        { $Copy = $script:ObservedCredential.Password.Copy(); $Copy.Dispose() } | Should -Throw '*disposed*'
    }

    It 'releases the secure password if credential construction fails' -Tag 'ResourceDisposal' {
        Mock New-Object {
            $script:ObservedSecurePassword = $ArgumentList[1]
            throw [ArgumentException]::new('Test credential construction failure.')
        } -ParameterFilter { $TypeName -eq 'System.Management.Automation.PSCredential' }
        (Invoke-TestScript)[-1] | Should -Be 1
        $script:ObservedSecurePassword | Should -Not -BeNullOrEmpty
        { $Copy = $script:ObservedSecurePassword.Copy(); $Copy.Dispose() } | Should -Throw '*disposed*'
        Should -Invoke Connect-LdapServer -Times 0 -Exactly
    }

    It 'does not repeat a rejected bind when the LDAP exception has an inner cause' -Tag 'ExceptionClassification' {
        Mock Connect-LdapServer {
            throw [DirectoryServices.Protocols.LdapException]::new(
                49, 'test-only detail', [InvalidOperationException]::new('test-only-password'))
        }
        (Invoke-TestScript)[-1] | Should -Be 1
        Should -Invoke Connect-LdapServer -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
        $script:LogEntries -join "`n" | Should -Match 'LDAP error code 49'
        $script:LogEntries -join "`n" | Should -Not -Match 'test-only-password'
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

    It 'uses the Windows log fallback when the Task Sequence path is <State>' -ForEach @(
        @{ State = 'empty' }, @{ State = 'absent' }, @{ State = 'unreadable' }
    ) {
        $OriginalWindowsDirectory = $env:WINDIR
        try {
            $env:WINDIR = $script:TestLogFolder
            if ($State -eq 'unreadable') {
                $script:TaskSequenceEnvironment | Add-Member ScriptMethod Value { throw 'test-only-password' } -Force
            }
            elseif ($State -eq 'absent') {
                $script:TaskSequenceEnvironment.LogFolder = Join-Path $script:TestLogFolder 'absent'
            }
            else { $script:TaskSequenceEnvironment.LogFolder = '' }
            Initialize-Log
            $script:LogPath | Should -BeExactly (Join-Path $script:TestLogFolder 'Temp\AddComputerToADGroup.log')
            Test-Path -LiteralPath (Split-Path -Parent $script:LogPath) -PathType Container | Should -BeTrue
        }
        finally { $env:WINDIR = $OriginalWindowsDirectory }
    }

    It 'writes native one-line CMTrace records and neutralizes record terminators' {
        Write-Log -Message "Line1`r`nLine2]LOG]!>"
        $Lines = @(Get-Content -LiteralPath $script:LogPath)
        $Lines.Count | Should -Be 1
        $Lines[0] | Should -Match '^<!\[LOG\[Line1 Line2'
        $Lines[0] | Should -Match '\]LOG\]!><time="\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d+" date="\d{2}-\d{2}-\d{4}" component="AddComputerToADGroup" context="" type="1" thread="\d+" file="">$'
        ([regex]::Matches($Lines[0], '\]LOG\]!>')).Count | Should -Be 1
    }

    It 'keeps sanitized <Level> diagnostics visible outside the success stream' -Tag 'DiagnosticStreams' -ForEach @(
        @{ Level = 'WARN' }, @{ Level = 'ERROR' }
    ) {
        $Console = @(Write-Log -Level $Level -Message "Line1`r`nLine2]LOG]!>" -WarningVariable Diagnostics)
        $Console.Count | Should -Be 0
        $Diagnostics.Count | Should -Be 1
        $Diagnostics[0].Message | Should -BeExactly "[$Level] Line1 Line2]LOG removed>"
        $Diagnostics[0].Message | Should -Not -Match '\]LOG\]!>'
    }

    It 'keeps credential-bearing exception messages out of both dedicated and console logs' -Tag 'DiagnosticStreams' {
        try { throw [InvalidOperationException]::new('CONTOSO\test-account test-only-password') }
        catch { $Console = @(Write-Log -Level ERROR -Message (Get-SafeErrorMessage $_) -WarningVariable Diagnostics) }
        (Get-Content -LiteralPath $script:LogPath -Raw) | Should -Not -Match 'test-account|test-only-password'
        $Console.Count | Should -Be 0
        $Diagnostics.Count | Should -Be 1
        $Diagnostics[0].Message | Should -BeExactly '[ERROR] Operation failed (InvalidOperationException); raw exception details are omitted to protect credentials.'
    }

    It 'reports a safe computer lookup diagnostic for <Count> results' -Tag 'DiagnosticStreams' -ForEach @(
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
        $Console = @(Write-Log -Level ERROR -Message (Get-SafeErrorMessage $LookupError) -WarningVariable Diagnostics)
        (Get-Content -LiteralPath $script:LogPath -Raw) | Should -Match ([regex]::Escape($Expected))
        (Get-Content -LiteralPath $script:LogPath -Raw) | Should -Not -Match 'test-account|test-only-password'
        $Console.Count | Should -Be 0
        $Diagnostics.Count | Should -Be 1
        $Diagnostics[0].Message | Should -BeExactly "[ERROR] $Expected"
        $Diagnostics[0].Message | Should -Not -Match 'test-account|test-only-password'
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
