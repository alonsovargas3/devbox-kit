---
name: devbox-setup
description: Set up, verify, or repair a personal remote dev box on AWS with devbox-kit — config, provisioning, SSH over SSM, tools, logins, repos, Claude and Orca setup. Use when the user says "set up my devbox", "/devbox-setup", "provision a dev box", "my devbox is broken", or wants to add a second box in another AWS account.
---

# /devbox-setup

Walk the user through devbox-kit's `SETUP.md`, one phase at a time, running the commands yourself and proving each phase with its **Verify** step before moving on. The kit is at `__KIT_DIR__`; the CLI is `__KIT_DIR__/bin/devbox` (or `devbox` if it's on PATH).

## Before starting

1. Read `__KIT_DIR__/SETUP.md` and `__KIT_DIR__/docs/troubleshooting.md`. They're the source of truth; this skill is the procedure around them.
2. Find out where the user is: `ls ~/.config/devbox/` and `devbox status` (if a config exists). If a box already exists, resume from the first phase whose Verify fails. Don't redo working phases.
3. Restate the goal in one sentence: a running box, reachable with `ssh <alias>`, with the user's repos, logins and Claude setup, auto-stopping when idle. The final verification is `devbox doctor` all ✓ plus the phase 7 Claude check.

## Procedure

Go phase by phase (0 → 8). For each one:
- Run its commands and show the key output.
- Run its **Verify** step. A phase is done only when Verify passes; if it fails, use `__KIT_DIR__/docs/troubleshooting.md`, fix, and re-verify.
- Say in one line what's done and what's next.

**Phase 1 decisions are the user's.** Use AskUserQuestion (with a recommendation first) for the org-specific settings in SETUP.md's Phase 1 table:
- region/AZ;
- whether there's a default VPC or they need `SUBNET_ID`;
- whether IAM role creation is allowed (otherwise `INSTANCE_PROFILE` from their admin);
- required tags;
- KMS;
- `ARCH`;
- SSO sessions;
- gcloud;
- which repos to clone, and at which paths.

Look up what you can first (`aws configure list-profiles`, `aws ec2 describe-vpcs --filters Name=is-default,Values=true`, `grep '^\[sso-session' ~/.aws/config`) so you ask informed questions. Edit the config file yourself once they answer. `DEVBOX_NAME` must start with `devbox-`.

**Stop and hand over to the user for the steps only a human can do:**
- browser approvals for `devbox login` (AWS device codes, the gcloud paste-back code);
- adding the box's GitHub key if `gh` lacks the `admin:public_key` scope;
- Claude Code `/login` on the box (`ssh -t <alias> claude`);
- the Orca UI step: adding the SSH host. (You can register projects on it yourself with `orca project setup-existing-folder --host ssh:<id> …`, then `orca repo set-base-ref … origin/main`.)

Tell them exactly what to type or click, then wait for them to confirm before verifying.

## Rules

- **Never run `devbox destroy`** unless the user explicitly asks for it in this conversation, and then show them its resource list first. Never pass `--delete-data` without their explicit request; it deletes their repos and logins.
- Before `devbox provision` (it creates billable resources), show `devbox provision --dry-run` and the cost (see README: about $0.19/hr running, about $10/mo stopped for the default size), and get a yes.
- **Never write secrets into the config, the kit, or git.** Credentials stay in the user's own login stores (`~/.aws`, `gh`, Claude). If `~/.aws/config` contains keys, `setup-identity` refuses to copy it; tell them to move the keys to `~/.aws/credentials`.
- `devbox check` failures are information, not dead ends. Denied permissions → `iam/README.md` (what to ask their admin); subnet or egress → `SUBNET_ID`.
- If they already have a box and want another (different account or client), use a new `devbox init <name>` and a distinct `SSH_HOST_ALIAS`, and pass `--box <name>` on every command.

## Finish

Report: box name, instance ID, region/AZ, alias, the cost when running and when stopped, what auto-stops it, and the three daily commands (`devbox up`, `devbox down`, `devbox status`). Point them to `__KIT_DIR__/docs/sop.md`.
