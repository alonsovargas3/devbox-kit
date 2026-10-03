---
name: devbox
description: Daily devbox operations for Claude on the laptop — start/stop/status, wip audit before ending the day, keepawake around unattended agent runs, and re-auth when logins expire. Use when the user says "start/stop my devbox", "/devbox", "is the box up", "check my wip", "keep the box up", or "the box's AWS/GitHub/Claude login expired".
---

# /devbox

Routine operation of the user's devbox (their remote dev machine). First-time
setup and structural repair belong to `/devbox-setup`; this is the daily loop
from `__KIT_DIR__/docs/sop.md` — read it when a situation isn't covered here.

## Commands

- `devbox status` — state + the auto-stop verdict (which signal is busy). Run it
  before answering "is it up?".
- `devbox up` / `devbox down` — start (~1 min, waits for SSM) / stop (only the
  disks are billed while stopped).
- `devbox wip` — work that exists on only one machine: uncommitted changes and
  commits on no remote branch, laptop and box. Suggest it when the user wraps
  up for the day. The fix is committing and pushing — never copy working trees
  between machines.
- `devbox keepawake` — hold off auto-stop for 12 h. Ask for it (or run it) before
  any unattended agent run: agents that wait silently on an API look idle and
  the box can stop under them. `devbox keepawake off` when done.

## When something expires

Follow the table in `__KIT_DIR__/docs/sop.md`: AWS SSO → `devbox login` (box:
`devbox-login`); `git push` failing on the box → `devbox doctor` shows whether
it's the GitHub key or gh; Claude Code → `ssh -t <alias> claude`, then /login;
laptop-side `devbox` failures → the laptop AWS login expired.

## Rules

- **Never `devbox destroy`** unless the user explicitly asks for it in this
  conversation.
- Heavy local Docker/test/lint/build goes to the box: ask **"Run where?"** per
  the installed guard (Devbox / Local / Local for this session) rather than
  assuming.
- The laptop and the box have separate clones that sync only through git:
  push before working on the other machine, pull when you start.
