#!/usr/bin/env bash
# Table tests for laptop/devbox-heavy-guard. "ask" = the guard turns the command away so
# Claude asks "Run where?". Runs on any laptop OS; needs jq and python3.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
H="${1:-$here/laptop/devbox-heavy-guard.sh}"
command -v jq >/dev/null || { echo "needs jq"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TMPDIR="$T" DEVBOX_CONFIG_DIR="$T/cfg" DEVBOX_BOX_MARKER="$T/not-a-box"
mkdir -p "$DEVBOX_CONFIG_DIR"
# A project command registered through guard-commands (the profile mechanism).
printf '%s\n' "# label: command [first-arg]" "Docker stack: make up" "Docker stack: ./scripts/dev-up.sh" >"$DEVBOX_CONFIG_DIR/guard-commands"
pass=0; fail=0

t() { # t <ask|allow> <command>
  local exp="$1" out got; shift
  out=$(jq -n --arg c "$*" --arg d "$HOME/Dev/app" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | sh "$H")
  [[ -n "$out" ]] && got=ask || got=allow
  if [[ "$got" == "$exp" ]]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); echo "FAIL want=$exp got=$got :: $(printf '%s' "$*" | head -c 100)"; fi
}

for c in "docker compose up -d" "docker-compose up -d db web" "docker compose -f a.yml -f b.yml up" \
  "docker run --rm alpine true" "docker build -t x ." "docker buildx build ." \
  "vendor/bin/phpunit --filter Foo" "cd api && phpunit tests/X.php" "ember test -s" "yarn test:unit --run" \
  "npm test" "npm run test" "pnpm test" "npx vitest run" "npx playwright test" "bats test/" "cypress run" \
  "pytest -q" "go test ./..." "cargo build" "./gradlew test" "mvn -q package" \
  "yarn lint" "npx run-s lint:*" "eslint src" "phpcs app" "rubocop" "npm run build" "yarn build" \
  "ember build --environment=production" "vite build" \
  "git add x && git commit -m 'wip' && npx jest --ci" "echo start; yarn lint" 'out=$(npm test)' \
  "make up" "./scripts/dev-up.sh" \
  "python -m pytest -q" "python3 -m pytest tests/unit" "python3.12 -u -m pytest -x" "cd api && python -m tox" \
  "python -m unittest discover"; do
  t ask "$c"
done

for c in "docker ps" "docker compose ps" "docker compose logs -f web" "docker logs web" "docker exec -i web sh" \
  "git log --oneline" "cat phpunit.xml" "grep -rn lint package.json" "ssh devbox 'cd Dev/x && npm test'" \
  "ssh -t devbox 'pytest'" "devbox ssh 'npm test'" "gh pr view 1" "npm install" "yarn install" "go vet ./..." \
  "make lint-fix-docs" "make" "DEVBOX_RUN=local yarn lint" "cd x && DEVBOX_RUN=local vendor/bin/phpunit" \
  'gh issue comment 66 -b "uses jest 29 and yarn test and docker compose up"' "echo 'run pytest later'" \
  "python -m pip install -r requirements.txt" "python3 -m venv .venv" "python -c 'import pytest'" "python -m"; do
  t allow "$c"
done
t allow "$(printf '%s\n' "cat >> notes.md <<'EOF'" "- jest 29 snapshot; ran yarn test on the box" \
  "- docker compose up worked" "EOF" "git add notes.md")"
# Regression: a board update + issue comment + heredoc note that mentions jest (false positive in v1).
t allow "$(printf '%s\n' 'for u in a/issues/66; do gh project item-add 80 --owner o --url x; done' \
  'gh issue comment 66 -b "drift: jest 29 snapshot format; new Native Tests workflow"' \
  "cat >> sessions/x.md <<'EOF'" '- jest 29 format. Tests ran on the devbox.' 'EOF' \
  'git add sessions/x.md && git commit -q -m "session: Native Tests workflow"')"

# On the box itself the guard is a no-op.
touch "$T/not-a-box"
t allow "npm test"; t allow "docker compose up -d"
rm -f "$T/not-a-box"

# A custom SSH alias is recognized as "already on the box".
out=$(printf 'DEVBOX_NAME=x\nAWS_REGION=us-east-1\nSSH_HOST_ALIAS=buildbox\n' >"$DEVBOX_CONFIG_DIR/x.env"; echo x >"$DEVBOX_CONFIG_DIR/default"; \
  jq -n '{tool_input:{command:"ssh buildbox \"npm test\""},cwd:"/tmp"}' | sh "$H")
[[ -z "$out" ]] && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL custom alias not recognized"; }

echo "guard: pass=$pass fail=$fail"
exit $(( fail > 0 ))
