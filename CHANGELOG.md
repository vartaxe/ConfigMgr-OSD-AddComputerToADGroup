# Changelog

## v1.0.0 (pre-release)

- Initial version of the self-contained Windows PowerShell 5.1 Task Sequence script.
- Kerberos over LDAPS by default, with explicit authentication and transport compatibility controls.
- Direct computer-group membership checks, additions, verification, domain controller failover, and bounded retry passes.
- Site-aware domain controller ordering that prefers the computer's own Active Directory site and falls back to name order when the site cannot be determined.
- CMTrace-format logging and documented custom credential variables.
- Credential-free computer lookup diagnostics, retaining bounded retries for post-join account visibility.
- Parser, PSScriptAnalyzer, and Pester validation tooling, plus Windows-based CI.
- Deployment, security, troubleshooting, and pending live-validation documentation.

These entries describe included functionality and tooling, not a published release or completed live tests. See [validation](docs/validation.md).
