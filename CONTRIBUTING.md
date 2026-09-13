# Contributing

Contributions are welcome when they keep the project focused, readable, and safe for ConfigMgr Task Sequence use.

Before opening a pull request:

1. Install the pinned development modules and run `.\build\Invoke-Validation.ps1` in Windows PowerShell 5.1 as described in [validation](docs/validation.md).
2. Keep examples generalized.
3. Do not add organization-specific defaults.
4. Do not introduce credential logging.
5. Update documentation when behavior changes.
6. Add focused Pester coverage for behavioral fixes, and distinguish mocks from live tests.

The production script must remain self-contained, target Windows PowerShell 5.1, and retain secure defaults. Review analyzer warnings individually; any suppression needs a precise justification. Never include credentials or unsanitized logs in a pull request.
