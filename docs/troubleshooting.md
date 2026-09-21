---
title: Troubleshooting
---

# Troubleshooting

[Documentation home](../index.md) | [Development](development.md) | [Deployment](deployment.md) | [Compatibility](compatibility.md) | [Validation](validation.md)

## Validation

```powershell
.\build\Invoke-Validation.ps1
```

Run this from the project root in **Windows PowerShell 5.1** after installing the pinned development modules in [validation](validation.md). This does not execute a live Task Sequence.

## Common checks

- Confirm the package is distributed to distribution points.
- Confirm the Task Sequence step references the packaged script, not an older inline version.
- Confirm execution is in full Windows as Local System, **after domain join and restart**.
- Confirm both `ADGroupUserName` and `ADGroupPassword` are set and hidden, and cleanup runs on failure as well as success.
- Review `AddComputerToADGroup.log` in the existing `_SMSTSLogPath` directory or `%WINDIR%\Temp`, along with `smsts.log`.
- Sanitize logs before sharing externally.

LDAP failures intentionally report a sanitized numeric error code, directory result code, or exception type, not raw server diagnostic text. Known credential-free local errors remain readable. Use the reported code plus deployment context and approved private directory diagnostics; do not add raw exception or credential output to troubleshoot. See [logging](logging.md#error-diagnostics).

| Symptom | Check |
|---|---|
| `Microsoft.SMS.TSEnvironment` unavailable | Run from an active ConfigMgr Task Sequence, not a standalone console |
| Secure channel/readiness failure | Domain-join restart completed, domain DNS/time/network connectivity, and member-computer trust |
| LDAPS connection failure | TCP 636 reachability, certificate trust/expiry/DNS name, and DC LDAPS configuration; do not bypass certificate validation |
| Invalid credentials / `LDAP error code 49.` | Re-enter the two hidden custom variables and check account restrictions/lockout without printing values |
| Access denied / permanent group failure | Least-privilege delegation to the group's `member` attribute; group scope constraints and domain location |
| Group not found | Exact group `sAMAccountName`, not a display name or DN. Ensure the group exists and is visible to the delegated account before deployment; a missing group is treated as a permanent configuration failure |
| Computer account was not found | Account exists in the computer's domain with `sAMAccountName` matching the local computer name plus `$`; allow for post-join replication. Retries remain bounded and do not create the account |
| Computer account returned multiple results | Investigate the ambiguous directory search with the AD administrator; the script does not select an arbitrary account |
| Unavailable DC / retries exhausted | DC discovery, DNS, network reachability, and readiness; retries do not change transport or authentication |
| `local Active Directory site could not be determined` warning | Site coverage for the computer's subnet in AD Sites and Services, plus DNS. Discovery still proceeds in name order, so this is a performance warning, not a failure |
| Compatibility request rejected | Negotiate needs explicit `-AllowNtlmV2` and readable local `LmCompatibilityLevel` of `3`, `4`, or `5`; verify server-side LM/NTLMv1 refusal separately. Use [compatibility](compatibility.md), not weaker settings |
| SignedLdap bind failure | Explicit TCP 389 path and support/policy for **both** signing and sealing |
| Exit `1` after some additions | Operations are not transactional; inspect each group summary. Verified additions are not rolled back |
| No dedicated log / `Cannot write AddComputerToADGroup.log` warning | Check `smsts.log`, early initialization failure, log directory existence/permissions, and package source. Raw write-exception details are intentionally omitted |

An already-direct-member rerun should return `0` without adding a duplicate. A successful verification uses the same directory connection and does not prove replication to every DC. Validate those outcomes in your environment using the [checklist](validation.md#required-live-tests).
