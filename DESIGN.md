# Design

This repository follows the shared ConfigMgr OSD script design principles: focused scripts, explicit variables, package-based PowerShell steps, dedicated logging, bounded retries, and sanitized public support data.

## Related work

Adding a computer to an AD group during OSD is a well-documented community problem. Related implementations:

- Johan Arwidmark (Deployment Research) — ["Back to Basics: Adding the Computer to an AD Group during Deployment"](https://www.deploymentresearch.com/back-to-basics-adding-the-computer-to-an-ad-group-during-deployment/). The commonly referenced version. Runs the step as a different account.
- Jörgen Nilsson (ccmexec.com) — [MEMCM-OSD-Scripts](https://github.com/Ccmexec/MEMCM-OSD-Scripts). ADSI (`adsisearcher`) based.
- Martin Bengtsson (imab.dk) — ["Back to basics: how can I add computers to Active Directory Groups during OSD"](https://www.imab.dk/back-to-basics-how-can-i-add-computers-to-active-directory-groups-during-osd-with-sccm-system-center-configuration-manager/). Calls a custom web service.
- Q's Tech Babble — [PowerShell to add computers to AD security groups during Task Sequences](https://qtechbabble.wordpress.com/2021/07/30/use-powershell-to-add-computer-to-ad-security-group-during-sccm-task-sequence/). Installs the RSAT AD module with `Add-WindowsCapability`, runs `Add-ADGroupMember`, then removes it.

This script differs in three ways:

- Direct LDAP bind over `System.DirectoryServices.Protocols`. Kerberos authentication, LDAPS enforced (TCP 636). No RSAT install, no ADSI, no external web service.
- Domain controller discovery with automatic failover and bounded retry per group.
- Credentials are scoped to the LDAP bind only. The script does not use the Run PowerShell Script step's "run as another account" option, which avoids the token and local-admin issues documented in the Deployment Research write-up above when a step runs as a different account than the task sequence itself.

Trade-off: LDAPS requires domain controllers to have a valid server certificate. Environments without LDAPS configured should use one of the alternatives above instead.
