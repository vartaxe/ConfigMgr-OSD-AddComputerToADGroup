<div align="center">

![ConfigMgr OSD Add Computer to AD Group](assets/banner.svg)

# ConfigMgr OSD Add Computer to AD Group

Adds the current computer account to Active Directory groups during a ConfigMgr Task Sequence, using Kerberos over LDAPS.

[![Validate PowerShell](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/validate.yml/badge.svg)](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/validate.yml)
[![Release](https://img.shields.io/github/v/release/vartaxe/ConfigMgr-OSD-AddComputerToADGroup?sort=semver)](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE)
![ConfigMgr](https://img.shields.io/badge/ConfigMgr-Task%20Sequence-6f42c1)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

</div>

> [!IMPORTANT]
> Test in a lab Task Sequence before production use. Script logs can contain internal infrastructure details. Sanitize output before sharing publicly.

## Why this script

Adding a computer to an AD group during OSD is a well-worn problem, and several good
community solutions already exist. This one is built for environments that want the
operation to be secure by default:

- **Kerberos over LDAPS (TCP 636), enforced.** There is no fallback to unsigned LDAP on
  port 389 and no NTLM path. If the directory cannot be reached securely, the step fails
  rather than downgrading.
- **No extra payload.** No RSAT install, no ADSI, no external web service. It uses
  `System.DirectoryServices.Protocols` directly.
- **Credentials scoped to the LDAP bind only.** The step does not use *Run this step as
  the following account*, which avoids a known class of token and local-administrator
  failures in Task Sequences.
- **Domain controller discovery with failover** and bounded retries that distinguish
  transient failures from permanent ones.

See [DESIGN.md](DESIGN.md) for related community implementations and the trade-offs.

## Requirements

- Windows PowerShell 5.1, running in the **full Windows** phase of a Task Sequence, after
  domain join. Windows PE is not supported and the script exits if detected.
- Domain controllers reachable on **TCP 636** with a valid LDAPS server certificate.
- An account with rights to modify the target groups. Use *Manager can update membership
  list* on the group's **Managed By** tab for per-group delegation, or the Delegation of
  Control Wizard's *Modify the membership of a group* at the OU level.

## Quick start

1. Add the `Scripts` folder to a ConfigMgr package and distribute it.
2. Create two hidden Task Sequence variables holding the credential:

   | Variable | Purpose |
   | --- | --- |
   | `ADGroupUserName` | Account with delegated rights over the target groups |
   | `ADGroupPassword` | Password for that account |

3. Add a **Run PowerShell Script** step in the full Windows phase, referencing the package:

   ```powershell
   .\Add-ComputerToADGroup.ps1 -GroupName "Workstation-Certificate-AutoEnroll"
   ```

   Multiple groups are supported:

   ```powershell
   .\Add-ComputerToADGroup.ps1 -GroupName "Group-A","Group-B"
   ```

4. The script clears both credential variables on exit. Keep a following **Clear AD Group Variables** step as defense in depth.

Full step settings are in the [deployment guide](DEPLOYMENT.md).

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `-GroupName` | *(required)* | One or more group `sAMAccountName` values |
| `-RetryCount` | `3` | Retry passes for transient directory failures |
| `-RetryDelaySeconds` | `300` | Delay between retry passes |
| `-TimeoutSeconds` | `30` | LDAP connect and operation timeout per DC |

Exit code `0` means every requested group was added and verified. Exit code `1` means at
least one group failed; see `AddComputerToADGroup.log`.

## Logging

Writes `AddComputerToADGroup.log` to `_SMSTSLogPath`, falling back to `%WINDIR%\Temp`.
Each group produces a summary line with the outcome: `AlreadyMember`, `AddedAndVerified`,
`FailedPermanent`, or `FailedTransient`.

## Documentation

- [Deployment guide](DEPLOYMENT.md)
- [Design notes and related work](DESIGN.md)
- [Feature support](FEATURES.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Security](SECURITY.md)
- [Release notes](RELEASE-NOTES.md)
- [Examples](examples/README.md)

## Validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Test-Script.ps1"
```

Runs the PowerShell parser, PSScriptAnalyzer, and a set of required and forbidden pattern
checks. The same script runs in CI on every push.

## License

MIT. See [LICENSE](LICENSE).
