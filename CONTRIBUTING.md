---
title: Contributing
---

# Contributing

Keep contributions focused, readable, and safe for ConfigMgr Task Sequence use.
Follow the [code of conduct](CODE_OF_CONDUCT.md) when discussing changes.

Separate automated evidence from live results. The current v1.0.0 source has static and mocked coverage; live ConfigMgr and Active Directory testing was not executed.

Before opening a pull request:

1. Use the pinned development modules and Windows PowerShell 5.1 described in [validation](docs/validation.md). Install modules only if the required versions are missing.
2. Use generic examples and keep environment-specific values configurable.
3. Keep credentials out of logs and pull requests.
4. Update documentation when behavior changes.
5. Add focused Pester coverage for behavioral fixes, and distinguish mocks from live tests.
6. Regenerate `CHECKSUMS.txt` after all file changes, including documentation and workflow updates, following the [checkout convention](docs/release-process.md#checksum-checkout-convention). Run validation again before pushing.

Regenerate the manifest before full-tree validation. `-SkipChecksums` skips only the validator's final checksum phase; repository-contract tests still verify the manifest independently. Final validation must run without that switch.

The production script must remain self-contained, target Windows PowerShell 5.1, and retain secure defaults. Review analyzer warnings individually; any suppression needs a precise justification. Never include credentials or unsanitized logs in a pull request.

## Documentation and reuse

- Follow [Microsoft's style and voice guidance](https://learn.microsoft.com/en-us/style-guide/top-10-tips-style-voice). Use sentence-case headings, active verbs, and concise steps. Lead with prerequisites, safe defaults, and the operator's next action.
- Describe the tools and actions the reader needs. Include restrictions when they prevent mistakes, protect data, or explain a supported-runtime boundary; omit inventories of unrelated tools.
- Check upstream licenses before reusing code or artwork. Preserve copyright, license notices, and required credit for approved reuse.

## Source and presentation conventions

- Start standalone production and build scripts with `#Requires -Version 5.1`, a blank line, then comment-based help. The blank line preserves help binding in Windows PowerShell 5.1. Follow with attributes and parameters, strict/error setup, state, functions, orchestration, and explicit exit as applicable. Pester containers retain their test-specific structure.
- Use four-space PowerShell indentation and spaces around assignments and after commas; YAML and JSON use two spaces. Follow `.editorconfig` and `.gitattributes`: PowerShell files use CRLF, other maintained text uses LF. Use the pinned PSScriptAnalyzer formatter for focused whitespace changes, not a repository-wide style rewrite.
- Keep formatting separate from behavior changes. Preserve executable tokens, AST structure, runtime strings, parameter defaults, and output contracts; verify help with both the parser and `Get-Help` without executing the entry points. Add comments only when they explain non-obvious intent.
- Preserve the README's reader journey and the shared Cayman blue/teal palette: `#155799` to `#117865` in light banners, `#0d2e4c` to `#103d38` in dark banners. Keep diagrams readable in light and dark themes, separate number markers from labels, and retain titles, descriptions, text equivalents, and full-size links. Status must be meaningful without color, and illustrations must never imply unrecorded live validation.
- GitHub Pages builds from `main` at the repository root; the theme does not change GitHub's README rendering. Keep the purpose-built [documentation home](index.md) distinct from the README. Shared layout, stylesheet, and favicon must stay aligned with the [profile site](https://github.com/vartaxe/vartaxe) and companion OSD repository.
- Use relative Markdown links to maintained `.md` guides so `jekyll-relative-links` can generate Pages URLs. In Liquid-generated HTML or `_config.yml` buttons, use the final `.html` URL with the correct base URL instead. Link excluded source files and dotfiles through GitHub, not through nonexistent Pages paths. Keep explicit front matter on contributor and conduct pages so Jekyll renders them, and retain the examples index's `/examples/` permalink.
- Keep Jekyll output (`_site`, `.jekyll-cache`, `.jekyll-metadata`, `.sass-cache`) out of the source tree during checksum generation and full validation. Ignoring these artifacts in Git does not exclude them from the validator's exact-file manifest contract.

Submit changes against `main`. Changes to distributed files require a new version; never silently replace a published tag or asset. See the [release process](docs/release-process.md).
