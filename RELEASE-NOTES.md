# Release notes

## v1.0.0

Version 1.0.0 of `Add-ComputerToADGroup.ps1`.

Highlights:

- Kerberos over LDAPS TCP 636
- Domain controller discovery and failover
- Multiple group support
- LDAP filter escaping
- Direct membership detection
- Post-write membership verification
- Transient retry handling
- Permanent error classification
- Dedicated Task Sequence logging
- Explicit compatibility controls for Negotiate authentication and signed, sealed LDAP

Run in full Windows after domain join and restart, as Local System under Windows PowerShell 5.1. Supply only the hidden custom credential variables `ADGroupUserName` and `ADGroupPassword`.

Parser, analyzer, Pester, and CI results are separate from live validation. All required live tests remain pending; review [validation](docs/validation.md), [compatibility](docs/compatibility.md), and [security](SECURITY.md) before deployment.
