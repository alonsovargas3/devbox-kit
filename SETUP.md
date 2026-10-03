# Setup

A full walkthrough from nothing to a working devbox. Budget about 30 minutes, most of it waiting for installs. Each phase ends with a **Verify** step; don't move on until it passes. The `/devbox-setup` Claude skill (Phase 7) can walk you through this interactively.

Throughout, `<box>` is your box name (it must start with `devbox-`, e.g. `devbox-jdoe`) and `<alias>` is `SSH_HOST_ALIAS` (default `devbox`).

---

## Phase 0: Prerequisites

**On your laptop (macOS or Linux):**

| Tool | Install |
|---|---|
| AWS CLI **v2** | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| Session Manager plugin | https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html |
| `jq`, `python3`, `rsync`, `ssh` | your package manager (`brew install jq` …) |
| `gh` (optional, recommended) | https://cli.github.com, then `gh auth login` |
| Claude Code | https://claude.com/claude-code |
| Orca (optional) | only if you use Orca for worktrees and agents |

**Accounts:**
- An AWS account where you can create EC2 resources, with a CLI profile on your laptop (SSO or access keys). The identity needs [`iam/provisioner-policy.json`](iam/provisioner-policy.json). If your org restricts IAM, tagging or VPCs, read [`iam/README.md`](iam/README.md) first.
- A GitHub account with access to the repos you'll clone.
- A Claude subscription or API access, for Claude Code on the box.

Get the kit and put the CLI on your PATH:

```bash
git clone https://github.com/alonsovargas3/devbox-kit ~/Dev/devbox-kit
mkdir -p ~/.local/bin && ln -sf ~/Dev/devbox-kit/bin/devbox ~/.local/bin/devbox   # make sure ~/.local/bin is on PATH
```

**Verify:** `devbox help` prints the command list, and `aws sts get-caller-identity --profile <your-profile>` shows the account you expect.

---

## Phase 1: Configure

```bash
devbox init devbox-jdoe          # writes ~/.config/devbox/devbox-jdoe.env (and makes it the default box)
$EDITOR ~/.config/devbox/devbox-jdoe.env
```

Fill in at least the **Required** block. Then decide on the settings that differ by organisation:

| Your situation | Setting |
|---|---|
| Your region has a default VPC | leave `SUBNET_ID` empty |
| No default VPC, or you must use a specific network | `SUBNET_ID=subnet-…` with internet egress (IGW + public IP, or NAT) |
| Subnet egresses through NAT | `ASSOCIATE_PUBLIC_IP=no` |
| Org blocks IAM role creation | `INSTANCE_PROFILE=<admin-provided profile with AmazonSSMManagedInstanceCore>` |
| Org requires tags | `EXTRA_TAGS="CostCenter=eng Team=x"` |
| Org requires a KMS key | `EBS_KMS_KEY=<key id or ARN>` |
| Your stack is ARM-native | `ARCH=arm64` and a Graviton `INSTANCE_TYPE` (e.g. `m7g.xlarge`) |
| You use AWS SSO on the box too | `DEVBOX_SSO_SESSIONS="<sso-session names from ~/.aws/config>"` |
| You use Google Cloud | `GCLOUD=on` |
| Repos to have on the box | `REPOS="owner/repo:Dev/repo …"`, ideally the **same paths as on your laptop** |

Several boxes (different accounts, clients or projects) are fine: one config file each, then `devbox --box <name> …`, or change the default in `~/.config/devbox/default`. Give each box its own `SSH_HOST_ALIAS`.

```bash
devbox check
```

**Verify:** `check passed`. Every ✗ line names what's missing. Denied permissions point to the IAM policy; subnet or egress failures point to `SUBNET_ID`.

---

## Phase 2: Provision

```bash
devbox provision --dry-run   # shows exactly what would be created; creates nothing
devbox provision
```

This creates, all named after `<box>` and tagged `purpose=devbox`:
- a security group with **no inbound rules**;
- an instance role and profile (SSM only), unless you set `INSTANCE_PROFILE`;
- an SSH key pair (the private key stays on your laptop in `SSH_KEY_FILE`);
- an encrypted **data volume**;
- the instance;
- a daily snapshot policy.

The first boot formats the data volume and installs Docker (about 3 minutes). Re-running `provision` is safe: it only creates what's missing.

**Verify:** it ends with `next: devbox ssh-config`, and `devbox status` shows the instance `running`. (A `--dry-run` ends with `dry run only: …` and creates nothing.)

---

## Phase 3: Connect

```bash
devbox ssh-config        # adds "Host <alias>" to ~/.ssh/config (SSH through Session Manager, no open port)
devbox ssh 'cat /var/lib/devbox-bootstrapped && docker --version && findmnt /data'
```

If the first command says `not connected`, the SSM agent is still starting. Wait a minute and retry.

**Verify:** the command prints the bootstrapped marker, a Docker version, and `/data` mounted from an NVMe device.

---

## Phase 4: Box tools and helpers

```bash
devbox bootstrap         # Node (for Orca's relay), build tools, aws, SSM plugin, gh, Claude Code, optional gcloud
devbox push-helpers      # login banner (devbox-doctor), devbox-login, claude-trust, idle auto-stop settings
```

**Verify:** `devbox ssh devbox-doctor` shows the auto-stop verdict and disk usage. AWS lines may be `!` until Phase 5.

---

## Phase 5: Identity and logins

```bash
devbox setup-identity    # git name/email, the box's own GitHub key (added via gh if it can), ~/.aws/config copy
devbox login             # one device-code approval per SSO session (+ gcloud); interactive
ssh -t <alias> claude    # then /login in Claude Code, once
```

If `setup-identity` couldn't add the GitHub key, it prints the key. Add it at https://github.com/settings/keys, or run `gh auth refresh -s admin:public_key` and re-run.

**Verify:** `devbox doctor` shows every line ✓: the AWS sessions, gh, the GitHub SSH key, gcloud if enabled, and Claude Code.

---

## Phase 6: Repos

```bash
devbox clone             # clones REPOS, trusts each main checkout for Claude, points repo memory/ dirs at themselves
```

`claude-trust` matters if you run Claude agents in new worktrees: Claude Code keys folder trust on the repo's main checkout, and an untrusted repo stalls agents at the trust dialog.

**Verify:** `devbox ssh 'ls ~/Dev'` lists your repos, and `devbox wip` runs on both machines.

---

## Phase 7: Claude setup

```bash
devbox install-skill     # laptop: the /devbox-setup and /devbox skills, into ~/.claude/skills
devbox sync-claude --dry-run && devbox sync-claude   # your ~/.claude (now including those skills) → box
devbox install-guard     # laptop: Claude asks "Run where?" before local Docker/test/lint/build
```

`sync-claude` copies one way, laptop to box. It rewrites your home path and keeps any hooks Orca installed on the box. Anything listed in `RETIRED_*` is never copied. Skills install to the laptop first, then ride the same sync to the box; the installed files point back at this kit checkout, so keep it (or re-run install-skill after moving it).

**Verify:** `install-guard` ends with `guard: pass=… fail=0`. `devbox ssh "claude -p 'reply with the first heading of your user-level CLAUDE.md'"` quotes your global CLAUDE.md.

---

## Phase 8: Orca (optional)

Worktree-based agent runners work well on the devbox. If you use Orca, follow
[docs/orca.md](docs/orca.md) — add the SSH host in the Orca UI, register repos
from the CLI, and set base refs to `origin/main`.

**Verify:** a terminal in a box worktree opens with the `devbox-doctor` banner.

---

## Done

Day-to-day use (start/stop, keepawake, re-auth, cost) is in [docs/sop.md](docs/sop.md). When something breaks, see [docs/troubleshooting.md](docs/troubleshooting.md).
