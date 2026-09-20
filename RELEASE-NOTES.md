# Release notes

## v1.0.0

Version 1.0.0 is [published as a GitHub prerelease](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases/tag/v1.0.0). Live ConfigMgr and Active Directory validation remains pending.

### Reissue: 2026-09-20

This maintainer-authorized prerelease reissue replaces the tag, ZIP, and SHA-256 sidecar first published on 2026-09-15. It includes the merged documentation and diagram improvements, discoverable PowerShell help, consistent source formatting, and the diagnostic-stream correction that prevents warnings from being interpreted as domain-controller names. Version remains 1.0.0; authentication and transport defaults are unchanged.

Previously downloaded copies do not update automatically and have different contents under the same version number. Download the ZIP and sidecar together and verify the new SHA-256. The release page records the exact reissued commit and archive hash.

For identification, the original archive SHA-256 was `540B39AF1593AF80AB3FE85E1CEAD812D26811642FDCF47F668D1BA482E9AD69`. Its tag previously selected commit `1f023396296699fee914ea4384c8c0a0463fea63`. Neither identifies this reissue.

Highlights:

- Kerberos over LDAPS TCP 636
- Domain controller discovery and failover
- Site-aware domain controller ordering with name-order fallback
- Multiple group support
- LDAP filter escaping
- Direct membership detection
- Post-write membership verification
- Transient retry handling
- Permanent error classification
- Dedicated Task Sequence logging
- Explicit compatibility controls for Negotiate authentication and signed, sealed LDAP

Run in an active ConfigMgr Task Sequence in full Windows after domain join and restart, as Local System under Windows PowerShell 5.1. Supply only the hidden custom credential variables `ADGroupUserName` and `ADGroupPassword`. Clear both variables immediately afterward on success and failure, and preserve failed script results.

For the published version, Windows PowerShell 5.1 parser checks, PSScriptAnalyzer, mocked Pester tests, SHA-256 manifest verification, and GitHub Actions passed. These results are separate from live validation. All required live tests remain pending; review [validation](docs/validation.md), [compatibility](docs/compatibility.md), and [security](SECURITY.md) before deployment.
