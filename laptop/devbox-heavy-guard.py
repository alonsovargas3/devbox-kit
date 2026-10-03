#!/usr/bin/env python3
"""PreToolUse(Bash) guard, laptop side (called by devbox-heavy-guard.sh).

Heavy local commands are turned away with instructions for Claude to ASK the user where
to run them: Devbox, Local, or Local for this session. "Local" re-runs with the prefix
DEVBOX_RUN=local, which this guard lets through.

Only the command actually run in each step (the first word of each `;`, `&&`, `||`, `|`,
newline, or $( ) segment) is inspected. Quoted strings and heredoc bodies are ignored, so
`gh issue comment -b "...jest..."` doesn't trigger. Commands aimed at the box
(`ssh <alias> ...`, `devbox ssh ...`) pass through. Any error fails open.

Project-specific commands: add lines `<label>: <command> [<first-arg>]` to
~/.config/devbox/guard-commands or <PROFILE>/guard-commands, e.g.
    Docker stack: ./scripts/dev-up.sh
    Docker stack: make up
"""
import json, os, re, subprocess, sys, time

WRAPPERS = {"sudo", "time", "env", "exec", "nice", "command", "nohup"}
ALIAS = os.environ.get("SSH_HOST_ALIAS") or "devbox"


def strip_heredocs(cmd):
    out, term = [], None
    for line in cmd.split("\n"):
        if term is not None:
            if line.strip() == term:
                term = None
            continue
        out.append(line)
        m = re.search(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        if m:
            term = m.group(2)
    return "\n".join(out)


def strip_quotes(s):
    s = re.sub(r"'[^']*'", "''", s)
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', s)


def extra_rules():
    """[(label, head, first_arg_or_None)] from guard-commands files."""
    rules = []
    paths = [os.path.join(os.environ.get("DEVBOX_CONFIG_DIR", os.path.expanduser("~/.config/devbox")), "guard-commands")]
    if os.environ.get("PROFILE"):
        paths.append(os.path.join(os.path.expanduser(os.environ["PROFILE"]), "guard-commands"))
    for p in paths:
        try:
            for line in open(p):
                line = line.split("#", 1)[0].strip()
                if ":" not in line:
                    continue
                label, rest = (x.strip() for x in line.split(":", 1))
                words = rest.split()
                if words:
                    rules.append((label, words[0], words[1] if len(words) > 1 else None))
        except OSError:
            pass
    return rules


def classify(tokens, rules):
    """Return (kind, head) for one segment's tokens, or None."""
    t = list(tokens)
    while t and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t[0]) or t[0] in WRAPPERS):
        t.pop(0)
    if not t:
        return None
    cmd, rest = os.path.basename(t[0]), t[1:]
    a1 = rest[0] if rest else ""
    head = " ".join(t[:3])

    for label, h, arg in rules:
        if (t[0] == h or cmd == os.path.basename(h)) and (arg is None or a1 == arg):
            return label, head
    if cmd in ("docker", "docker-compose"):
        args = rest[1:] if cmd == "docker" and a1 == "compose" else rest
        if cmd == "docker-compose" or a1 == "compose":
            # first non-flag word after compose, skipping flag values (-f x, -p x, --profile x)
            i = 0
            while i < len(args) and args[i].startswith("-"):
                i += 2 if args[i] in ("-f", "--file", "-p", "--project-name", "--profile", "--env-file") else 1
            if i < len(args) and args[i] in ("up", "run", "build", "start", "create"):
                return "Docker Compose", head
            return None
        if a1 in ("run", "build", "start") or (a1 == "buildx" and len(rest) > 1 and rest[1] == "build"):
            return "Docker", head
        return None
    if cmd == "phpunit" or t[0].endswith("/phpunit"):
        return "test suite", head
    if cmd in ("jest", "vitest", "bats", "pytest", "rspec", "tox"):
        return "test suite", head
    if cmd in ("eslint", "phpcs", "rubocop"):
        return "lint", head
    if cmd == "ember" and a1 in ("test", "t"):
        return "test suite", head
    if cmd == "ember" and a1 in ("build", "b"):
        return "build", head
    if cmd == "cypress" and a1 == "run":
        return "test suite", head
    if cmd in ("go", "cargo") and a1 in ("test", "build"):
        return ("test suite" if a1 == "test" else "build"), head
    if cmd in ("gradle", "./gradlew", "gradlew", "mvn") and any(x in ("test", "build", "check", "package", "verify") for x in rest):
        return "build/test", head
    if cmd in ("yarn", "npm", "pnpm", "bun"):
        sub = rest[1] if a1 == "run" and len(rest) > 1 else a1
        for pre, kind in (("test", "test suite"), ("lint", "lint"), ("build", "build")):
            if sub == pre or sub.startswith(pre + ":"):
                return kind, head
        return None
    if cmd == "npx" and rest:
        tool = os.path.basename(rest[0])
        if tool in ("vitest", "jest", "cypress", "playwright"):
            return "test suite", head
        if tool == "eslint":
            return "lint", head
        if tool == "run-s" and any(x.startswith(("lint", "test", "build")) for x in rest[1:]):
            return "lint/test/build", head
        if tool == "vite" and len(rest) > 1 and rest[1] == "build":
            return "build", head
    if cmd == "vite" and a1 == "build":
        return "build", head
    return None


def find_heavy(cmd):
    if re.search(r"(^|[\s;&|(])DEVBOX_RUN=local(\s|$)", cmd):
        return None  # the user already chose Local
    s = strip_quotes(strip_heredocs(cmd))
    if re.search(r"\bssh\s+(-\S+\s+)*" + re.escape(ALIAS) + r"\b|\bdevbox\s+(--box\s+\S+\s+)?ssh\b", s):
        return None  # already going to the box
    rules = extra_rules()
    for seg in re.split(r"&&|\|\||[;|\n`]|\$\(|[()]", s):
        hit = classify(seg.split(), rules)
        if hit:
            return hit
    return None


def devbox_state():
    name, profile, region = os.environ.get("DEVBOX_NAME"), os.environ.get("AWS_PROFILE"), os.environ.get("AWS_REGION")
    if not (name and region):
        return "unknown (no devbox config)"
    cache = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"devbox-state-{name}.cache")
    try:
        if time.time() - os.path.getmtime(cache) < 60:
            return open(cache).read()
    except OSError:
        pass
    env = dict(os.environ)
    if profile:
        env["AWS_PROFILE"] = profile
    try:
        state = subprocess.run(
            ["aws", "ec2", "describe-instances", "--region", region,
             "--filters", f"Name=tag:Name,Values={name}",
             "Name=instance-state-name,Values=pending,running,stopping,stopped",
             "--query", "Reservations[0].Instances[0].State.Name", "--output", "text",
             "--cli-connect-timeout", "3", "--cli-read-timeout", "3"],
            capture_output=True, text=True, timeout=8, env=env).stdout.strip()
    except Exception:
        state = ""
    if not state or state == "None":
        state = "unknown (AWS login on this laptop may be expired)"
    try:
        open(cache, "w").write(state)
    except OSError:
        pass
    return state


def main():
    d = json.load(sys.stdin)
    cmd = (d.get("tool_input") or {}).get("command") or ""
    hit = find_heavy(cmd)
    if not hit:
        return
    kind, head = hit
    state = devbox_state()
    home, cwd = os.path.expanduser("~"), d.get("cwd") or ""
    if cwd.startswith(home + "/"):
        where = (f"`ssh {ALIAS} 'cd {cwd[len(home) + 1:]} && <the heavy step>'` (same path on the box; "
                 "if that path doesn't exist there, push the branch and check it out on the box)")
    else:
        where = f"`ssh {ALIAS} 'cd <same repo> && <the heavy step>'`"
    running = state == "running"
    reason = (
        f"Heavy local work on this laptop ({kind}: `{head}`). Devbox: {state}. Nothing ran. Do not stop the task "
        f"and do not treat this as the user declining. Ask the user where to run it with AskUserQuestion "
        f"(header 'Run where?'), options: "
        f"'Devbox{' (Recommended)' if running else ''}': run {where}; "
        f"'Local': re-run this exact command prefixed with `DEVBOX_RUN=local `; "
        f"'Local for this session': the same, and use that prefix on every heavy command for the rest "
        f"of this session without asking again. "
        + ("" if running else "If they pick Devbox, start it first with `devbox up`. ")
        + "Only the heavy step needs to move; run the other steps of the command as before. "
        "If you cannot ask (unattended worker), use the devbox when it is running; otherwise report back."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # fail open
    sys.exit(0)
