# Support

This project is provided as open-source tooling without guaranteed support.

Version 1.0.0 is published as a GitHub prerelease. Its completed static checks, mocked Pester tests, checksum verification, and GitHub Actions runs are not live platform certification; live ConfigMgr and Active Directory validation remains pending.

Before opening an issue:

- For source changes, run `.\build\Invoke-Validation.ps1` in Windows PowerShell 5.1; see [validation](docs/validation.md).
- Confirm the package was distributed to the required distribution points.
- Confirm the ConfigMgr Task Sequence step references the packaged script.
- Sanitize logs before sharing.

Use the [issue forms](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/issues/new/choose) for bugs, compatibility reports, and feature requests. Include the script version, ConfigMgr/Windows versions, Windows PowerShell version, post-domain-join restart status, and sanitized error context. Do not assume CI proves live compatibility.

For vulnerabilities, use the enabled [private reporting](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/security/advisories/new) endpoint instead of posting a public issue. If it is unavailable, contact [vartaxe@outlook.com](mailto:vartaxe@outlook.com) to arrange a private exchange; see [security](SECURITY.md). Maintainer: [Claudio Mendes (@vartaxe)](https://github.com/vartaxe).
