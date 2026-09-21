---
title: Release process
---

# Release process

[Documentation home](../index.md) | [Development](development.md) | [Deployment](deployment.md) | [Compatibility](compatibility.md) | [Validation](validation.md)

Prepare **v1.0.0** for a regular GitHub release in two stages. The existing workflow publishes a **prerelease candidate**. The maintainer verifies downloaded assets and approves promotion to **regular/latest**. The workflow does not perform the promotion.

Release status is a distribution choice, not platform certification. Live ConfigMgr and Active Directory testing was not executed; that limitation belongs in the release notes and [validation checklist](validation.md#required-live-tests).

Use a new numeric version for changed distributed files. Never silently replace a published tag, ZIP, or sidecar. Existing downloads do not update when `main` changes.

The maintainer explicitly authorized the **2026-09-21 v1.0.0 baseline reset**.
That reset is disclosed in the release notes and distribution guide; earlier
downloads with the same label may differ. It is not permission to silently replace
future release bytes. Verify the current archive hash and advance the version for
later changes.

Preparing a version does **not** publish it. Candidate publication is an explicit, approved action: either push a matching `vX.Y.Z` tag or manually dispatch the `Release` workflow for an **existing** tag. Merging a pull request never publishes a release, and a successful workflow run does not approve promotion.

`vX.Y.Z` is a placeholder for `v` followed by a three-part numeric version. The current validation command below uses the actual target, `v1.0.0`.

## Prepare the version

1. Review the complete runtime, file list, and diff. Keep the production script self-contained. Align `VERSION`, the script's literal version and help, badges, and current documentation. Keep a matching `## v1.0.0` section in [`RELEASE-NOTES.md`](../RELEASE-NOTES.md); the workflow publishes only the selected tag's section and rejects missing or empty notes.
2. Record automated results separately from live results. Obtain approval for any unperformed environment checks, whether distributing a regular release or another release type. Never infer production readiness from local checks, mocks, CI, or the release label.
3. Verify the [private reporting endpoint](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/security/advisories/new) and retain the email fallback in [security](../SECURITY.md). Review public identity, links, copyright, upstream credit, and sensitive content.
4. Normalize source bytes and regenerate `CHECKSUMS.txt` **last** using the recipe below. Keep ZIPs, local reports, test output, and generated Pages files outside the source tree.
5. Run full validation in Windows PowerShell 5.1 with the pinned development modules:

   ```powershell
   powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\build\Invoke-Validation.ps1 -Tag v1.0.0
   ```

   This checks parsing, analyzer results, every Pester test, the manifest, and tag/version agreement. Final validation must not use `-SkipChecksums`. Resolve parser errors, analyzer findings, failed discovery, and failed, skipped, or not-run tests.
6. Review and merge through the maintainer-approved process. Require CI for the final revision. After further content or line-ending changes, regenerate the manifest and repeat validation.

## Stage 1: Publish the prerelease candidate

After source review and approval, use the existing tag-triggered workflow or manually dispatch it for an approved existing tag. It validates the tagged checkout, creates `<Project>-v<Version>.zip` and its `.zip.sha256` sidecar, and publishes them as a **prerelease candidate**. This is not final regular-release approval.

Checkout and archiving select `refs/tags/<tag>` so a same-named branch cannot supply different code. The validator checks version agreement. GitHub CLI's [`--verify-tag` and `--prerelease`](https://cli.github.com/manual/gh_release_create) require the remote tag to exist and retain candidate status. The workflow does not mark the candidate latest.

## Stage 2: Verify assets and approve promotion

1. Download the candidate's uploaded ZIP and matching sidecar from GitHub. Check the ZIP's SHA-256 against that sidecar; do not substitute GitHub's automatically generated source archive.
2. Expand the downloaded ZIP outside the working source tree. Verify its complete file set and exact bytes against `CHECKSUMS.txt`, and run the tagged Windows PowerShell 5.1 validator from the extracted root. Checkout validation alone does not establish archive-byte integrity. Any failed check blocks promotion.
3. Record the source revision, tag, archive hash, test results, and remaining environment-validation limits. Obtain explicit maintainer approval for the verified candidate.
4. The maintainer, **vartaxe**, promotes that existing release through GitHub's [Update a release REST API](https://docs.github.com/en/rest/releases/releases#update-a-release), setting `prerelease` to `false` and `make_latest` to `"true"`. Use the verified release ID and existing authorized repository access. Do not broaden access, switch identities, change the tag, or replace asset bytes as part of promotion.
5. Confirm that the release is no longer a prerelease, that the repository's latest-release endpoint selects the approved tag, and that the downloadable assets retain their verified hashes.

Keep the candidate in prerelease status if verification, authorization, or approval is incomplete. Promotion changes release metadata only; it does not add live-test evidence. See GitHub's [release-management guidance](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).

## Checksum checkout convention

`CHECKSUMS.txt` hashes the **checked-out file bytes**. Follow [`.gitattributes`](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/blob/main/.gitattributes): PowerShell `.ps1` files use **CRLF**; other text files use **LF**, including Markdown, YAML, SVG, `LICENSE`, and `VERSION`. These repository rules avoid dependence on a contributor's global `core.autocrlf` setting.

Normalize files before generating the manifest. From the source root, use Windows PowerShell 5.1:

```powershell
$Root = (Get-Location).Path
[string[]]$Entries = @(
    Get-ChildItem -LiteralPath $Root -Force |
        Where-Object { $_.Name -notin @('.git', 'CHECKSUMS.txt') } |
        ForEach-Object {
            if ($_.PSIsContainer) {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force
            }
            else { $_ }
        } |
        ForEach-Object {
            $RelativePath = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
            '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $RelativePath
        }
)
[Array]::Sort($Entries, [StringComparer]::Ordinal)
[IO.File]::WriteAllText(
    (Join-Path $Root 'CHECKSUMS.txt'),
    (($Entries -join "`n") + "`n"),
    [Text.UTF8Encoding]::new($false))
```

The manifest includes dotfiles and even ignored artifacts present under the root. Exclude only root `.git` metadata and `CHECKSUMS.txt`. Each entry is a full SHA-256 hash, exactly two spaces, and a relative slash-separated path; complete lines are sorted hash first and written as UTF-8 without a BOM, with LF endings.

Keep the existing `git archive` packaging path; it honors this repository's `.gitattributes`. Regenerate and verify checksums after every content or line-ending change. Verify the downloadable candidate and obtain maintainer approval before promoting it to regular/latest.
