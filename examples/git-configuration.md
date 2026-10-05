---
title: Git configuration
---

# Git configuration

[Documentation home](../index.md) | [Development](../docs/development.md) | [Deployment](../docs/deployment.md) | [Compatibility](../docs/compatibility.md) | [Validation](../docs/validation.md)

Use your own author identity. Configure it **locally in this repository** when it differs from your usual Git identity; replace the placeholders below with your name and approved email:

```powershell
git config --local user.name "Your Name"
git config --local user.email "you@example.com"
git config --local user.name
git config --local user.email
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
```

Verify the author and committer before committing. Do not copy another contributor's identity. Preserve the project's copyright, license, and upstream attribution when changing files.
