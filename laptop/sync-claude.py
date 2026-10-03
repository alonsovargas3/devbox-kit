#!/usr/bin/env python3
"""sync-claude.py — mirror your laptop's personal Claude Code setup onto the devbox.

One-way (laptop -> box), idempotent. Run via `devbox sync-claude [--dry-run]`.

What moves:
  files     ~/.claude/CLAUDE.md, keybindings.json, statusline-command.sh, hooks/*.{sh,py},
            agent-routing/{profile,roles.json}, agents/, commands/, output-styles/ (whichever exist),
            skills/<portable>/ (macOS-only skills skipped)
  settings  selected keys from ~/.claude/settings.json, merged into the box's settings:
            box-only keys and Orca's box-side hooks are kept; laptop hooks are added (deduped by command)
  never     tools you retired: RETIRED_SKILLS / RETIRED_PLUGINS / RETIRED_HOOKS from your devbox config
  plugins   marketplaces + enabledPlugins installed with `claude plugin` on the box

Your laptop home is rewritten to /home/ubuntu in every copied value. Secrets stay off
the box by default: no credentials, ~/.claude.json, sessions, or history ever move, and
the settings `env` block is copied only when SYNC_CLAUDE_ENV=yes — env commonly holds
API keys, so review yours before opting in.
"""
import json, os, shlex, subprocess, sys, tempfile

HOST = os.environ.get("SSH_HOST_ALIAS") or "devbox"
MAC_HOME = os.path.expanduser("~")
BOX_HOME = "/home/ubuntu"
CL = os.path.join(MAC_HOME, ".claude")
DRY = "--dry-run" in sys.argv

# macOS-only (GUI / iOS simulator), or managed on the box by other means.
SKIP_SKILLS = {"computer-use", "orca-emulator", "orca-emulator-android", "synced"}
# Tools you retired: never propagate them, even if they reappear on the laptop.
# Space-separated lists from the devbox config (exported by `devbox sync-claude`).
RETIRED_SKILLS = set(os.environ.get("RETIRED_SKILLS", "").split())
RETIRED_PLUGINS = set(os.environ.get("RETIRED_PLUGINS", "").split())
RETIRED_MARKETPLACES = {p.split("@", 1)[1] for p in RETIRED_PLUGINS if "@" in p}
RETIRED_HOOK_SUBSTRINGS = tuple(os.environ.get("RETIRED_HOOKS", "").split())
COPY_KEYS = [
    "attribution", "effortLevel", "autoMode", "statusLine", "permissions", "tui",
    "agentPushNotifEnabled", "inputNeededNotifEnabled", "awaySummaryEnabled",
    "skipWorkflowUsageWarning", "skipDangerousModePermissionPrompt", "enabledPlugins",
]
# The settings `env` block often holds API keys/tokens, so it moves only when the config
# opts in (SYNC_CLAUDE_ENV=yes, exported by `devbox sync-claude`).
if os.environ.get("SYNC_CLAUDE_ENV") == "yes":
    COPY_KEYS.append("env")
ORCA_HOOK_MARK = ".orca/agent-hooks"


def rewrite(v):
    """Swap laptop home paths for box ones in any JSON value."""
    return json.loads(json.dumps(v).replace(MAC_HOME, BOX_HOME))


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw).stdout


def ssh(script, stdin=None):
    return sh(["ssh", HOST, "bash", "-lc", shlex.quote(script)], input=stdin)


def say(msg):
    print(("[dry-run] " if DRY else "") + msg)


def sync_files():
    rel = ["CLAUDE.md", "keybindings.json", "statusline-command.sh", "agent-routing/profile", "agent-routing/roles.json"]
    hooks_dir = os.path.join(CL, "hooks")
    if os.path.isdir(hooks_dir):
        rel += [f"hooks/{f}" for f in sorted(os.listdir(hooks_dir)) if f.endswith((".sh", ".py"))]
    rel = [r for r in rel if os.path.isfile(os.path.join(CL, r))]
    dirs = [d for d in ("agents", "commands", "output-styles") if os.path.isdir(os.path.join(CL, d))]
    skills_dir = os.path.join(CL, "skills")
    skills = [s for s in sorted(os.listdir(skills_dir) if os.path.isdir(skills_dir) else [])
              if s not in SKIP_SKILLS | RETIRED_SKILLS and os.path.isdir(os.path.join(CL, "skills", s))]
    say(f"files: {', '.join(rel + [d + '/' for d in dirs]) or 'none'}")
    say(f"skills: {', '.join(skills)} (skipped: {', '.join(sorted(SKIP_SKILLS | RETIRED_SKILLS))})")
    if DRY:
        return
    lst = "\n".join(rel + [d + "/" for d in dirs] + [f"skills/{s}/" for s in skills]) + "\n"
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(lst)
    try:
        # --files-from + trailing-slash dirs; -r so skill dirs recurse. No --delete: never
        # removes anything the box has on its own.
        sh(["rsync", "-a", "-r", f"--files-from={f.name}", CL + "/", f"{HOST}:.claude/"])
    finally:
        os.unlink(f.name)
    # Scripts may embed laptop paths (statusline, hooks): rewrite in place on the box.
    targets = " ".join(shlex.quote(r) for r in rel if r.endswith((".sh", ".py")))
    if targets:
        ssh(f"cd ~/.claude && sed -i 's#{MAC_HOME}#{BOX_HOME}#g' {targets} && chmod +x {targets}")


def merge_hooks(box_hooks, mac_hooks):
    """Keep every box hook; add laptop hooks whose command isn't already present.
    Orca-managed laptop hooks are skipped: Orca installs its own on the box."""
    out = json.loads(json.dumps(box_hooks or {}))
    added = []
    for event, matchers in (mac_hooks or {}).items():
        have = {h.get("command") for m in out.get(event, []) for h in m.get("hooks", [])}
        for m in matchers:
            hooks = []
            for h in m.get("hooks", []):
                cmd = h.get("command", "")
                if ORCA_HOOK_MARK in cmd or any(r in cmd for r in RETIRED_HOOK_SUBSTRINGS):
                    continue
                h = rewrite(dict(h, command=cmd))
                if h["command"] not in have:
                    hooks.append(h)
                    have.add(h["command"])
            if hooks:
                out.setdefault(event, []).append(dict(rewrite(m), hooks=hooks))
                added += [f"{event}: {h['command'][:60]}" for h in hooks]
    return out, added


def sync_settings():
    sp = os.path.join(CL, "settings.json")
    mac = json.load(open(sp)) if os.path.exists(sp) else {}
    box = json.loads(ssh("cat ~/.claude/settings.json 2>/dev/null || echo '{}'"))
    merged = dict(box)
    changed = []
    for k in COPY_KEYS:
        if k in mac:
            v = rewrite(mac[k])
            if k == "enabledPlugins":
                v = {p: on for p, on in v.items() if p not in RETIRED_PLUGINS}
            if box.get(k) != v:
                changed.append(k)
            merged[k] = v
    merged["hooks"], added = merge_hooks(box.get("hooks"), mac.get("hooks"))
    say(f"settings keys updated: {', '.join(changed) or 'none'}")
    for a in added:
        say(f"  + hook {a}")
    if DRY or (not changed and not added):
        return
    body = json.dumps(merged, indent=2) + "\n"
    ssh("f=~/.claude/settings.json; cp -p \"$f\" \"$f.bak-sync-claude\" 2>/dev/null; "
        "t=$(mktemp ~/.claude/.settings.XXXXXX) && cat >\"$t\" && "
        "python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \"$t\" && mv \"$t\" \"$f\"", stdin=body)


def sync_plugins():
    sp = os.path.join(CL, "settings.json")
    enabled = [p for p, on in ((json.load(open(sp)) if os.path.exists(sp) else {}).get("enabledPlugins") or {}).items()
               if on and p not in RETIRED_PLUGINS]
    mp = os.path.join(CL, "plugins", "known_marketplaces.json")
    markets = json.load(open(mp)) if os.path.exists(mp) else {}
    have = ssh("claude plugin list 2>/dev/null || true")
    have_m = ssh("claude plugin marketplace list 2>/dev/null || true")
    for name, meta in markets.items():
        src = meta.get("source", {})
        if name in have_m or name in RETIRED_MARKETPLACES:
            continue
        if src.get("source") == "github":
            say(f"marketplace add {src['repo']} ({name})")
            if not DRY:
                ssh(f"claude plugin marketplace add {shlex.quote(src['repo'])}")
    for p in enabled:
        if p.split("@")[0] in have:
            continue
        say(f"plugin install {p}")
        if not DRY:
            ssh(f"claude plugin install {shlex.quote(p)}")


if __name__ == "__main__":
    sync_files()
    sync_settings()
    sync_plugins()
    say("done")
