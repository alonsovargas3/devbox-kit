# devbox-kit

A personal remote dev box on AWS for agentic development: your agents work on
two machines — laptop and box — with one set of repos, and the heavy load
(Docker stacks, test suites, linters, builds, agent runs) leaves the laptop.
It runs in **your own AWS account**; nothing is shared with anyone else.

- **Durable by design.** Everything lives on a persistent data volume: `/home`,
  Docker, images, your logins. The instance is disposable — resize or replace
  it and come back to the same state. Daily snapshots, 7 kept.
- **No inbound ports.** SSH goes through AWS Session Manager, gated by your own
  AWS login. IAM-restricted org: see [iam/](iam/).
- **Stops itself.** 45 minutes after you stop using it (no terminal, no SSH,
  low load), it stops; only the disks are billed. Estimate for the defaults
  (m7i-flex.xlarge, us-west-2, on-demand, Oct 2026): running ≈ **$48/mo** at
  8 h × 22 d — instance ~$34, 100 GB data + 40 GB root EBS ~$11, public IPv4
  ~$2, snapshots ~$1; stopped ≈ **$13/mo** (disks + snapshots). Agent
  subscriptions and NAT egress are extra.
- **Built for agents.** Claude Code works the same on both machines; a laptop
  hook makes Claude ask **"Run where?"** before heavy local commands, so they
  land on the box unless you choose otherwise. Orca works over the same SSH
  route ([docs/orca.md](docs/orca.md)).
- **Two machines, one set of repos.** Each machine has its own clones; they
  sync **only through git** — push before you switch, `devbox wip` to audit
  what's unpushed or uncommitted on either side.

```
laptop                                        AWS (your account)
┌──────────────────────────────┐              ┌────────────────────────────────────────┐
│ devbox CLI + config          │  AWS API     │ EC2 instance (Ubuntu 24.04, disposable)│
│ Claude Code + "Run where?"   │ ───────────▶ │  └─ idle check → stops itself          │
│ Orca (optional)              │  SSH over    │ data volume /data  (persistent)        │
│ ssh <alias>  ────────────────┼─ SSM ──────▶ │  ├─ /home  (repos, logins, Claude)     │
└──────────────────────────────┘  (no ports)  │  ├─ docker/     └─ containerd/          │
                                              │ daily snapshots (DLM)                  │
                                              └────────────────────────────────────────┘
```

## Quickstart

```bash
git clone https://github.com/alonsovargas3/devbox-kit ~/Dev/devbox-kit && ln -sf ~/Dev/devbox-kit/bin/devbox ~/.local/bin/devbox
devbox init devbox-<you> && $EDITOR ~/.config/devbox/devbox-<you>.env
devbox check && devbox provision && devbox ssh-config
devbox bootstrap && devbox push-helpers && devbox setup-identity && devbox login
devbox clone && devbox install-skill && devbox sync-claude && devbox install-guard
```

The full walkthrough, with a verify step per phase and the choices that differ
between organisations, is in **[SETUP.md](SETUP.md)**. If you use Claude Code,
`/devbox-setup` (installed above) walks you through it interactively.

## Components

| Piece | What it does |
|---|---|
| `bin/devbox` | one CLI: provision, connect, bootstrap, clone, sync, daily up/down/status/wip/keepawake/resize/destroy |
| "Run where?" guard | laptop Claude hook: heavy local Docker/test/lint/build asks Devbox / Local / Local-for-session |
| `devbox wip` | audit work that exists on only one machine (uncommitted + unpushed) |
| `devbox sync-claude` | mirror your `~/.claude` (CLAUDE.md, skills, hooks, settings, plugins) onto the box, one-way |
| `devbox-doctor` | login-banner health check: what expired or drifted on the box |
| skills | `/devbox-setup` (guided setup + repair), `/devbox` (daily ops for your agent) |
| [profiles/](profiles/) | per-project add-ons: runtimes, stack helpers, extra checks, guard commands |
| [iam/](iam/) | least-privilege policy for the provisioning identity |

## Docs

| | |
|---|---|
| [SETUP.md](SETUP.md) | first-time setup, phase by phase |
| [docs/sop.md](docs/sop.md) | daily use: start/stop, keepawake, re-auth, "Run where?", cost |
| [docs/troubleshooting.md](docs/troubleshooting.md) | known failure modes and fixes |
| [docs/orca.md](docs/orca.md) | Orca (optional): setup, daily use, troubleshooting |
| [config.example.env](config.example.env) | every setting, commented |

## Development

`tests/run.sh` runs the offline suite: syntax, guard table tests, release-scan
gate tests, user-data rendering, config checks, and a scan that fails if any
person-, account- or company-specific value leaks into the kit (your private
identifier list lives in gitignored `tests/leak-patterns`). Run it before every
commit.

MIT — see [LICENSE](LICENSE). Not affiliated with Jetify's Devbox.
