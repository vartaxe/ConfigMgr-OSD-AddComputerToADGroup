---
title: Distribution
---

# Distribution

[Documentation home](../index.md) | [Development](development.md) | [Deployment](deployment.md) | [Compatibility](compatibility.md) | [Validation](validation.md)

## Release package

Use the [v1.0.0 release](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases/tag/v1.0.0)
for the complete script, documentation, tests, and source manifest. Download its ZIP
and `.zip.sha256` sidecar together. The repository and release package are the
authoritative source; the [release process](release-process.md) describes verification.

This is the new **2026-09-21 v1.0.0 baseline**. Older downloads bearing the same
version label may contain different bytes. Verify the current SHA-256 values
rather than identifying a download by its version label alone.

## Standalone gist

[`Add-ComputerToADGroup.ps1` is also available as a public gist](https://gist.github.com/vartaxe/99dc4be2d6dbf8cda0b93e2de3f0d906).
It contains the same script bytes, a full `LICENSE`, usage notes, and
`SHA256SUMS.txt`. The gist is a snapshot, not an automatic-update channel.

Download the files and verify the script with `Get-FileHash -Algorithm SHA256`
against `SHA256SUMS.txt`. Keep the license with every redistributed copy.
The complete repository's `CHECKSUMS.txt` and the gist's smaller `SHA256SUMS.txt`
cover different file sets; neither replaces the release ZIP's sidecar.

Use Windows PowerShell 5.1 as Local System in an active ConfigMgr task sequence
in full Windows after domain join and restart. Follow the
[deployment guide](deployment.md) for hidden credential variables and native
cleanup on success and failure. Do not treat a raw gist URL as an executable
command or run the deployment entry point as a normal desktop test.

## License

The script remains [MIT licensed](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/blob/main/LICENSE).
Redistribution must retain the copyright and permission notice. Third-party
artwork keeps its own [included notices](../assets/README.md).

Publishing a regular release or a gist is not evidence of live deployment testing.
Live ConfigMgr and Active Directory testing was not executed; use the
[environment-validation checklist](validation.md#required-live-tests) before rollout.
