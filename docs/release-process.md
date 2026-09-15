# Release process

Version 1.0.0 is already [published as a GitHub prerelease](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases/tag/v1.0.0). Its parser, PSScriptAnalyzer, mocked Pester, SHA-256 manifest, and GitHub Actions checks passed; live ConfigMgr and Active Directory validation remains pending.

This checklist is for **future releases**. The existing `v1.0.0` tag and published assets are immutable. Documentation corrections on `main` do not alter that snapshot or its release ZIP.

Preparing a version does **not** publish it. Publication is an explicit, approved action: either push a matching `vX.Y.Z` tag or manually dispatch the `Release` workflow for an **existing** tag. Merging a pull request never publishes a release.

Throughout this guide, `vX.Y.Z` is a documentation placeholder. Replace it with the intended numeric version tag before executing any command or adding a release-notes heading. The validator accepts only `v` followed by a three-part numeric version, not the literal `vX.Y.Z`.

1. Review the complete file list and diff, keeping the production script self-contained. Align `VERSION` and the production script's literal version. Add a matching `## vX.Y.Z` section to [`RELEASE-NOTES.md`](../RELEASE-NOTES.md); the `Release` workflow publishes only that section and fails if it is missing or empty.
2. Review and record the [live environment checklist](validation.md). Complete the required tests before claiming live compatibility; any tests still pending require explicit review and approval as a prerelease limitation and must remain clearly marked in its notes. Local checks, mocks, and CI results are not substitutes for live evidence.
3. Recheck that GitHub private vulnerability reporting remains enabled and verify the [private reporting endpoint](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/security/advisories/new). Enablement was verified for v1.0.0; recheck it for each future release. Retain the maintainer-email fallback in [security](../SECURITY.md), support guidance, and issue forms in case the endpoint becomes unavailable.
4. Check public identity, links, sensitive content, and the full diff. Keep generated ZIPs, local reports, and validation output outside the source tree and out of source control.
5. Regenerate `CHECKSUMS.txt` **last**, after all source and documentation edits, using SHA-256 for every maintained file, including dotfiles, except root `.git` metadata and the manifest itself. Each entry must contain the hash, exactly two spaces, and a relative forward-slash path. Sort the complete hash/path lines deterministically (hash first), and write UTF-8 without a BOM with LF endings. Verify every entry exists and matches, entries are unique, and no maintained file is omitted.
6. Run full validation in Windows PowerShell 5.1 with the pinned development modules from [validation](validation.md). Use an approved package source and retain publisher verification; do not bypass it.

   ```powershell
   .\build\Invoke-Validation.ps1
   ```

   This checks every PowerShell file with the parser, analyzes `Scripts`, `Tests`, and `build`, runs all Pester tests, compares `VERSION` with the production script version, and verifies `CHECKSUMS.txt`. Final validation must not use `-SkipChecksums`; parser errors, analyzer warnings/errors, and failed, skipped, or not-run tests must be resolved.
7. Check the proposed numeric tag as well, replacing the placeholder before running:

   ```powershell
   .\build\Invoke-Validation.ps1 -Tag 'vX.Y.Z'
   ```

   This repeats full validation and additionally checks the supplied tag's format and agreement with `VERSION` and the production script version. Neither command creates a tag or publishes a release. The `CI` workflow repeats the tag comparison on tag pushes but never creates a tag or release.
8. Review and merge through the maintainer-approved pull request process. After any further content or line-ending changes, regenerate the manifest and rerun both validation commands.
9. Push a matching `vX.Y.Z` tag only after the final checks, live-checklist status, and release notes are approved. Alternatively, manually dispatch the `Release` workflow for an approved **existing** tag. The workflow revalidates the tagged revision, creates `<Project>-v<Version>.zip` and `<Project>-v<Version>.zip.sha256`, and publishes a GitHub prerelease.

Checkout and archiving explicitly select `refs/tags/<tag>`, so a same-named branch cannot supply different code. The validator checks tag/version agreement. `--verify-tag` requires the remote tag to exist and prevents release creation from creating a tag.

## Checksum checkout convention

`CHECKSUMS.txt` hashes the **checked-out file bytes**. Follow [`.gitattributes`](../.gitattributes): PowerShell `.ps1` files use **CRLF**; other text files use **LF**, including Markdown, YAML, SVG, `LICENSE`, and `VERSION`. These repository rules avoid dependence on a contributor's global `core.autocrlf` setting.

Normalize files to that convention before the final manifest generation, then verify the hashes against a fresh checkout or staged export that honors `.gitattributes`. Recheck after any content or line-ending change. Raw Git blobs or source archives may use different line endings and must not be assumed byte-identical to the checked-out files.

Approved releases are published at [GitHub Releases](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/releases) by a deliberate tag push or manual workflow dispatch for an existing tag. Both are publication actions; do not initiate either for a revision with failed checks or unapproved live-validation gaps.
