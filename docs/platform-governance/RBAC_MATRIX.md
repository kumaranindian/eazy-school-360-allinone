# RBAC matrix (new capabilities)

| Capability | Owner | Support | Compliance | Viewer | School admin | Branch admin / teacher / finance / parent |
|---|---|---|---|---|---|---|
| Activate / deactivate / suspend / close school | yes | no | no | no | no | no |
| Reactivate / expire (manual) | yes | no | no | no | no | no |
| Set subscription, plan, dates, grace, trial, cancel | yes | no | no | no | no | no |
| View subscription and history | yes | yes | yes | yes | own school, read-only | no |
| Enable/disable features, global defaults | yes | no | no | no | no | no |
| View feature configuration/history | yes | yes | yes | yes | own school, read-only | no |
| Platform notifications: publish | yes | yes | no | no | no | no |
| Platform notifications: read / acknowledge | all | all | all | all | own, yes | no |
| Audit: global dashboard, search, history | yes | schools they support (read) | yes | no | **own school only, read** (decision D14, default off) | no |
| Audit: export | yes | no | yes | no | no | no |
| Retention / archival configuration | yes | no | no | no | no | no |
| Break-glass reopen of CLOSED | two owners | no | no | no | no | no |
All checks are server-side from the caller's `/users` profile, never from a client-supplied role.
