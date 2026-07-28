<h1 align="center">ConfigMgr OSD Add Computer to AD Group</h1>

<p align="center">
  Add the local computer account to an Active Directory group securely during a Microsoft Configuration Manager OSD Task Sequence.
</p>

<p align="center">
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell&logoColor=white">
  <img alt="ConfigMgr OSD" src="https://img.shields.io/badge/ConfigMgr-OSD-0078D4">
  <img alt="Version" src="https://img.shields.io/badge/Version-1.0.0-brightgreen">
  <img alt="LDAPS default" src="https://img.shields.io/badge/LDAP-LDAPS%20default-success">
  <img alt="License" src="https://img.shields.io/github/license/vartaxe/ConfigMgr-OSD-AddComputerToADGroup">
</p>

<p align="center">
  <a href="#quick-start"><strong>Quick Start</strong></a> ·
  <a href="#security-notes"><strong>Security</strong></a> ·
  <a href="#troubleshooting"><strong>Troubleshooting</strong></a>
</p>

---

PowerShell script for Microsoft Configuration Manager OSD Task Sequences.

The script runs as `SYSTEM` and adds the local computer account to an Active Directory group by using a delegated account stored in custom Task Sequence variables.

## Current version

```text
Version: 1.0.0
Release date: 2026-07-28
Script SHA256: 3D9CCBC1829E299C5542B4447D72A9EA4FAD76435ED6E79D9E75A64C0C7A13B9
```

## Features

- Reads `ADGroupUserName` and `ADGroupPassword` from the running Task Sequence.
- Uses LDAPS on TCP 636 by default.
- Discovers domain controllers automatically.
- Finds the local computer and target group by `sAMAccountName`.
- Checks direct membership before making a change.
- Adds the computer only when needed.
- Verifies membership before returning success.
- Retries temporary failures three times with five-minute intervals.
- Clears the credential variables before exit.
- Writes a dedicated log and sends the same messages to Task Sequence output.
- Supports optional LDAP fallback on TCP 389.

## Requirements

- Microsoft Configuration Manager Task Sequence.
- Full Windows operating system phase, not WinPE.
- Computer joined to Active Directory and restarted after domain join.
- LDAPS enabled on the domain controllers.
- The client trusts the domain controller LDAPS certificate chain.
- A delegated AD account with permission to update the target group.

## Quick Start

### 1. Delegate Active Directory permissions

On the target group, grant the delegated account:

```text
Read Members
Write Members
Applies to: This object only
```

Do not grant Domain Admin, Account Operator, Full Control, Write all properties, Modify permissions, or broad OU permissions.

### 2. Set Task Sequence variables

Create a **Set Dynamic Variables** step before the script step:

```text
ADGroupUserName = CONTOSO\sa-configmgr-adgroups
ADGroupPassword = <password>
```

Configure `ADGroupPassword` with **Do not display this value**.

### 3. Run the PowerShell script

Run the script after:

```text
Setup Windows and ConfigMgr
Restart Computer
```

Do not run the script in WinPE.

Recommended **Run PowerShell Script** settings:

```text
PowerShell execution policy: Bypass
Output to task sequence variable: empty
Start in: empty
Time-out: 20 minutes
Run this step as the following account: unchecked
Continue on error: unchecked
Success codes: 0
```

Parameters:

```powershell
-GroupName "Workstation-Certificate-AutoEnroll"
```

Do not pass credentials in the parameter field.

## Optional parameters

Custom log file name:

```powershell
-GroupName "Workstation-Certificate-AutoEnroll" -LogFileName "AddComputerToADGroup.log"
```

Optional LDAP fallback:

```powershell
-GroupName "Workstation-Certificate-AutoEnroll" -AllowInsecureLdapFallback
```

LDAP fallback is disabled by default.

## Retry behavior

The script performs three passes. Each pass tries every discovered domain controller. It waits five minutes between passes. With three passes there are two waits, so a 20-minute timeout leaves margin for connection attempts and verification.

## Logging

The default log is `AddComputerToADGroup.log`. The script first uses `_SMSTSLogPath`, then falls back to `C:\Windows\CCM\Logs`.

Messages are also sent through `Write-Output`.

## Troubleshooting

### Old cached package

If ConfigMgr still runs an older script, replace the package source file, update the Distribution Points, and confirm that the client receives the new package revision.

### Generic exit code 16389

Exit code `16389` is often only a Task Sequence wrapper failure. Review the step output, `smsts.log`, and `AddComputerToADGroup.log` for the underlying error.

### Garbled console output

Some ConfigMgr status-message views can display duplicated PowerShell output as unreadable Unicode characters. This is a display issue and does not change the script result. Use the readable action output, `smsts.log`, and `AddComputerToADGroup.log` as the authoritative logs.

### Verify membership manually

```powershell
Get-ADComputer 'PC-CONTOSO-01' -Properties MemberOf |
    Select-Object -ExpandProperty MemberOf
```

```powershell
Get-ADGroupMember -Identity 'Workstation-Certificate-AutoEnroll' |
    Where-Object { $_.SamAccountName -eq 'PC-CONTOSO-01$' }
```

> [!IMPORTANT]
> Before sharing logs or screenshots, remove domain names, computer names, account names, distinguished names, server names, package IDs, deployment IDs, and all credential-related values.

## Exit codes

```text
0 = Membership verified successfully.
1 = Membership not verified.
```

A computer that is already a direct member also returns `0` after verification.

## Local validation

```powershell
$Path = '.\Scripts\Add-ComputerToADGroup.ps1'
Unblock-File -Path $Path
$ScriptText = Get-Content -Path $Path -Raw
$Tokens = $null
$Errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$Tokens, [ref]$Errors)
$Errors | Format-List *
```

Expected: no output.

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path $Path -Severity Warning,Error
```

Expected: no output.

## Security notes

- The password is never written to the script log.
- A masked Task Sequence variable is not a dedicated secret vault.
- Use a least-privileged delegated account.
- LDAPS certificate validation is not bypassed.
- LDAP fallback is disabled by default.
- Report potential security vulnerabilities privately through GitHub's security reporting features rather than opening a public issue.

## Contact

For questions, issues, or suggestions, please use GitHub Issues:

https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/issues

Maintainer: [@vartaxe](https://github.com/vartaxe)

## Support

If this project saves you time, you can optionally support its continued maintenance through GitHub Sponsors:

https://github.com/sponsors/vartaxe

Sponsorship is entirely optional. This project remains free and open source under the MIT License.

## Validated behavior

Version 1.0.0 was validated in a real ConfigMgr OSD Task Sequence: LDAPS bind succeeded, the computer was added, membership was verified, credential variables were cleared, and the script returned `0`.

## License

MIT License.
