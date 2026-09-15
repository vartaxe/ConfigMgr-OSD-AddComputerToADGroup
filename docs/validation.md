# Validation

<p align="center"><img src="../assets/validation-pass.svg" alt="Validation checklist showing required parser, PSScriptAnalyzer, and Pester checks with live ConfigMgr and AD tests marked PENDING" width="70%"></p>

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-Validation.ps1` to parse every PowerShell file with Windows PowerShell 5.1, run PSScriptAnalyzer, execute Pester tests, and verify the exact-byte checksum manifest.

## Prerequisites and scope

Install the same pinned development modules used by CI:

```powershell
Install-Module Pester -RequiredVersion '5.7.1' -Repository PSGallery -Scope CurrentUser -Force
Install-Module PSScriptAnalyzer -RequiredVersion '1.25.0' -Repository PSGallery -Scope CurrentUser -Force
Import-Module Pester -RequiredVersion '5.7.1' -Force
Import-Module PSScriptAnalyzer -RequiredVersion '1.25.0' -Force

# Final validation; checksums are required.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-Validation.ps1

# Optional tag check (does not create a tag).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-Validation.ps1 -Tag v1.0.0

# Developer loop only, before regenerating CHECKSUMS.txt.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Invoke-Validation.ps1 -SkipChecksums
```

These modules are **development dependencies**, not production runtime dependencies. Use your organization's approved package source and trust policy; do not bypass publisher verification.

The validator explicitly requires Windows PowerShell 5.1 and the exact module versions, analyzes `Scripts`, `Tests`, and `build`, checks `VERSION` against the production script's literal version assignment, and verifies `CHECKSUMS.txt`. Parser errors, analyzer warnings/errors, missing modules, failed, skipped, or not-run Pester tests, failed discovery, zero discovered tests, and manifest/version errors return a nonzero process exit.

The manifest covers all files in the source root, including dotfiles, excluding only root `.git` metadata and `CHECKSUMS.txt` itself. Each line is a SHA-256 hash, two spaces, then a root-relative path using forward slashes. Duplicate, missing, extra, malformed, and mismatched entries fail. Validate a clean source tree or full extracted source archive; keep generated ZIPs and test artifacts outside that tree.

Process-exit fixtures write their intended inputs once and decode structured PowerShell output, so console line wrapping does not change diagnostic assertions. Their 60-second child-process timeout and nonzero-exit checks remain enforced.

## What each result establishes

| Validation layer | Evidence and limits |
|---|---|
| Static | Parser/analyzer results apply to the checked source and runtime; they do not exercise ConfigMgr or AD |
| Unit / mocked | Pester checks source contracts and isolated behavior with test doubles; mocks do not establish live authentication, TLS, permissions, or deployment compatibility |
| GitHub Actions | The [CI run](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/ci.yml) must complete for the relevant commit before claiming a CI pass; Windows-hosted CI is not a domain/ConfigMgr lab |
| Live | Only recorded testing in a real ConfigMgr/AD environment establishes the results below |

No static success illustration or workflow definition is evidence of a passed run. Record the exact revision, commands, engine/module versions, results, and any unresolved warnings when reporting validation.

## Required live tests

**All tests below are PENDING. No live environment results are recorded for this version.**

| Required live test | Status | Evidence required |
|---|---|---|
| ConfigMgr Task Sequence execution | **PENDING** | Packaged script runs as Local System in full Windows with Windows PowerShell 5.1 and active `Microsoft.SMS.TSEnvironment` |
| Domain join and restart | **PENDING** | Join and required restart completed before execution; secure channel operational |
| Kerberos over LDAPS TCP 636 | **PENDING** | Default bind, trusted certificate, direct addition, and verification succeed without compatibility settings |
| Delegated permissions | **PENDING** | Least-privilege account can modify only intended groups; denied access fails safely |
| Already-member rerun | **PENDING** | Existing direct member is not duplicated and process exit is `0` |
| Invalid credentials | **PENDING** | Incorrect credentials fail without secret leakage or repeated lockout-prone retries |
| Unavailable domain controller | **PENDING** | Failover and bounded retries work; exhausted failures return `1` without authentication/transport fallback |
| Site-aware domain controller order | **PENDING** | A multi-site domain binds a local-site controller first, and an undetermined site logs the warning and still completes in name order |
| SignedLdap compatibility | **PENDING** | Explicit TCP 389 connection requires signing and sealing; compatibility selection is logged |
| Sanitized dedicated log | **PENDING** | Success, compatibility, invalid-credential, and failure paths in `AddComputerToADGroup.log` contain no credentials |
| Sanitized ConfigMgr log | **PENDING** | Corresponding `smsts.log` entries contain no credentials or unintended parameter disclosure |
| Negotiate compatibility | **PENDING** | Explicit opt-in and enforced LM/NTLMv1 denial; negotiated authentication checked independently rather than inferred from `AuthType` |
| Credential cleanup and failure propagation | **PENDING** | Both hidden custom variables cleared on success/failure and failed script results preserved |

Keep raw logs private. Record only sanitized evidence and non-sensitive environment versions. See [compatibility](compatibility.md) for candidate platforms and [security](../SECURITY.md) for limitations.
