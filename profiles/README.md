# Profiles: project-specific add-ons

The core sets up a generic box. A **profile** adds what one project or team needs: language runtimes, a stack start helper, extra health checks, or project commands the laptop guard should route to the box. Point your config at one with `PROFILE=/path/to/profile`. A profile can live anywhere, including inside the project's own repo, so each team versions its own.

| File (all optional) | Runs where | When | Purpose |
|---|---|---|---|
| `bootstrap.sh` | box, as `ubuntu` via `bash -s` | `devbox bootstrap` | install runtimes and tools (idempotent; re-run after replacing the instance) |
| `bashrc` | box, sourced by `~/.bashrc.devbox` | every interactive shell | helpers such as `stack-up` or project env vars |
| `doctor.d/*.sh` | box, run by `devbox-doctor` | login banner, `devbox doctor` | extra checks; print lines like `  ✓ ...` / `  ! ...`; `FULL=1` for `--full` |
| `guard-commands` | laptop, read by the "Run where?" guard | every Claude Bash call | `label: command [first-arg]`, one per line |

`devbox push-helpers` copies `bashrc` and `doctor.d/` to `~/.devbox/profile/` on the box. `bootstrap.sh` runs from the laptop copy, and `guard-commands` is read from the laptop copy.

## Rules

- **No secrets.** Profiles get committed and shared. Read credentials at runtime from the user's own logins (SSO, `gh`, a secrets manager).
- **Idempotent.** `bootstrap.sh` must be safe to run twice.
- **Don't fight the core.** Docker and containerd data live on `/data`; keep project data under `/home/ubuntu` (which is `/data/home`) or `/data`.

See `example/` for a skeleton.
