---
title: Add Computer to AD Group
---

## <img src="assets/people-team.svg" alt="" aria-hidden="true" width="24" height="24"> Add group membership

Add a newly joined computer to Active Directory groups from a ConfigMgr Task Sequence.
The self-contained Windows PowerShell 5.1 script checks direct membership, adds only
when needed, and verifies the result on the same domain controller connection.

> **Current version: 1.0.0.** The workflow publishes a prerelease candidate.
> Downloaded-asset verification and maintainer approval precede promotion to a
> regular release marked latest. Release status is not platform certification.
> Live ConfigMgr and Active Directory testing was not executed. This site follows `main`; the
> [v1.0.0 release](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases/tag/v1.0.0)
> is a versioned snapshot with its own [release notes](RELEASE-NOTES.md).

## Before deployment

Run as **Local System in full Windows, after domain join and restart**, inside an
active ConfigMgr Task Sequence. WinPE, PowerShell 7, and ordinary interactive
execution are not supported.

The default is **Kerberos over LDAPS on TCP 636**, with trusted domain controller
certificates and a dedicated account delegated access only to the target groups.
There is no automatic authentication or transport fallback.

Set the hidden custom variables `ADGroupUserName` and `ADGroupPassword` immediately
before the packaged script step. Clear both on **success and failure** using native
Task Sequence steps, and preserve the script's result. Never put credentials in
parameters or package content.

## Documentation

| Guide | Use it for |
|---|---|
| [Deployment](docs/deployment.md) | Prerequisites, parameters, credential cleanup, exit codes |
| [Compatibility](docs/compatibility.md) | Candidate platforms and explicit opt-in modes |
| [Security](SECURITY.md) | Least privilege, credential limitations, private reporting |
| [Validation](docs/validation.md) | Automated checks and the environment-validation checklist |
| [Architecture](docs/architecture.md) | Discovery, membership verification, bounded retries |
| [Logging](docs/logging.md) | Dedicated CMTrace log, sanitized diagnostics, `smsts.log` |
| [Troubleshooting](docs/troubleshooting.md) | Readiness, certificates, permissions, failure handling |
| [Examples](examples/README.md) | Generic Task Sequence pattern and contributor setup |
| [Release process](docs/release-process.md) | Source-byte checksums and publication safeguards |
| [Development](docs/development.md) | Workstation setup, names versus paths, and shared banner generation |
| [Distribution](docs/distribution.md) | Release packages, standalone gist, licensing, and checksum verification |

## Outputs and results

Exit `0` means the computer is verified as a direct member of every requested
group. Exit `1` means initialization or an operation failed. Successful additions
are not rolled back when another group fails; verification does not prove replication
to other domain controllers.

## Source and releases

[Browse source](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup) or
[read the script](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/blob/main/Scripts/Add-ComputerToADGroup.ps1).
Download release assets and their matching SHA-256 sidecars from
[GitHub Releases](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases).
Existing downloads do not update automatically.

For the standalone script, use the
[public gist snapshot](https://gist.github.com/vartaxe/99dc4be2d6dbf8cda0b93e2de3f0d906)
with its MIT license and checksums. The repository remains authoritative; see
[distribution](docs/distribution.md) before using a separately downloaded script.

For changes, see [contributing](CONTRIBUTING.md) and the
[release process](docs/release-process.md). Maintained by
[Claudio Mendes (@vartaxe)](https://github.com/vartaxe), under the
[MIT license](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/blob/main/LICENSE).

## Related projects

- [Copy OSD Logs to File Share](https://github.com/vartaxe/ConfigMgr-OSD-CopyOSDLogToFileShare) - companion task-sequence utility ([documentation](https://vartaxe.github.io/ConfigMgr-OSD-CopyOSDLogToFileShare/)).
- [Claudio Mendes / vartaxe](https://vartaxe.github.io/vartaxe/) - profile and project directory ([GitHub](https://github.com/vartaxe)).
