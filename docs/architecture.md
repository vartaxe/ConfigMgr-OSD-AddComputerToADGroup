---
title: Architecture
---

# Architecture

[Documentation home](../index.md) | [Development](development.md) | [Deployment](deployment.md) | [Compatibility](compatibility.md) | [Validation](validation.md)

<p align="center">
    <picture>
        <source media="(max-width: 960px)" srcset="../assets/addgroup-flow-compact.svg" width="440">
        <img src="../assets/addgroup-flow.svg" alt="Add Computer to AD Group workflow: set hidden variables, validate Windows and secure channel, connect, add and verify membership, then clear variables" width="1200">
    </picture>
</p>

[Open the full-size workflow](../assets/addgroup-flow.svg). The steps and credential-cleanup responsibilities are described below.

The self-contained [`Add-ComputerToADGroup.ps1`](../Scripts/Add-ComputerToADGroup.ps1) runs inside an active ConfigMgr Task Sequence as Local System in full Windows, after domain join and restart.

1. Open `Microsoft.SMS.TSEnvironment`, initialize logging, enforce any requested compatibility policy, and read only the custom credential variables `ADGroupUserName` and `ADGroupPassword`.
2. Trim group names and remove case-insensitive duplicates while retaining input order. Check the computer secure channel before directory discovery on each pass.
3. Discover domain controllers in the computer's domain and connect using Kerberos over LDAPS by default. Controllers in the computer's own Active Directory site are tried first, then the remainder; every discovered controller stays available for failover.
4. Read the domain controller's default naming context and find the local computer account and requested groups by `sAMAccountName`, using escaped LDAP filters.
5. Check direct membership; add the computer to the group's `member` attribute only when missing, then verify on the same connection.
6. Retry unresolved transient failures within the configured pass count. Retain permanent failures and completed results rather than repeating those group operations. Preserve structured directory codes through PowerShell exception wrappers; server message text does not override those codes.
7. Dispose each LDAP connection, log per-group results, and exit `0` only if every requested group succeeded; otherwise exit `1`.

Membership changes are not transactional: if one group fails, earlier successful additions are not rolled back. Nested/transitive membership, primary-group membership, and replication to other domain controllers are not verified. Discovery uses the computer's domain and searches start at the connected controller's default naming context; this is not a cross-forest group-management tool. Site preference affects ordering only: if the local site cannot be determined, discovery falls back to name order and logs a warning.

The script disposes its site, domain, and controller discovery objects after extracting names. It disposes its own secure password when execution ends, including handled failure paths. This does not clear Task Sequence variables or guarantee erasure of every managed credential copy. Creating and clearing those variables remains the responsibility of native Task Sequence steps; see [deployment](deployment.md#credential-lifecycle).

## Implementation references

- [PowerShell exception handling and `finally`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally?view=powershell-5.1): cleanup and wrapped exceptions.
- [.NET Framework `LdapException` constructors](https://learn.microsoft.com/en-us/dotnet/api/system.directoryservices.protocols.ldapexception.-ctor?view=netframework-4.8.1) and [`DirectoryOperationException` constructors](https://learn.microsoft.com/en-us/dotnet/api/system.directoryservices.protocols.directoryoperationexception.-ctor?view=netframework-4.8.1): error codes and responses can coexist with an inner exception.
- [`ActiveDirectoryPartition.Dispose`](https://learn.microsoft.com/en-us/dotnet/api/system.directoryservices.activedirectory.activedirectorypartition.dispose?view=netframework-4.8.1), [`DirectoryServer.Dispose`](https://learn.microsoft.com/en-us/dotnet/api/system.directoryservices.activedirectory.directoryserver.dispose?view=netframework-4.8.1), and [`ActiveDirectorySite.Dispose`](https://learn.microsoft.com/en-us/dotnet/api/system.directoryservices.activedirectory.activedirectorysite.dispose?view=netframework-4.8.1): discovery resource ownership.
- [`SecureString.Dispose`](https://learn.microsoft.com/en-us/dotnet/api/system.security.securestring.dispose?view=netframework-4.8.1): release of the owned secure buffer, not other plaintext copies.
