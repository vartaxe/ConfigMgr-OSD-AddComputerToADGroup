# Deployment

## Prerequisites

- Domain controllers must support LDAPS (TCP 636) with a valid server certificate.
- The account in `ADGroupUserName` needs write access to the `member` attribute on each target group. Use "Manager can update membership list" on the group's Managed By tab for per-group delegation, or the Delegation of Control Wizard's "Modify the membership of a group" task at the OU level.

Recommended Task Sequence layout:

```text
Set AD Group Variables
Add Computer to AD Group
Clear AD Group Variables
```

The script clears both variables when it exits. Retain the explicit cleanup step so
credentials are also removed if the script cannot start.

Required variables:

```text
ADGroupUserName
ADGroupPassword
```

Example parameters:

```powershell
-GroupName "Workstation-Certificate-AutoEnroll"
```

Recommended step settings:

```text
Run as another account:       Disabled
PowerShell parameter logging: Disabled
Timeout:                      20 minutes
Continue on error:            Disabled if membership is mandatory
```
