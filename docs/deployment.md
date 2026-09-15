# Deployment

## Prerequisites and execution phase

- Run in an active ConfigMgr Task Sequence as **Local System in full Windows after domain join and the required restart**. Do not run in WinPE, before the join restart, or from an ordinary interactive shell.
- Use **Windows PowerShell 5.1**, not PowerShell 7. The production script has no external runtime module dependency.
- Ensure domain DNS, time synchronization, and the member computer's secure channel are operational.
- Default connections use **Kerberos over LDAPS on TCP 636** to discovered domain controllers in the computer's domain, preferring controllers in the computer's own Active Directory site. Provide trusted, valid DC certificates matching their DNS names and the required domain network connectivity.
- Delegate directory read access and write access to the target groups' `member` attribute to a dedicated account. Do not use Domain Admin credentials.

## Recommended Task Sequence layout

<p align="center"><img src="../assets/task-sequence-flow.svg" alt="ConfigMgr Task Sequence pattern: set variables, run packaged script, validate result, clear variables on success and failure" width="100%"></p>

```text
Complete domain join
Restart into the installed Windows operating system
Set hidden ADGroupUserName and ADGroupPassword
Run packaged Add-ComputerToADGroup.ps1
Clear ADGroupUserName and ADGroupPassword on success and failure
Preserve and handle the script result
```

The restart may already be part of Windows setup, but it must have completed after domain join before this script runs.

## Run PowerShell Script step

Keep the `Scripts` directory in the package source, distribute the package, and configure:

```text
Package: package containing Scripts\Add-ComputerToADGroup.ps1
Script name: Scripts\Add-ComputerToADGroup.ps1
Run as another account: Disabled
PowerShell parameter logging: Disabled
Success code: 0
```

Use your organization's approved execution policy. `AllSigned` requires you to sign the script with a trusted certificate; the supplied script is not signed. Do not put credentials in the parameters field.

For the native step's parameter logging, leave `OSDLogPowerShellParameters` unset or set it to `False`; do not enable it. This is a ConfigMgr logging control, not a credential variable read by this script. See Microsoft's [Run PowerShell Script step](https://learn.microsoft.com/en-us/intune/configmgr/osd/understand/task-sequence-steps#run-powershell-script).

Size the step timeout for your environment. The default three passes can include two 300-second sleeps, plus discovery, connection, and multiple LDAP operations for each DC/group; `TimeoutSeconds` is not an overall script deadline. A fixed 20-minute timeout is not guaranteed to cover every environment.

## Variables

| Exact custom variable | Value | Setting |
|---|---|---|
| `ADGroupUserName` | Dedicated account, for example `CONTOSO\svc-configmgr-adgroups` | **Do not display this value** |
| `ADGroupPassword` | That account's password, entered through approved Task Sequence administration | **Do not display this value** |

The script reads only these custom credential variables, never reserved ConfigMgr credentials. `_SMSTSLogPath` is read only to select the log directory.

## Parameters

Use group **sAMAccountName** values, not distinguished names or display names.

```powershell
-GroupName 'Workstation-Certificate-AutoEnroll'
```

For multiple groups, the **Run PowerShell Script** step's parameters field accepts a PowerShell array:

```powershell
-GroupName 'Group-A','Group-B' -RetryCount 3 -RetryDelaySeconds 300 -TimeoutSeconds 30
```

| Parameter | Default | Contract |
|---|---|---|
| `GroupName` | Required | One or more group `sAMAccountName` values; whitespace is trimmed and duplicates are removed |
| `RetryCount` | `3` | Total retry passes, including the first attempt; range `1`-`10` |
| `RetryDelaySeconds` | `300` | Delay between passes with unresolved groups; range `0`-`3600` |
| `TimeoutSeconds` | `30` | LDAP connection/operation timeout per DC, not total runtime; range `5`-`300` |
| `AuthenticationMode` | `Kerberos` | `Kerberos` or explicit `Negotiate`; Negotiate requires `AllowNtlmV2` |
| `DirectoryTransport` | `LDAPS` | `LDAPS` on TCP 636 or explicit `SignedLdap` on TCP 389 with signing and sealing |
| `AllowNtlmV2` | Not set | Explicit opt-in required for Negotiate; local `LmCompatibilityLevel` must be `3`, `4`, or `5`. Does not force or attest an NTLM version and does not change Kerberos mode |

Keep compatibility examples separate from the default deployment; see [compatibility](compatibility.md) and [security](../SECURITY.md) before changing authentication or transport.

## Credential lifecycle

Create both hidden credential variables immediately before the script step and clear them immediately afterward using native Task Sequence steps. The script does not clear them for you.

Do not rely on a cleanup step that is skipped when the script fails. Configure a failure-handling path that preserves the Run PowerShell Script result before later steps overwrite it, clears both variables, and then applies the deployment's failure policy. If using **Continue on error** to reach cleanup, do not treat that as permission to ignore a failed membership operation. Verify this path in a live Task Sequence.

## Results and logs

- Exit `0`: every group was already a direct member or was added and verified.
- Exit `1`: initialization or any group operation failed. Successful additions are not rolled back if another group fails.
- The dedicated log is `AddComputerToADGroup.log`, in the existing `_SMSTSLogPath` directory when available, otherwise `%WINDIR%\Temp`.
- Consult both the dedicated log and `smsts.log`; see [logging](logging.md), [troubleshooting](troubleshooting.md), and the [pending live tests](validation.md).
