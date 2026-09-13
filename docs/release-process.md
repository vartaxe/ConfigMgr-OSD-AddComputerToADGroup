# Release process

Version 1.0.0 preparation does **not** create a tag or publish a release. Keep release creation separate from validation and require explicit maintainer approval for any future publication.

1. Review the complete file list and diff, keeping the production script self-contained.
2. Run `.\build\Invoke-Validation.ps1` in Windows PowerShell 5.1 with the pinned development modules. It checks every PowerShell file with the parser, analyzes `Scripts`, `Tests`, and `build`, and runs all Pester tests.
3. Check the proposed version without creating a tag:

   ```powershell
   .\build\Invoke-Validation.ps1 -Tag 'v1.0.0'
   ```

   Tag validation compares the proposed tag, `VERSION`, and the production script version. CI performs the same comparison on tag pushes; it never creates a tag or release.
4. Complete and record the [live environment checklist](validation.md). Local checks, mocks, and CI results are not substitutes for it.
5. Recheck that GitHub private vulnerability reporting remains enabled and verify the [private reporting endpoint](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/security/advisories/new). **Enablement has been verified.** Retain the maintainer-email fallback in [security](../SECURITY.md), support guidance, and issue forms in case the endpoint becomes unavailable.
6. Check public identity, links, sensitive content, and the full diff. Keep generated ZIPs, local reports, and validation output out of source control.
7. Regenerate `CHECKSUMS.txt` **last**, using SHA-256 and relative forward-slash paths for every maintained file except the manifest itself. Verify every entry exists and matches, entries are unique, and no maintained file is omitted.
8. Review and merge through the maintainer-approved pull request process. Push a matching `vX.Y.Z` tag only after the live checklist and release notes are approved. The `Release` workflow validates the tag, creates a source archive and SHA-256 sidecar, and publishes a GitHub prerelease.

## Checksum checkout convention

`CHECKSUMS.txt` hashes the **checked-out file bytes**. Follow [`.gitattributes`](../.gitattributes): PowerShell `.ps1` files use **CRLF**; other text files use **LF**, including Markdown, YAML, SVG, `LICENSE`, and `VERSION`. These repository rules avoid dependence on a contributor's global `core.autocrlf` setting.

Normalize files to that convention before the final manifest generation, then verify the hashes against a fresh checkout or staged export that honors `.gitattributes`. Recheck after any content or line-ending change. Raw Git blobs or source archives may use different line endings and must not be assumed byte-identical to the checked-out files.

Approved releases are published at [GitHub Releases](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases) by the tag-triggered workflow. A tag is a publication action; do not push one for an unapproved or incompletely validated revision.
