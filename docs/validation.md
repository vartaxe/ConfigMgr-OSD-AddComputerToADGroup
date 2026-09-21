---
title: Validation
---

# Validation

[Documentation home](../index.md) | [Development](development.md) | [Deployment](deployment.md) | [Compatibility](compatibility.md) | [Validation](validation.md)

<p align="center"><img src="../assets/validation-pass.svg" alt="Validation checklist showing required parser, PSScriptAnalyzer, and Pester checks with live ConfigMgr and AD tests marked PENDING" width="600" height="456"></p>

[Open the full-size checklist](../assets/validation-pass.svg). The illustration summarizes the validation layers; use the results and checklist below when planning a rollout.

The v1.0.0 source passes Windows PowerShell 5.1 parser checks, PSScriptAnalyzer 1.25.0, Pester 5.7.1, and exact-byte source manifest verification. Runtime tests bind the production parameters and use mocked Task Sequence, domain-discovery, and LDAP boundaries. They cover escaped requests, membership verification, exception classification, failover, bounded retries, duplicate groups, resource disposal, and credential-free diagnostics.

**Live ConfigMgr and Active Directory testing was not executed.** Automated results do not establish live authentication, certificate trust, permissions, or deployment compatibility.

## Prerequisites and scope

Use the same pinned development modules as CI. If the required versions are missing, install them through your organization's approved package source and trust policy; retain publisher verification:

```powershell
Install-Module Pester -RequiredVersion '5.7.1' -Repository PSGallery -Scope CurrentUser -Force
Install-Module PSScriptAnalyzer -RequiredVersion '1.25.0' -Repository PSGallery -Scope CurrentUser -Force
```

These are development dependencies, not production runtime dependencies. From the project root, run:

```powershell
# Final validation, including the version/tag contract. This does not create a tag.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\build\Invoke-Validation.ps1 -Tag v1.0.0
```

The command parses every PowerShell file, analyzes the runtime and test/build code, executes all Pester tests, and verifies the checksum manifest. The process-scoped execution policy does not change machine policy; use your organization's approved equivalent where required.

The validator explicitly requires Windows PowerShell 5.1 and the exact module versions, analyzes `Scripts`, `Tests`, and `build`, checks `VERSION` against the production script's literal version assignment, and verifies `CHECKSUMS.txt`. Parser errors, analyzer warnings/errors, missing modules, failed, skipped, or not-run Pester tests, failed discovery, zero discovered tests, and manifest/version errors return a nonzero process exit.

`-SkipChecksums` skips only the validator's final checksum phase. It does not bypass repository-contract tests, which independently check the manifest. Regenerate `CHECKSUMS.txt` before validating the full source tree; the switch is useful for isolated validator fixtures, not as a way to validate source edits against a stale manifest. Final validation must not use it.

The manifest covers all files in the source root, including dotfiles, excluding only root `.git` metadata and `CHECKSUMS.txt` itself. Each line is a SHA-256 hash, two spaces, then a root-relative path using forward slashes. Sort the complete lines, hash first. Duplicate, missing, extra, malformed, and mismatched entries fail. Follow the [normalization and generation recipe](release-process.md#checksum-checkout-convention); keep generated ZIPs, reports, and test artifacts outside the source tree.

Process-exit fixtures write their intended inputs once and decode structured PowerShell output, so console line wrapping does not change diagnostic assertions. Their 60-second child-process timeout and nonzero-exit checks remain enforced.

Documentation tests resolve local Markdown links and heading fragments, parse every SVG, check image labels and intrinsic dimensions, measure banner text contrast, and enforce the Pages and current-release contracts. These source checks do not replace a successful GitHub Pages build or browser checks of light/dark themes and mobile layouts. Pages uses the shared Cayman layout; GitHub renders the README separately.

## What each result establishes

| Validation layer | Evidence and limits |
|---|---|
| Static | Parser/analyzer results apply to the checked source and runtime; they do not exercise ConfigMgr or AD |
| Unit / mocked | Pester checks source contracts and isolated behavior with test doubles; mocks do not establish live authentication, TLS, permissions, or deployment compatibility |
| GitHub Actions | The [CI run](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/ci.yml) must complete for the relevant commit before claiming a CI pass; Windows-hosted CI is not a domain/ConfigMgr lab |
| Live | Only recorded testing in a real ConfigMgr/AD environment establishes the results below |

Record the exact revision, commands, engine/module versions, results, and unresolved warnings. The workflow publishes a prerelease candidate; the [separate promotion gate](release-process.md#stage-2-verify-assets-and-approve-promotion) requires verification of the downloaded assets and explicit maintainer approval. A regular GitHub release label describes distribution; it does not add live-test evidence.

## Required live tests

Complete these checks in a controlled environment before broad rollout. **None was executed for this release.** Record sanitized evidence for your ConfigMgr version, Windows build, domain policy, and deployment phase.

| Required live test | Status | Evidence required |
|---|---|---|
| ConfigMgr Task Sequence execution | Not executed | Packaged script runs as Local System in full Windows with Windows PowerShell 5.1 and active `Microsoft.SMS.TSEnvironment` |
| Domain join and restart | Not executed | Join and required restart completed before execution; secure channel operational |
| Kerberos over LDAPS TCP 636 | Not executed | Default bind, trusted certificate, direct addition, and verification succeed without compatibility settings |
| Delegated permissions | Not executed | Least-privilege account can modify only intended groups; denied access fails safely |
| Already-member rerun | Not executed | Existing direct member is not duplicated and process exit is `0` |
| Invalid credentials | Not executed | Incorrect credentials fail without secret leakage or repeated lockout-prone retries |
| Unavailable domain controller | Not executed | Failover and bounded retries work; exhausted failures return `1` without authentication/transport fallback |
| Site-aware domain controller order | Not executed | A multi-site domain binds a local-site controller first, and an undetermined site logs the warning and still completes in name order |
| SignedLdap compatibility | Not executed | Explicit TCP 389 connection requires signing and sealing; compatibility selection is logged |
| Sanitized dedicated log | Not executed | Success, compatibility, invalid-credential, and failure paths in `AddComputerToADGroup.log` contain no credentials |
| Sanitized ConfigMgr log | Not executed | Corresponding `smsts.log` entries contain no credentials or unintended parameter disclosure |
| Negotiate compatibility | Not executed | Explicit opt-in and enforced LM/NTLMv1 denial; negotiated authentication checked independently rather than inferred from `AuthType` |
| Credential cleanup and failure propagation | Not executed | Both hidden custom variables cleared on success/failure and failed script results preserved |

Keep raw logs private. Record only sanitized evidence and non-sensitive environment versions. See [compatibility](compatibility.md) for candidate platforms and [security](../SECURITY.md) for limitations.
