# Daily use

The rule behind all of this: **whatever expires is checked by a script, not by memory.** `devbox-doctor` runs on every interactive login to the box and flags anything stale.

## Start and stop

```bash
devbox up          # start; waits until you can connect (~1 min)
devbox down        # stop now; only the disks are billed while stopped
devbox status      # state + the auto-stop verdict, e.g. "busy (tty) | last activity 3m ago"
```

**It stops itself** once all of these hold for `IDLE_MIN` minutes (default 45), checked every 5 minutes:
- no terminal on the box read or written;
- **no new SSH session** (a laptop agent running `ssh <alias> 'cmd'` counts as use);
- 15-minute load ≤ 0.3;
- no keepawake;
- the box has been up at least `IDLE_MIN` minutes.

A long-lived connection such as Orca's doesn't keep it up. Checking on it (`devbox status`, `doctor`, `wip`) opens a session, so it counts as use.

**Nothing wakes a stopped box automatically.** Run `devbox up`, or pick *Devbox* when Claude asks "Run where?" and it will start the box for you.

## Laptop sleep and box restarts

- **Your laptop can sleep; the box keeps working.** Terminals and agents on the box run through laptop sleep (verified: a loop logged every 30 s through 36 min of sleep, same process, and Orca's connection survived). Orca messages from box workers queue until the laptop wakes. Auto-stop still applies, so use keepawake for long unattended runs.
- **After the box restarts** (`devbox up`, or waking from auto-stop), Orca may not reconnect by itself. Click **Reconnect** on the host.

## Before leaving work running unattended

```bash
devbox keepawake       # hold off auto-stop for 12 h
devbox keepawake off   # clear it when done
```

You need it for agents that wait silently on an API for a long time: no terminal output, no new SSH session, no load. Otherwise the box can stop under them.

## Heavy work: box or laptop?

With `devbox install-guard`, Claude on the laptop won't run Docker, test, lint or build commands directly. It asks **"Run where?"**:

- **Devbox:** it runs the step with `ssh <alias> 'cd <same path> && …'`.
- **Local:** it runs on the laptop this once (useful when the box is down or the job is tiny).
- **Local for this session:** local without asking again.

On the box itself the guard does nothing. To route project commands too (e.g. `make up`), add lines to `~/.config/devbox/guard-commands` or to your profile's `guard-commands`.

## Two machines, one set of repos

- The laptop and the box each have their own clones. **They sync only through the git remote.**
- `devbox wip` lists work that exists on only one machine: uncommitted changes, and commits on no remote branch. Run it before stopping for the day.
- Pull when you start working on a branch; push when you stop. The login banner warns when a main checkout is behind its remote.
- Don't commit to the same branch on both machines at once. If a push is rejected, merge (`git pull --no-rebase`) rather than rewrite shared history.

## When something expires

| Symptom | Fix |
|---|---|
| Banner: AWS SSO expired | `devbox login` (laptop) or `devbox-login` (box) |
| gcloud / BigQuery auth errors | the same: `devbox-login` refreshes the user login and ADC together |
| `git push` fails on the box | `devbox doctor` shows which: re-add the box key at github.com/settings/keys, or `gh auth login` |
| Claude Code asks to log in | `ssh -t <alias> claude`, then `/login` |
| `devbox` commands fail on the laptop | your laptop AWS login expired: `aws sso login --profile <AWS_PROFILE>` |

## Orca

Worktrees, trust, and laptop-coordinator/box-worker patterns: see [orca.md](orca.md).


## Size and cost

- `devbox resize m7i-flex.2xlarge` gives 8 vCPU / 32 GB at ~$0.38/hr. It stops and starts the box (about 2 minutes), and the disks come along. Update `INSTANCE_TYPE` in your config to match.
- Disk nearly full: `docker system prune`, or grow the volume in the EC2 console or with `aws ec2 modify-volume`. Growing is online, allowed once every 6 h. Then run `sudo resize2fs` on the device (plus `growpart` for the root disk).
- Snapshots: daily, 7 kept. To restore, create a volume from a snapshot in the same AZ and swap it in as `<box>-data`.

## Replacing the instance

The data volume survives termination. `aws ec2 terminate-instances …` (or `devbox destroy` without `--delete-data`), then `devbox provision` launches a fresh instance and re-attaches the same volume. Then run `devbox ssh-config` (the instance ID changed) and `devbox bootstrap && devbox push-helpers`.
