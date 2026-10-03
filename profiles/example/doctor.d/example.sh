#!/usr/bin/env bash
# Example profile check, run by devbox-doctor on the box. FULL=1 during `devbox doctor`.
n=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
printf '  \033[32m✓\033[0m containers running: %s\n' "$n"
