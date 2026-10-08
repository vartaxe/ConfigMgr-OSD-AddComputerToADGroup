<p align="center">
  <picture>
    <source media="(max-width: 720px)" srcset="assets/banner-compact.svg?v=1.0.0" width="640">
    <img src="assets/banner.svg?v=1.0.0" alt="Add Computer to AD Group for ConfigMgr OSD; Add-ComputerToADGroup.ps1; Windows PowerShell 5.1." width="1280">
  </picture>
</p>

# ConfigMgr OSD Add Computer to AD Group

Add computer accounts to Active Directory groups during ConfigMgr OSD with verification, retries, compatibility modes, and CMTrace logging.

**Current version: 1.0.0.** This README follows `main`; downloads are versioned snapshots.

[Documentation](https://vartaxe.github.io/ConfigMgr-OSD-AddComputerToADGroup/) | [Quick start](#quick-start) | [Deployment](docs/deployment.md) | [Compatibility](docs/compatibility.md) | [Security](SECURITY.md) | [Troubleshooting](docs/troubleshooting.md)

[![Release v1.0.0](https://img.shields.io/badge/RELEASE-v1.0.0-155799)](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases/tag/v1.0.0)
[![CI - main push](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)
![Windows PowerShell 5.1](https://img.shields.io/badge/Windows%20PowerShell-5.1-155799)
[![MIT license](https://img.shields.io/badge/license-MIT-117865)](LICENSE)

Standalone script: [public gist snapshot](https://gist.github.com/vartaxe/99dc4be2d6dbf8cda0b93e2de3f0d906).
Keep its license and checksum files with the script; see [distribution](docs/distribution.md).

## Requirements

- An active ConfigMgr task sequence running as **Local System in full Windows, after domain join and restart**, with **Windows PowerShell 5.1**. WinPE and PowerShell 7 are not supported runtimes.
- Working domain DNS, time synchronization, and the member computer's secure channel.
- Trusted domain controller certificates for the default **Kerberos over LDAPS on TCP 636** connection.
- A dedicated account delegated directory-read access and permission to update the target groups' membership. Do not use Domain Admin credentials.

## Quick start

1. Download and verify the [release ZIP and SHA-256 sidecar](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases/tag/v1.0.0). Use its extracted **`Scripts` folder as the ConfigMgr package source**, then distribute the package. It contains the self-contained [`Add-ComputerToADGroup.ps1`](Scripts/Add-ComputerToADGroup.ps1).
2. Place the script step after domain join and the required restart, once the [requirements](#requirements) are met.
3. Immediately before the script step, create the hidden custom ConfigMgr Task Sequence variables `ADGroupUserName` and `ADGroupPassword` for a dedicated account with delegated group-membership permissions.
4. In **Run PowerShell Script**, set **Script name** to `Add-ComputerToADGroup.ps1` and use this value in **Parameters**:

```text
-GroupName 'Workstation-Certificate-AutoEnroll'
```

5. Clear both credential variables immediately afterward on success **and failure**, and preserve a failed script result.

Read [deployment](docs/deployment.md) for prerequisites, cleanup handling, parameters, and log locations. Complete the [environment-validation checklist](docs/validation.md#required-live-tests) before a staged rollout.

## Outputs and results

| Output | Location or meaning |
|---|---|
| Group membership | Direct membership verified on the same domain controller connection used for the operation |
| Operational log | `AddComputerToADGroup.log` in `_SMSTSLogPath`, falling back to `%WINDIR%\Temp` |
| Exit `0` / `1` | Verified membership in every requested group / initialization or an operation failed |

Successful additions are not rolled back when another group fails. Verification
does not prove replication to other domain controllers. Existing membership is
left in place; retries are bounded. See [architecture](docs/architecture.md) and
[logging](docs/logging.md) for the full contract.

## Documentation

- [Architecture](docs/architecture.md)
- [Compatibility](docs/compatibility.md)
- [Deployment](docs/deployment.md)
- [Development](docs/development.md)
- [Distribution](docs/distribution.md)
- [Examples](examples/README.md)
- [Logging](docs/logging.md)
- [Release process](docs/release-process.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Validation](docs/validation.md)

## Validation and rollout

The v1.0.0 source passes Windows PowerShell 5.1 parser checks, PSScriptAnalyzer, mocked Pester tests, and exact-byte SHA-256 manifest verification. Tests cover parameter validation, LDAP requests, retry decisions, resource cleanup, logging, documentation, and validator process exits without writing to AD. Check [CI](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/actions/workflows/ci.yml) for the status of a specific revision.

**Live ConfigMgr and Active Directory testing was not executed for this release.** Use the [validation checklist](docs/validation.md) to verify your environment before broad deployment.

## Maintainer

**Claudio Mendes** · [@vartaxe](https://github.com/vartaxe) · [vartaxe@outlook.com](mailto:vartaxe@outlook.com)

See [authors and artwork notices](AUTHORS.md).

## Related projects

- [Copy OSD Logs to File Share](https://github.com/vartaxe/ConfigMgr-OSD-CopyOSDLogToFileShare) - companion task-sequence utility ([documentation](https://vartaxe.github.io/ConfigMgr-OSD-CopyOSDLogToFileShare/)).
- [Claudio Mendes / vartaxe](https://vartaxe.github.io/vartaxe/) - profile and project directory ([GitHub](https://github.com/vartaxe)).

## License

MIT. See [LICENSE](LICENSE).
