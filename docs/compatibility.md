---
title: Compatibility
---

# Compatibility

[Documentation home](../index.md) | [Development](development.md) | [Deployment](deployment.md) | [Compatibility](compatibility.md) | [Validation](validation.md)

| Status | Platform / requirement |
|---|---|
| Target runtime | Windows PowerShell 5.1 in a supported ConfigMgr Task Sequence, as Local System in full Windows after domain join **and restart** |
| Platform candidates | Windows client and Windows Server 2016 or later versions supported by the deployed ConfigMgr release |
| Legacy, best effort | Windows Server 2012/2012 R2 with **WMF 5.1**; this does not extend Microsoft lifecycle or ConfigMgr support |
| Unsupported runtime | WinPE, PowerShell 7, standalone execution outside an active Task Sequence, or domain controllers as deployment targets |
| Not permitted | LM/NTLMv1, password-based LDAP simple bind, unsigned/unsealed LDAP, certificate-validation bypass |

**Live ConfigMgr and Active Directory testing was not executed.** This table describes prerequisites and scope, not certified platforms. Verify the [environment checklist](validation.md#required-live-tests) for your ConfigMgr release and Windows build.

[`Test-ComputerSecureChannel`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-computersecurechannel?view=powershell-5.1) is used for member-computer readiness; Microsoft documents false-positive errors on domain controllers, which are not supported deployment targets.

## Secure default

```text
-GroupName 'Workstation-Certificate-AutoEnroll'
```

This selects `-AuthenticationMode Kerberos -DirectoryTransport LDAPS` on TCP 636. Ensure domain DNS, time synchronization, an operational computer secure channel, delegated group permissions, and trusted domain controller certificates. There is no automatic authentication or transport fallback.

## Explicit compatibility options

Use only after reviewing policy and testing in a controlled environment. Nondefault modes are logged.

### Negotiate authentication

```text
-GroupName 'Workstation-Certificate-AutoEnroll' -AuthenticationMode Negotiate -AllowNtlmV2
```

Negotiate may choose Kerberos or NTLM. `-AllowNtlmV2` is explicit permission to use this compatibility mode, **not an NTLMv2 selector or proof of the negotiated protocol**. The LDAP `AuthType` API cannot force an NTLM version. Enforce **Network security: LAN Manager authentication level = Send NTLMv2 response only. Refuse LM & NTLM** on clients and domain controllers before use. Other domain restrictions may still deny NTLM entirely; this switch does not override them.

Before reading credentials or binding, the script checks the local `LmCompatibilityLevel` registry value under `HKLM:\SYSTEM\CurrentControlSet\Control\Lsa`. Configure it explicitly as a **DWORD with value 3, 4, or 5**, which selects NTLMv2-only client responses. Missing/unreadable policy, values **0-2**, and invalid values fail closed with an error; the script never changes OS policy. This prerequisite applies only to Negotiate: the default Kerberos path is unaffected.

That client-side check does **not** inspect domain controller policy or prove server-side LM/NTLMv1 refusal: values 3 and 4 are not equivalent to value 5 for what a DC accepts. Enforce server-side refusal separately; value **5** represents the policy stated above. The script cannot attest the protocol actually negotiated.

See Microsoft's [LAN Manager authentication level policy](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/network-security-lan-manager-authentication-level). Do not lower policy or assume a missing setting is safe.

### Signed and sealed LDAP

```text
-GroupName 'Workstation-Certificate-AutoEnroll' -DirectoryTransport SignedLdap
```

This explicitly selects TCP 389 with **both signing and sealing** and retains Kerberos authentication. It does not use TLS; confidentiality comes from negotiated session sealing. It is not an LDAPS failure fallback and never uses clear-text password simple bind.

If both compatibility options are needed, specify them together:

```text
-GroupName 'Workstation-Certificate-AutoEnroll' -AuthenticationMode Negotiate -AllowNtlmV2 -DirectoryTransport SignedLdap
```

Validate each compatibility mode you intend to use; a successful default-mode test does not establish the others. See [security](../SECURITY.md) and the [environment-validation checklist](validation.md#required-live-tests).
