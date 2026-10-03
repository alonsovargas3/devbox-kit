#!/usr/bin/env bash
# Example profile bootstrap: runs ON THE BOX as ubuntu (`devbox bootstrap`). Idempotent.
set -euo pipefail
# e.g. a Node version manager for projects that pin old Node versions:
# [ -x "$HOME/.volta/bin/volta" ] || { curl -fsSL https://get.volta.sh | bash -s -- --skip-setup; "$HOME/.volta/bin/volta" setup; }
# e.g. a docker-compose v1 shim for older scripts (--compatibility keeps v1 container names):
# printf '#!/bin/sh\nexec docker compose --compatibility "$@"\n' | sudo tee /usr/local/bin/docker-compose >/dev/null
# sudo chmod 755 /usr/local/bin/docker-compose
echo "example profile: nothing to install"
