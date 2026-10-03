#!/usr/bin/env bash
# tests/release-scan.sh <ref> — publication gate for devbox-kit.
#
# Scans every object reachable from <ref> for private identifiers:
#   - blob contents (git show) and path names (git ls-tree)
#   - raw commit metadata: author/committer names+emails and full messages
#     including trailers (git cat-file commit) of every reachable commit
#
# Lists (gitignored, never in the published tree; see tests/leak-patterns.example):
#   DEVBOX_LEAK_PATTERNS  required, nonempty — must never appear anywhere.
#   DEVBOX_ATTRIBUTION    optional — allowed ONLY under LICENSE, README.md,
#                         SETUP.md, docs/ (public attribution), never in metadata.
# Exits 0 clean, 1 identifiers found (printed), 2 usage/config error.
# Runs against the repository in the CALLER's cwd (run it from the repo to scan).
set -uo pipefail
ref="${1:?usage: tests/release-scan.sh <ref>}"
leak="${DEVBOX_LEAK_PATTERNS:-tests/leak-patterns}"
attr="${DEVBOX_ATTRIBUTION:-tests/attribution}"
ALLOW='^(LICENSE|README\.md|SETUP\.md|docs/)'

die2() { echo "release-scan: $*" >&2; exit 2; }
git rev-parse --verify -q "$ref^{commit}" >/dev/null || die2 "bad ref: $ref"
[[ -s "$leak" ]] || die2 "identifier list missing/empty: $leak (cp tests/leak-patterns.example)"
for f in "$leak" "$attr"; do
  [[ -s "$f" ]] || continue
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && die2 "$f is TRACKED — it must never be committed"
done

readpat() { # file -> combined ERE on stdout; stderr + rc 2 on an invalid line
  local f="$1" l c=""
  [[ -s "$f" ]] || { printf ''; return 0; }
  while IFS= read -r l; do
    [[ -z "${l// /}" || "$l" == \#* ]] && continue
    printf '' | grep -c -E "$l" >/dev/null 2>&1
    rc=$?
    if (( rc == 2 )); then echo "invalid ERE in $f: $l" >&2; return 2; fi
    c="${c:+$c|}$l"
  done <"$f"
  printf '%s' "$c"
}
LP="$(readpat "$leak")" || die2 "fix $leak"
AP="$(readpat "$attr")" || die2 "fix $attr"
[[ -n "$LP" ]] || die2 "no patterns in $leak"

fail=0
note() { printf '  LEAK %s\n' "$*"; fail=1; }

# 1. private lists must not be anywhere in the tree
while IFS= read -r p; do
  [[ "$p" == tests/leak-patterns || "$p" == tests/attribution ]] && note "tree contains $p"
done < <(git ls-tree -r --name-only "$ref")

# 2. every blob reachable from <ref> — ALL history, not just the tip tree — plus
#    every historical path name. Attribution patterns apply only to allowlisted paths.
while IFS= read -r obj; do
  h="${obj%% *}"; p="${obj#* }"; [[ "$p" == "$obj" ]] && p=""
  [[ -n "$p" && "$(git cat-file -t "$h" 2>/dev/null)" == blob ]] || continue
  if [[ "$p" =~ $ALLOW ]]; then pat="$LP"; else pat="${LP}${AP:+|$AP}"; fi
  grep -q -E "$pat" <<<"$p" && note "path $p matches"
  hit="$(git cat-file blob "$h" | grep -n -E "$pat" | head -1)"
  [[ -n "$hit" ]] && note "blob $p:$hit"
done < <(git rev-list --objects "$ref")

# 3. path names
git ls-tree -r --name-only "$ref" | grep -E "${LP}${AP:+|$AP}" >/dev/null 2>&1 && note "a path name matches"

# 4. raw commit metadata of every reachable commit. The author/committer IDENTITY
#    lines carry the sanctioned attribution (name + noreply email); messages and
#    trailers never do.
while IFS= read -r c; do
  m="$(git cat-file commit "$c")"
  ids="$(grep -E '^(author|committer) ' <<<"$m")"
  rest="$(grep -vE '^(author|committer) ' <<<"$m")"
  hit="$(grep -n -E "$LP" <<<"$ids" | head -1)"
  [[ -n "$hit" ]] && note "commit ${c:0:10} identity: $hit"
  hit="$(grep -n -E "${LP}${AP:+|$AP}" <<<"$rest" | head -1)"
  [[ -n "$hit" ]] && note "commit ${c:0:10} metadata: $hit"
done < <(git rev-list "$ref")

if (( fail == 0 )); then echo "release-scan: clean ($ref, $(git rev-list --count "$ref") commit(s))"
else echo "release-scan: FAILURES above"; fi
exit $fail
