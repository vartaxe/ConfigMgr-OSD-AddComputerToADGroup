# Changelog

## 1.1.0 - 2026-08-05

- Treat discovered domain controller names as fully qualified DNS host names, so Kerberos builds the correct service principal name.
- Stop connecting to further domain controllers once every requested group has been resolved.
- Document the LDAPS and delegation prerequisites in DEPLOYMENT.md.
- Document related community implementations and the trade-offs of this approach in DESIGN.md.

## 1.0.0 - 2026-08-04

- Initial validated release.
