# Repository guidance

## Architecture and compatibility

- Treat the live working tree as authoritative and inspect related scripts,
  tests, documentation, and generated artifacts before editing.
- Keep `Scripts/Add-ComputerToADGroup.ps1` compatible with Windows PowerShell
  5.1 and ConfigMgr task-sequence execution in full Windows.
- Preserve existing public parameters, task-sequence variables, exit behavior,
  CMTrace logging, and secure defaults unless the requested change explicitly
  changes a documented contract.
- Keep `VERSION`, script version metadata, release notes, documentation, and
  release workflow expectations consistent.

## Security and reliability

- Never log credentials, secrets, internal directory identifiers, or raw
  credential-bearing exceptions.
- Preserve fail-closed LDAP behavior, bounded retries, explicit compatibility
  switches, certificate validation, signing/sealing requirements, and resource
  disposal.
- Do not imply live Active Directory or ConfigMgr validation when only static,
  mocked, or CI validation was performed.

## Validation

- Run `build/Invoke-Validation.ps1` with Windows PowerShell 5.1.
- Use Pester 6.2.0 and keep all tests fully passing with no skipped or not-run
  cases.
- Regenerate `CHECKSUMS.txt` after maintained files change; do not bypass its
  final verification for completion.
- Run `build/Update-Banners.ps1 -Check` when banner inputs or generated artwork
  may be affected.
