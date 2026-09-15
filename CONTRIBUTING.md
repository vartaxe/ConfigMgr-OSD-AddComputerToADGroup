# Contributing

Contributions are welcome when they keep the project focused, readable, and safe for ConfigMgr Task Sequence use.

Live ConfigMgr and Active Directory validation remains pending for the published v1.0.0 prerelease. Its completed static checks, mocked Pester tests, checksum verification, and GitHub Actions runs do not establish live compatibility.

Before opening a pull request:

1. Install the pinned development modules and run `.\build\Invoke-Validation.ps1` in Windows PowerShell 5.1 as described in [validation](docs/validation.md).
2. Keep examples generalized.
3. Do not add organization-specific defaults.
4. Do not introduce credential logging.
5. Update documentation when behavior changes.
6. Add focused Pester coverage for behavioral fixes, and distinguish mocks from live tests.
7. Regenerate `CHECKSUMS.txt` after all file changes, including documentation and workflow updates, following the [checkout convention](docs/release-process.md#checksum-checkout-convention). Run validation again before pushing.

Regenerate the manifest before full-tree validation. `-SkipChecksums` skips only the validator's final checksum phase; repository-contract tests still verify the manifest independently. Final validation must run without that switch.

The production script must remain self-contained, target Windows PowerShell 5.1, and retain secure defaults. Review analyzer warnings individually; any suppression needs a precise justification. Never include credentials or unsanitized logs in a pull request.

## Source and presentation conventions

- Start standalone production and build scripts with `#Requires -Version 5.1`, a blank line, then comment-based help. The blank line preserves help binding in Windows PowerShell 5.1. Follow with attributes and parameters, strict/error setup, state, functions, orchestration, and explicit exit as applicable. Pester containers retain their test-specific structure.
- Use four-space PowerShell indentation and spaces around assignments and after commas; YAML uses two spaces. Follow `.editorconfig` and `.gitattributes`: PowerShell files use CRLF, other maintained text uses LF. Use the pinned PSScriptAnalyzer formatter for focused whitespace changes, not a repository-wide style rewrite.
- Keep formatting separate from behavior changes. Preserve executable tokens, AST structure, runtime strings, parameter defaults, and output contracts; verify help with both the parser and `Get-Help` without executing the entry points. Add comments only when they explain non-obvious intent.
- Preserve the README's reader journey and the project's purple/blue accent. Keep diagrams readable in light and dark themes, separate number markers from labels, and retain titles, descriptions, text equivalents, and full-size links. Status must be meaningful without color, and illustrations must never imply unrecorded live validation.

Make documentation corrections through pull requests against `main`, not by changing the immutable `v1.0.0` tag or its published assets. See the [release process](docs/release-process.md) for future releases.
