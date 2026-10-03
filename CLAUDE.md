# devbox-kit — notes for agents working in this repo

A replicable remote dev box on AWS: laptop CLI `bin/devbox`, box-side scripts in `box/`, laptop-side Claude tooling in `laptop/`, optional project add-ons in `profiles/`. Users follow `SETUP.md`; the `/devbox-setup` skill (`.claude/skills/devbox-setup/`) walks them through it.

## Rules

- **Nothing person-, account- or company-specific in the kit.** No account IDs, names, hostnames, SSO session names, or project stack commands. Everything user-specific comes from `~/.config/devbox/<box>.env`. `tests/run.sh` enforces this with a no-leak scan; add new identifiers to tests/leak-patterns (local, gitignored — see tests/leak-patterns.example), never to the kit itself. tests/release-scan.sh is the publication gate over a git ref.
- **One source per piece.** The idle check lives only in `box/user-data.sh`; `devbox push-helpers` extracts it from there. Settings live only in the config; box-side scripts read `~/.devbox/config`, which push-helpers writes.
- **Idempotent and safe to re-run:** `provision`, `bootstrap`, `push-helpers`, `setup-identity`, `clone`, `sync-claude`, `install-guard`.
- **`destroy` is the only destructive command.** It matches resources by this box's name tag, asks for the box name, and keeps the data volume unless `--delete-data` is given (with a second confirmation). Never weaken those guards.
- **Fail open on the laptop hooks.** A broken guard must never block the user's commands.
- Shell is bash (macOS ships bash 3.2 as `/bin/bash`; the scripts avoid bash-4-only features in laptop-side code).

## Tests

`tests/run.sh`: syntax, guard table tests (`tests/test-guard.sh`), user-data rendering, config checks, and the no-leak scan. Run it before every commit. Changes to `bin/devbox provision/destroy` also need a live check: `devbox check`, then `devbox provision --dry-run`, against a throwaway `DEVBOX_NAME`.
