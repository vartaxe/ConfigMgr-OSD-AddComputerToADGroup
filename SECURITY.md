# Security

## Reporting

**GitHub private vulnerability reporting is enabled.** Use [private vulnerability reporting](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/security/advisories/new) for security issues. If the endpoint is unavailable, contact [vartaxe@outlook.com](mailto:vartaxe@outlook.com) to arrange a private exchange. Do not post vulnerability details in a public issue or send credentials in the initial contact.

Use [GitHub Issues](https://github.com/vartaxe/ConfigMgr-OSD-AddComputerToADGroup/issues) only for non-sensitive bugs and documentation issues. Do not publish unsanitized logs, ZIP archives, command lines, credentials, tokens, certificates, internal server names, or deployment policy data.

## Security model

- Use a dedicated account with read access to the required directory objects and write access to the `member` attribute of only the target groups. Do not grant Domain Admin privileges.
- Mark **both** custom variables `ADGroupUserName` and `ADGroupPassword` as hidden using **Do not display this value**. These are the only credential variables read by the script.
- Do not pass credentials in script parameters, command lines, package content, or source control.
- Keep PowerShell parameter logging disabled for the Task Sequence step; see [deployment](docs/deployment.md).
- Clear both variables immediately afterward, including error paths, using native Task Sequence steps. The script does not clear the Task Sequence variables itself.
- Hidden variables are not a security boundary against a local administrator or Local System. Credentials remain accessible to the Task Sequence process; clearing variables or releasing managed references does not guarantee memory erasure.
- Review sanitized copies of both `AddComputerToADGroup.log` and `smsts.log` before sharing. Directory names and deployment details can still be sensitive. Live confirmation of secret-free logging remains pending.
- Error reporting retains only known credential-free local messages or sanitized LDAP/result codes and exception types, not raw server diagnostics. Log-write failures emit an explicit credential-free warning rather than raw exception text; see [logging](docs/logging.md).

## Authentication and transport

- The default is `-AuthenticationMode Kerberos -DirectoryTransport LDAPS`, using TCP 636 and Windows certificate validation. A trusted, valid domain controller certificate matching its DNS name is required. The script does not bypass certificate validation.
- `-AuthenticationMode Negotiate` requires explicit `-AllowNtlmV2`. This opts into compatibility negotiation; it does **not** force NTLMv2. The LDAP `AuthType` API cannot select an NTLM version or prove which version was negotiated. Enforce policy denying LM and NTLMv1 on clients and domain controllers before using this mode; do not weaken domain policy to make it work.
- The script fails closed unless the local `LmCompatibilityLevel` explicitly allows only NTLMv2 client responses (value `3`, `4`, or `5`). It does not modify policy or inspect DC policy. Those client-side values alone do not prove that servers refuse LM/NTLMv1; configure and verify that refusal separately, as explained in [compatibility](docs/compatibility.md).
- `-DirectoryTransport SignedLdap` explicitly selects TCP 389 with both LDAP signing **and sealing**. It is not clear-text simple bind. Authentication remains Kerberos unless Negotiate is separately selected.
- Compatibility choices are logged. The script never automatically changes authentication or transport after a failure, performs password-based simple bind, or enables unsigned/unsealed LDAP.

The script does not retrieve Network Access Account credentials or reserved ConfigMgr credential variables, and does not use external credential helpers. See [compatibility](docs/compatibility.md) for prerequisites and limitations.
