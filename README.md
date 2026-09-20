<p align="center"><img src="assets/banner.svg" alt="ConfigMgr OSD Add Computer to AD Group" width="100%"></p>

# ConfigMgr OSD Add Computer to AD Group

Add computer accounts to Active Directory groups during ConfigMgr OSD with verification, retries, compatibility modes, and CMTrace logging.

Version 1.0.0 is published as a prerelease; live ConfigMgr and Active Directory validation remains pending.

[Quick start](#quick-start) | [Deployment](docs/deployment.md) | [Compatibility](docs/compatibility.md) | [Security](SECURITY.md) | [Troubleshooting](docs/troubleshooting.md)

[![Version](https://img.shields.io/badge/version-1.0.0-2671be)](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases/tag/v1.0.0)
[![CI](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/ci.yml/badge.svg)](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/ci.yml)
![PowerShell](https://img.shields.io/badge/Windows%20PowerShell-5.1-2671be)
[![License](https://img.shields.io/badge/license-MIT-22c55e)](LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-%E2%9D%A4-db61a2)](https://github.com/sponsors/vartaxe)

## Quick start

1. Package `Scripts\Add-ComputerToADGroup.ps1` and distribute it to the required ConfigMgr distribution points.
2. Run as **Local System in full Windows, after domain join and the required restart**, using **Windows PowerShell 5.1**. WinPE and PowerShell 7 are not supported runtimes.
3. Immediately before the script step, create the hidden custom ConfigMgr Task Sequence variables `ADGroupUserName` and `ADGroupPassword` for a dedicated account with delegated group-membership permissions.
4. Use a **Run PowerShell Script** step with `Scripts\Add-ComputerToADGroup.ps1` as the script name and this value in **Parameters**:

```text
-GroupName 'Workstation-Certificate-AutoEnroll'
```

5. Clear both credential variables immediately afterward on success **and failure**, and preserve a failed script result.

The self-contained script defaults to **Kerberos over LDAPS on TCP 636**, with no automatic transport fallback or external runtime module dependency. It verifies direct membership and returns `0` only when all requested groups succeed; failures return `1`.

Read [deployment](docs/deployment.md) for prerequisites, cleanup handling, all parameters, and exact log locations before production use.

## Why this project exists

A ConfigMgr Task Sequence may need to add the newly joined computer to specific Active Directory groups. This project keeps that operation in a self-contained Windows PowerShell 5.1 utility, without RSAT or external runtime modules, with explicit authentication and transport settings, membership verification, retries, and logging.

## Highlights

- Kerberos over LDAPS on TCP 636 by default, without automatic authentication or transport fallback.
- Explicit `SignedLdap` transport on TCP 389 with signing and sealing.
- Direct membership checks, with post-write verification for additions.
- Site-aware domain controller ordering and failover, with name-order fallback when the local site is unknown.
- Bounded retries with permanent/transient error classification.
- CMTrace-format logs with sanitized error messages and explicit `0`/`1` exit codes.
- Windows PowerShell 5.1 parser/analyzer checks, mocked Pester coverage, and a SHA-256 source manifest.

## Documentation

- [Architecture](docs/architecture.md)
- [Compatibility](docs/compatibility.md)
- [Deployment](docs/deployment.md)
- [Logging](docs/logging.md)
- [Release process](docs/release-process.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Validation](docs/validation.md)

## Validation status

For the original 2026-09-15 v1.0.0 prerelease, Windows PowerShell 5.1 parser checks, PSScriptAnalyzer, mocked Pester tests, SHA-256 manifest verification, and [GitHub Actions](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/runs/35003413864) passed. The [2026-09-20 reissue notice](RELEASE-NOTES.md#reissue-2026-09-20) distinguishes the replacement; each revision requires its own validation. These results are distinct from live ConfigMgr and Active Directory testing. **All required live tests remain pending**; see the [validation checklist](docs/validation.md). Windows Server 2012/2012 R2 is best effort with WMF 5.1, not a verified platform.

## Maintainer

**Claudio Mendes** · [@vartaxe](https://github.com/vartaxe) · [vartaxe@outlook.com](mailto:vartaxe@outlook.com)

## License

MIT. See [LICENSE](LICENSE).
