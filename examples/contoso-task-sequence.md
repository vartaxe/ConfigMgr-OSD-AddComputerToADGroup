# Contoso Task Sequence example

```text
Complete domain join and restart into full Windows
Set hidden ADGroupUserName and ADGroupPassword
Run Add-ComputerToADGroup.ps1
Clear both custom credential variables on success and failure
Handle the preserved script result
```

Set `ADGroupUserName` to `CONTOSO\svc-configmgr-adgroups` and enter that account's password in `ADGroupPassword` through approved Task Sequence administration. Select **Do not display this value** for **both** variables. Do not put the password in a command line or package.

Run the packaged `Scripts\Add-ComputerToADGroup.ps1` as Local System using Windows PowerShell 5.1 with these **Run PowerShell Script** parameters:

```text
-GroupName 'Workstation-Certificate-AutoEnroll'
```

The default is Kerberos over LDAPS TCP 636; the group name is a `sAMAccountName`. This example is a deployment pattern, not a recorded live test. See [deployment](../docs/deployment.md) for permissions, logging, and cleanup handling, and [compatibility](../docs/compatibility.md) for separate opt-in examples.
