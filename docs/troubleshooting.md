# Troubleshooting

Every item here was hit for real while building this kit.

## Connecting

| Symptom | Cause | Fix |
|---|---|---|
| `TargetNotConnected` / `ssh` hangs | The box is stopped, or the SSM agent is still starting | `devbox status`; `devbox up` waits for SSM to come online |
| SSM never comes online after launch | No internet egress from the subnet, or the instance profile lacks SSM core | `devbox check` (egress line); confirm the profile's role has `AmazonSSMManagedInstanceCore` |
| All `devbox` commands fail with auth errors | The laptop's AWS login expired (SSH rides on it) | `aws sso login --profile <AWS_PROFILE>` |
| Every new `ssh <alias>` takes 4–5 s | Each connection starts a new SSM session (AWS CLI + API round trips) | `devbox ssh-config` (adds `ControlMaster`/`ControlPersist 10m`; later connections reuse one session, ~0.1 s) |
| `ssh` hangs right after the box was stopped or replaced outside `devbox down` | A shared (ControlMaster) connection to the old session is still open | `ssh -O exit <alias>`, then retry |
| Heroku / container-only platforms don't work as a devbox | No Docker daemon, a temporary filesystem, no real sshd | Use a VM (this kit) |

## Orca

Relay, node-pty, registration, and trust failures: see [orca.md](orca.md).

## Auto-stop

| Symptom | Cause | Fix |
|---|---|---|
| The box never stops | keepawake set, a busy process keeping load > 0.3, or constant new SSH sessions (e.g. a polling script) | `devbox status` shows which signal is busy: `(tty)`, `(ssh)`, `(load)`, `(keepawake)` |
| The box stopped under a working agent | The agent was silent (waiting on an API) past `IDLE_MIN` | `devbox keepawake` before unattended runs |
| Stopped seconds before you picked "Devbox" | A race: the idle check ran just before | Claude runs `devbox up` and continues; nothing is lost |

## Docker and disk

| Symptom | Cause | Fix |
|---|---|---|
| The root disk fills while `/data` is mostly empty | Docker 29+ keeps images in **containerd**, which ignores Docker's `data-root` | This kit sets containerd `root = "/data/containerd"`. On an older box: stop Docker, move `/var/lib/containerd` to `/data/containerd`, set `root` in `/etc/containerd/config.toml`, start |
| The Compose stack runs but containers exit 137 | Out of memory | `devbox resize` to a bigger type, or run fewer services |
| Old scripts call `docker-compose` (v1) | The box has Compose v2 only | A shim in your profile's `bootstrap.sh` (see `profiles/example`) |

## Claude Code

| Symptom | Cause | Fix |
|---|---|---|
| The guard asks "Run where?" for a harmless command | A heavy word in the step's command position | Pick Local; if it's a false positive, add a case to `tests/test-guard.sh` and fix `devbox-heavy-guard.py` |
| Answering "No" to a permission prompt stalls the task | An old yes/no style guard | `devbox install-guard` (this kit's guard asks *where*, not *whether*) |
| Box sessions don't follow your global CLAUDE.md or skills | `~/.claude` isn't on the box | `devbox sync-claude` |
| Two machines overwrite each other's shared memory files | Choosing the newest copy by mtime, when `git pull` stamps checkout time | Compare commit times for committed files; use mtime only for uncommitted edits |
| `sync-claude` crashes on a fresh laptop | No `~/.claude/settings.json` yet | Fixed in this kit; run Claude Code once on the laptop first anyway |

## Cost

| Symptom | Cause | Fix |
|---|---|---|
| Higher than expected | The box ran overnight | `devbox status`; check which signal kept it busy |
| Cost Explorer lower than your estimate | It lags several hours to a day | Estimate from running hours × the hourly price; the bill is the truth |
