# Logging

The dedicated filename is **`AddComputerToADGroup.log`**.

1. If `_SMSTSLogPath` supplies an existing directory, the script appends its log there.
2. If that variable is empty, unavailable, or does not identify an existing directory, the fallback is `%WINDIR%\Temp\AddComputerToADGroup.log`.

The log uses native CMTrace entries with severity `1` (information), `2` (warning), or `3` (error). It records retry progress, explicit compatibility selections, per-group summaries, and the process exit code. Group result values are `AlreadyMember`, `AddedAndVerified`, `FailedPermanent`, or `FailedTransient`.

Warnings/errors and final console status can also appear in **`smsts.log`**, whose location is managed by ConfigMgr. These are two separate logs; the dedicated log is not a replacement for `smsts.log`.

## Error diagnostics

Returned LDAP diagnostics are deliberately limited to a sanitized **numeric LDAP error code**, **directory result code**, or **exception type**. For example, invalid credentials may appear as `LDAP error code 49.` rather than a server-provided explanation. Known credential-free messages defined by the script, such as an empty required variable or a failed secure-channel check, remain readable.

Raw server diagnostic text and raw exception details are not written to the dedicated log or console. Wrapped directory exceptions are unwrapped for classification; their raw messages are not exposed. A shortened message is intentional, not evidence that the server returned no additional detail. Investigate further through approved private directory diagnostics rather than enabling credential or raw-exception logging in the script.

Do not log or dump Task Sequence variables, credentials, or credential objects. Keep native step parameter logging disabled. Sanitization reduces exposure, but directory identifiers and deployment details can remain sensitive. Review sanitized copies of **both** logs before sharing; never upload raw log archives.

## Logging failures

Failure to read `_SMSTSLogPath` produces a warning and uses the Windows Temp fallback. Failure to write a log entry produces the explicit warning `Cannot write AddComputerToADGroup.log; check the log directory and permissions.` without exposing the raw exception.

Early initialization failures or an unwritable log directory may prevent a dedicated file from being created; check `smsts.log` and package/Task Sequence setup as well. A log-write warning alone does not change the membership result or guarantee another writable destination. A successful membership result is not proof that logging succeeded.

Live verification of both logs, including invalid-credential and failure paths, remains **pending** in [validation](validation.md).
