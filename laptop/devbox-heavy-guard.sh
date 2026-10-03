#!/bin/sh
# Claude Code PreToolUse(Bash) hook, laptop side of devbox-kit (installed by
# `devbox install-guard`). Heavy local commands (Docker, test, lint, build) are turned
# away with instructions for Claude to ask the user where to run them: Devbox, Local, or
# Local for this session. Logic lives in devbox-heavy-guard.py.
#
# On the box itself (/etc/devbox.env exists) this is a no-op, so syncing it there is safe.
# Fails open: any problem exits 0 with no output, so the command proceeds.
[ -f "${DEVBOX_BOX_MARKER:-/etc/devbox.env}" ] && exit 0   # override only for tests
command -v python3 >/dev/null 2>&1 || exit 0
py="$(dirname "$0")/devbox-heavy-guard.py"
[ -r "$py" ] || exit 0

# Load the default box's config (shell syntax) so the guard knows its name, profile,
# region, SSH alias, and profile dir. Missing config still guards, just without state.
cfgdir="${DEVBOX_CONFIG_DIR:-$HOME/.config/devbox}"
box="${DEVBOX_BOX:-$(cat "$cfgdir/default" 2>/dev/null)}"
if [ -n "$box" ] && [ -r "$cfgdir/$box.env" ]; then
  # shellcheck disable=SC1090
  . "$cfgdir/$box.env" 2>/dev/null
  export DEVBOX_NAME AWS_PROFILE AWS_REGION SSH_HOST_ALIAS PROFILE
fi
export DEVBOX_CONFIG_DIR="$cfgdir"
exec python3 "$py"
