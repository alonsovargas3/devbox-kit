# Orca on the devbox

Everything Orca-specific lives here; the core kit is tool-agnostic (its guard,
trust helper, and skills integrate Claude Code specifically). Orca's SSH-host
mode works with any `~/.ssh/config` host, which is all the devbox is.

## Setup

1. **Orca → Settings → SSH hosts → Add:** host `<alias>`. Orca uses your `~/.ssh/config`, so the Session Manager route just works. The first connect installs Orca's relay on the box, and it compiles node-pty, which is why `devbox bootstrap` installed build tools.
2. **Register each repo on that host.** The CLI does this (only adding the host itself needs the UI):
   ```bash
   orca host list       # the host id, e.g. ssh:ssh-…
   orca project list    # project ids, e.g. github:acme/api
   orca project setup-existing-folder --project github:acme/api --host ssh:<id> --path /home/ubuntu/Dev/api --kind git
   ```
   Or in the Orca UI: add project → choose the `<alias>` host → the path under `/home/ubuntu`.
3. Make new worktrees start from the latest remote branch:
   `orca repo list` (find the ids), then `orca repo set-base-ref --repo id:<id> --ref origin/main` for each record, laptop and box. Orca then fetches before every new worktree.
4. Optional: a test with a coordinator on the laptop and a worker on the box — see Daily use below.

## Daily use

- **Worktrees:** pick the `<alias>` host when creating one. With the base ref set to `origin/main`, Orca fetches first, so new worktrees start from the latest code.
- **Agents in new worktrees** need the repo's main checkout trusted by Claude (`devbox clone` does this). For a repo added later: `ssh <alias> claude-trust ~/Dev/<repo>`.
- **Coordinating from the laptop and working on the box:** `orca orchestration worker-start --worktree new-top-level --repo id:<box repo id> …`, then follow up with `worker-list --include-remote`.

## Laptop sleep and box restarts

- **Your laptop can sleep; the box keeps working.** Terminals and agents on the box run through laptop sleep (verified: a loop logged every 30 s through 36 min of sleep, same process, and Orca's connection survived). Orca messages from box workers queue until the laptop wakes. Auto-stop still applies, so use keepawake for long unattended runs.
- **After the box restarts** (`devbox up`, or waking from auto-stop), Orca may not reconnect by itself. Click **Reconnect** on the host.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `orca serve` on the box → "cannot connect to the Desktop" | On Ubuntu, `orca` is **GNOME's screen reader** (`apt install orca` installs it) | `sudo apt-get purge --autoremove orca`. You don't need `orca serve`: SSH-target mode installs a relay CLI at `~/.orca-relay/bin/orca` that talks to your laptop's Orca |
| "Node.js not found on remote host" | The relay runs `node` on the **non-interactive** PATH, so version-manager shims don't count | `devbox bootstrap` installs Node 22 in `/usr/bin` |
| "could not locate its node-pty install directory" | The relay compiles node-pty on Linux, and the box had no compiler | `devbox bootstrap` (installs `build-essential`), then disconnect and reconnect the host in Orca |
| "the SSH relay for this host is not attached" after `devbox up` | The box restarted; Orca's old connection is gone and it didn't reconnect by itself | Orca → the host → **Reconnect**. (Laptop sleep doesn't cause this: the connection survives it.) |
| An added project shows as "Unknown" or lands under the wrong project | Registered with the wrong path, or a repo record without a display name | Check the path in the UI; `orca project setup-update --setup <id> --display-name "<name>"` |
| `worker-start` fails at `agent_readiness` (timeout) | Claude's "Is this a project you trust?" dialog swallowed the task | `ssh <alias> claude-trust ~/Dev/<repo>` (the **main checkout** of *that* repo; a parent folder's trust doesn't cover it, and a repo nested inside another is separate), release the worker, start again |
| New worktrees start from stale code | The base ref is local `main` | `orca repo set-base-ref --repo id:<id> --ref origin/main` (Orca fetches before creating) |

## Why the core installs what it installs

- `devbox bootstrap` installs `build-essential` because Orca's SSH relay compiles
  node-pty on Linux (no prebuilt), and Node 22 in `/usr/bin` because the relay
  runs on the non-interactive PATH where version-manager shims don't exist.
- `devbox clone` trusts each repo's **main checkout** (`claude-trust`) because
  Claude Code keys folder-trust for a worktree on the main checkout; without
  it, workers in new worktrees stall on the trust dialog.
- `sync-claude` preserves Orca's own box-side hooks (`ORCA_HOOK_MARK`) and
  skips Orca-managed laptop hooks, so the two never fight over the same
  settings.
