# Release notes

## v1.0.0

The supplied `Add-ComputerToADGroup.ps1` remains version 1.0.0. No tag, published release, or live validation is implied.

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

Run in full Windows after domain join and restart, as Local System under Windows PowerShell 5.1. Supply only the hidden custom credential variables `ADGroupUserName` and `ADGroupPassword`.

Parser, analyzer, Pester, and CI results are separate from live validation. All required live tests remain pending; review [validation](docs/validation.md), [compatibility](docs/compatibility.md), and [security](SECURITY.md) before deployment.
