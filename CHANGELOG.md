# Changelog

## v1.0.0 (prerelease)

- Initial GitHub prerelease of the self-contained Windows PowerShell 5.1 ConfigMgr Task Sequence script.
- Kerberos over LDAPS by default, with explicit authentication and transport compatibility controls.
- Direct computer-group membership checks, additions, verification, domain controller failover, and bounded retry passes.
- Site-aware domain controller ordering that prefers the computer's own Active Directory site and falls back to name order when the site cannot be determined.
- CMTrace-format logging and documented custom credential variables.
- Credential-free computer lookup diagnostics, retaining bounded retries for post-join account visibility.
- Parser, PSScriptAnalyzer, and Pester validation tooling, plus Windows-based CI.
- Deployment, security, troubleshooting, and pending live-validation documentation.

The published v1.0.0 passed parser, PSScriptAnalyzer, mocked Pester, SHA-256 manifest, and GitHub Actions checks. These do not establish live ConfigMgr or Active Directory compatibility; all required live tests remain pending. See [validation](docs/validation.md).
