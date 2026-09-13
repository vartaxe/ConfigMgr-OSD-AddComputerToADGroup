# Release checklist

- [ ] Extract repository package to a clean folder.
- [ ] Run `Test-Script.ps1` in Windows PowerShell 5.1.
- [ ] Confirm PowerShell parser passes.
- [ ] Confirm PSScriptAnalyzer passes.
- [ ] Confirm required and forbidden pattern checks pass.
- [ ] Rebuild `CHECKSUMS.txt`.
- [ ] Attach only the clean release ZIP to GitHub releases.
- [ ] Do not attach development, test, RC, or internal packages.
