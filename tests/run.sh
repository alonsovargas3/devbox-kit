#!/usr/bin/env bash
# Offline test suite for devbox-kit. No AWS calls, no box needed.
#   tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
okf() { printf '  ok   %s\n' "$*"; }
nok() { printf '  FAIL %s\n' "$*"; fail=1; }

step "syntax"
for f in bin/devbox box/*.sh box/devbox-doctor box/bashrc.devbox laptop/*.sh profiles/example/*.sh profiles/example/doctor.d/*.sh tests/*.sh; do
  bash -n "$f" && okf "bash -n $f" || nok "bash -n $f"
done
for f in box/claude-trust laptop/*.py; do
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" && okf "python parse $f" || nok "python parse $f"
done
python3 -m json.tool iam/provisioner-policy.json >/dev/null && okf "iam policy is valid JSON" || nok "iam policy JSON"

step "user-data render"
ud="$(mktemp)"
sed -e 's/__DATA_VOLUME_ID__/vol-0123456789abcdef0/g' -e 's/__IDLE_MIN__/45/g' -e 's/__ARCH__/amd64/g' -e 's/__DEVBOX_NAME__/devbox-test/g' box/user-data.sh >"$ud"
bash -n "$ud" && okf "rendered user-data parses" || nok "rendered user-data syntax"
grep -q '__[A-Z_]*__' "$ud" && nok "placeholders left: $(grep -o '__[A-Z_]*__' "$ud" | sort -u | tr '\n' ' ')" || okf "no placeholders left"
grep -q 'root = "/data/containerd"' "$ud" && okf "containerd root on /data" || nok "containerd root not set"
grep -q '"data-root": "/data/docker"' "$ud" && okf "docker data-root on /data" || nok "docker data-root not set"
sed -n "/cat >\/usr\/local\/sbin\/devbox-idle-check <<'EOF'/,/^EOF\$/p" box/user-data.sh | sed '1d;$d' >"$ud.idle"
bash -n "$ud.idle" && [[ -s "$ud.idle" ]] && okf "idle check extracts cleanly (push-helpers path)" || nok "idle check extraction"
rm -f "$ud" "$ud.idle"

step "config"
( set -e; . ./config.example.env
  for v in DEVBOX_NAME AWS_REGION AZ OWNER_EMAIL GIT_NAME GIT_EMAIL INSTANCE_TYPE ARCH DATA_GB ROOT_GB IDLE_MIN SSH_HOST_ALIAS; do
    [[ -n "${!v:-}" ]] || { echo "  missing $v"; exit 1; }; done
  [[ "$DEVBOX_NAME" == devbox-* ]] ) && okf "config.example.env sources and has every key" || nok "config.example.env"
T="$(mktemp -d)"
DEVBOX_CONFIG_DIR="$T" bin/devbox init devbox-ci >/dev/null && grep -q '^DEVBOX_NAME="devbox-ci"' "$T/devbox-ci.env" \
  && [[ "$(cat "$T/default")" == devbox-ci ]] && okf "devbox init writes config + default" || nok "devbox init"
DEVBOX_CONFIG_DIR="$T" bin/devbox init devbox-ci >/dev/null 2>&1 && nok "init overwrote an existing config" || okf "init refuses to overwrite"
rm -rf "$T"
bin/devbox help | grep -q "provision" && okf "help prints" || nok "help"

step "sync-claude env policy"
python3 - <<'PY' && okf "env moves only when SYNC_CLAUDE_ENV=yes" || nok "sync-claude env policy"
import importlib.util, os

def load():
    spec = importlib.util.spec_from_file_location("sync_claude", "laptop/sync-claude.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

os.environ.pop("SYNC_CLAUDE_ENV", None)
assert "env" not in load().COPY_KEYS, "env copied without opt-in"
os.environ["SYNC_CLAUDE_ENV"] = "yes"
assert "env" in load().COPY_KEYS, "env not copied after opt-in"
PY

step "guard"
tests/test-guard.sh && okf "guard table" || nok "guard table"

step "release scan gate"
tests/test-release-scan.sh && okf "release-scan table" || nok "release-scan table"

step "no leaks (nothing from any one person, account, or company)"
# Daily convenience scan. The publication gate is tests/release-scan.sh.
# Generic patterns always; your private list (tests/leak-patterns, gitignored) adds the rest.
# ([U]sers: the bracket keeps this source line from matching its own pattern.)
pat='/[U]sers/'
lp="tests/leak-patterns"
if [[ -s "$lp" ]]; then
  while IFS= read -r l; do
    [[ -z "${l// /}" || "$l" == \#* ]] && continue
    printf '' | grep -c -E "$l" >/dev/null 2>&1
    (( $? == 2 )) && { nok "invalid ERE in $lp: $l"; break; }
    pat="$pat|$l"
  done <"$lp"
else
  echo "  ! tests/leak-patterns missing — private identifier scan SKIPPED (cp tests/leak-patterns.example)"
fi
hits=$(git ls-files -coz --exclude-standard | xargs -0 grep -n -E "$pat" 2>/dev/null)
if [[ -n "$hits" ]]; then nok "identifiers found:"; echo "$hits" | head -20; else okf "no identifiers (generic + private patterns)"; fi

echo; (( fail == 0 )) && echo "ALL PASSED" || echo "FAILURES"
exit $fail
