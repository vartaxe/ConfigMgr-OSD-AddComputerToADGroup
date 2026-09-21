# Release notes

## v1.0.0

This is the **2026-09-21 v1.0.0 baseline**, published after an explicit maintainer
version reset. Earlier downloads with the same version label may contain different
bytes. Identify this baseline by its current release SHA-256 values, not the label alone.

### Included

- The reviewed, self-contained Windows PowerShell 5.1 script with Kerberos/LDAPS,
  direct membership verification, bounded retries, and CMTrace logging.
- Matching documentation, responsive artwork, editor tasks, and automated tests.
- A [public standalone gist](https://gist.github.com/vartaxe/99dc4be2d6dbf8cda0b93e2de3f0d906)
  with the same script bytes, MIT license, and checksum file.

Runtime behavior and security defaults are unchanged from the reviewed source.
The script remains MIT licensed; required third-party asset notices are retained.

### Deployment

Use Windows PowerShell 5.1 as Local System in an active ConfigMgr task sequence,
in full Windows after domain join and restart. Kerberos over LDAPS remains the
default. Preserve native success/failure credential cleanup and the saved result.
Check the [deployment guide](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/blob/v1.0.0/docs/deployment.md)
before changing an existing package-source layout.

### Verification and publication

Validation covers parsing, static analysis, Pester, generated artwork, version/tag
agreement, and exact-byte source checksums. The existing workflow creates a
prerelease candidate; downloaded-asset verification and explicit maintainer
approval precede regular/latest promotion without changing the tag or asset bytes.

Live ConfigMgr and Active Directory testing was not executed. A regular release
does not certify your environment. Use the
[validation checklist](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/blob/v1.0.0/docs/validation.md)
before broad rollout.

See [development](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/blob/v1.0.0/docs/development.md)
for workstation setup and [release process](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/blob/v1.0.0/docs/release-process.md)
for package verification and approval.
