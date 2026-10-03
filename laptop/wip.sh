#!/usr/bin/env bash
# wip.sh — list git work that exists only on THIS machine: dirty worktrees and commits on
# no remote branch. Prints only what needs attention. Uses cached remote refs (no fetch).
# `devbox wip` runs it on the laptop and on the box.
#
#   WIP_ROOTS="Dev work" bash wip.sh     # dirs under $HOME; each root and its immediate
#                                        # subdirectories that are git repos are scanned
set -uo pipefail

label="${WIP_LABEL:-$(hostname -s)}"
roots=()
for r in ${WIP_ROOTS:-Dev}; do
  base="$HOME/$r"
  [[ -d "$base/.git" ]] && roots+=("$base")
  for d in "$base"/*/ "$base"/*/*/; do        # depth 2: ~/Dev/<repo> and ~/Dev/<group>/<repo>
    [[ -d "$d/.git" ]] && roots+=("${d%/}")   # .git DIR = a primary clone (worktrees have a .git file)
  done
done

found=0; out=""
note() { out+=$(printf '  %-44s %s' "$1" "$2")$'\n'; found=1; }

for repo in "${roots[@]+"${roots[@]}"}"; do
  short="${repo#"$HOME"/}"
  # Dirty worktrees (the primary checkout and every linked worktree, wherever it lives).
  while IFS= read -r wt; do
    n=$(git -C "$wt" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    (( n > 0 )) && note "${wt#"$HOME"/}" "$n uncommitted change(s) [$(git -C "$wt" rev-parse --abbrev-ref HEAD)]"
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')

  # Commits that exist only here: reachable from a local branch but from no remote ref.
  while read -r br; do
    n=$(git -C "$repo" rev-list --count "$br" --not --remotes 2>/dev/null || echo 0)
    (( n > 0 )) && note "$short" "branch $br: $n commit(s) not pushed anywhere"
  done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads)
done

echo "== $label"
(( found )) && printf '%s' "$out" || echo "  nothing unpushed or uncommitted"
