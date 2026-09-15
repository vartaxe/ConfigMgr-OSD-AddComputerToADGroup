# Release notes

## v1.0.0

Version 1.0.0 is [published as a GitHub prerelease](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases/tag/v1.0.0). Live ConfigMgr and Active Directory validation remains pending.

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
