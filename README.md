<p align="center"><img src="assets/banner.svg" alt="ConfigMgr OSD Add Computer to AD Group" width="100%"></p>

# ConfigMgr OSD Add Computer to AD Group

Add computer accounts to Active Directory groups during ConfigMgr OSD with verification, retries, compatibility modes, and CMTrace logging.

[Quick start](#quick-start) | [Deployment](docs/deployment.md) | [Compatibility](docs/compatibility.md) | [Security](SECURITY.md) | [Troubleshooting](docs/troubleshooting.md)

[![Version](https://img.shields.io/badge/version-1.0.0-2671be)](VERSION)
[![CI](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/ci.yml/badge.svg)](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/ci.yml)
![PowerShell](https://img.shields.io/badge/Windows%20PowerShell-5.1-2671be)
[![License](https://img.shields.io/badge/license-MIT-22c55e)](LICENSE)

## Quick start

1. Package `Scripts\Add-ComputerToADGroup.ps1` and distribute it to the required ConfigMgr distribution points.
2. Run as **Local System in full Windows, after domain join and the required restart**, using **Windows PowerShell 5.1**. WinPE and PowerShell 7 are not supported runtimes.
3. Immediately before the script step, create the hidden custom Task Sequence variables `ADGroupUserName` and `ADGroupPassword` for a dedicated account with delegated group-membership permissions.
4. Use a **Run PowerShell Script** step with `Scripts\Add-ComputerToADGroup.ps1` as the script name and these parameters:

```powershell
-GroupName 'Workstation-Certificate-AutoEnroll'
```

5. Clear both credential variables immediately afterward on success **and failure**, and preserve a failed script result.

The self-contained script defaults to **Kerberos over LDAPS on TCP 636**, with no automatic transport fallback or external runtime module dependency. It verifies direct membership and returns `0` only when all requested groups succeed; failures return `1`.

Read [deployment](docs/deployment.md) for prerequisites, cleanup handling, all parameters, and exact log locations before production use.

## Documentation

- [Architecture](docs/architecture.md)
- [Compatibility](docs/compatibility.md)
- [Deployment](docs/deployment.md)
- [Logging](docs/logging.md)
- [Release process](docs/release-process.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Validation](docs/validation.md)

## Validation status

Static checks, mocked unit tests, and GitHub Actions are distinct from live ConfigMgr/Active Directory testing. **All required live tests remain pending**; see the [validation checklist](docs/validation.md). Windows Server 2012/2012 R2 is best effort with WMF 5.1, not a verified platform.

## Maintainer

**Claudio Mendes** · [@vartaxe](https://github.com/vartaxe) · [vartaxe@outlook.com](mailto:vartaxe@outlook.com)

## License

MIT. See [LICENSE](LICENSE).
