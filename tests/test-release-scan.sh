#!/usr/bin/env bash
# tests/test-release-scan.sh — table test for the publication gate (tests/release-scan.sh).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
RS="$here/release-scan.sh"
pass=0; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

printf 'secretword\nacme-codename\n' >"$T/lp"
printf 'Jane Doe\njanedoe\n' >"$T/attr"

newrepo() { git init -q "$T/$1" && git -C "$T/$1" config user.email tester@example.com \
  && git -C "$T/$1" config user.name Tester && echo hi >"$T/$1/f" \
  && git -C "$T/$1" add -A && git -C "$T/$1" commit -q -m tick; }
run() { ( cd "$T/$1" && DEVBOX_LEAK_PATTERNS="$2" DEVBOX_ATTRIBUTION="$3" \
  bash "$RS" "${4:-HEAD}" >/dev/null 2>&1 ); echo $?; }
check() { local name="$1" dir="$2" lp="$3" got="$4" want="$5"
  if [[ "$got" == "$want" ]]; then pass=$((pass+1)); printf '  ok   %s\n' "$name"
  else fail=$((fail+1)); printf '  FAIL %s: rc=%s want=%s\n' "$name" "$got" "$want"; fi; }

# 1 clean repo
newrepo c1; check "clean repo -> 0" c1 "$T/lp" "$(run c1 "$T/lp" "$T/attr")" 0
# 2 blob contains identifier
newrepo c2; echo "talks about secretword" >"$T/c2/f"; git -C "$T/c2" commit -qam tick
check "blob leak -> 1" c2 "$T/lp" "$(run c2 "$T/lp" "$T/attr")" 1
# 3 commit message contains identifier
newrepo c3; git -C "$T/c3" commit -q --allow-empty -m "fix acme-codename bug"
check "message leak -> 1" c3 "$T/lp" "$(run c3 "$T/lp" "$T/attr")" 1
# 4 author email contains identifier
newrepo c4; git -C "$T/c4" -c user.email=dev@secretword.test commit -q --allow-empty -m x
check "author leak -> 1" c4 "$T/lp" "$(run c4 "$T/lp" "$T/attr")" 1
# 5 tracked private list inside the tree
newrepo c5; mkdir -p "$T/c5/tests"; echo secretword >"$T/c5/tests/leak-patterns"
git -C "$T/c5" add -A && git -C "$T/c5" commit -qam tick
check "tracked leak list -> 1" c5 "$T/lp" "$(run c5 "$T/lp" "$T/attr")" 1
# 6 missing list file
newrepo c6; check "missing list -> 2" c6 "$T/nope" "$(run c6 "$T/nope" "$T/attr")" 2
# 7 empty list file
: >"$T/empty"; newrepo c7; check "empty list -> 2" c7 "$T/empty" "$(run c7 "$T/empty" "$T/attr")" 2
# 8 invalid ERE in list
printf 'clean\nbad[regex\n' >"$T/badlp"; newrepo c8
check "invalid ERE -> 2" c8 "$T/badlp" "$(run c8 "$T/badlp" "$T/attr")" 2
# 9 attribution allowed in LICENSE, caught elsewhere
newrepo c9; printf 'MIT\nCopyright Jane Doe\n' >"$T/c9/LICENSE"; git -C "$T/c9" add -A
git -C "$T/c9" commit -qam tick
check "attribution in LICENSE -> 0" c9 "$T/lp" "$(run c9 "$T/lp" "$T/attr")" 0
newrepo c10; echo "# by Jane Doe" >"$T/c10/script.sh"; git -C "$T/c10" add -A; git -C "$T/c10" commit -qam tick
check "attribution outside allowlist -> 1" c10 "$T/lp" "$(run c10 "$T/lp" "$T/attr")" 1
# 10 attribution as the commit author NAME is sanctioned (the noreply identity)
newrepo c11; git -C "$T/c11" -c user.name="Jane Doe" -c user.email=33203208+janedoe@users.noreply.github.com commit -q --allow-empty -m tick2
check "attribution as author -> 0" c11 "$T/lp" "$(run c11 "$T/lp" "$T/attr")" 0
# 11 attribution in a commit MESSAGE is still a leak
newrepo c12; git -C "$T/c12" commit -q --allow-empty -m "thanks to Jane Doe"
check "attribution in message -> 1" c12 "$T/lp" "$(run c12 "$T/lp" "$T/attr")" 1
# 12 a leak in a HISTORICAL blob removed before the tip (the v1-blocker shape)
newrepo c13; echo "contains secretword" >"$T/c13/f"; git -C "$T/c13" commit -qam add-leak
echo "clean now" >"$T/c13/f"; git -C "$T/c13" commit -qam remove-leak
check "historical blob leak -> 1" c13 "$T/lp" "$(run c13 "$T/lp" "$T/attr")" 1
# 13 a leak in a HISTORICAL path name, file deleted before the tip
newrepo c14; echo x >"$T/c13-tmp" ; mkdir -p "$T/c14/acme-codename"; echo x >"$T/c14/acme-codename/f"
git -C "$T/c14" add -A && git -C "$T/c14" commit -qm add-dir && git -C "$T/c14" rm -rq acme-codename && git -C "$T/c14" commit -qm rm-dir
check "historical path leak -> 1" c14 "$T/lp" "$(run c14 "$T/lp" "$T/attr")" 1

echo "release-scan table: pass=$pass fail=$fail"
(( fail == 0 ))
