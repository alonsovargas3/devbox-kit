#!/usr/bin/env bash
# bootstrap-tools.sh — system tooling on the box's ROOT volume. Idempotent.
# `devbox bootstrap` runs it over SSH; re-run after replacing the instance or an Ubuntu
# upgrade. Everything under /home already lives on the data volume (Claude Code, logins,
# repos), but apt packages and /usr/local/bin do not.
#
#   GCLOUD=on|off  install gcloud (default off)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
GCLOUD="${GCLOUD:-off}"
case "$(uname -m)" in
  x86_64)  awsarch=x86_64;  smp=ubuntu_64bit; debarch=amd64 ;;
  aarch64) awsarch=aarch64; smp=ubuntu_arm64; debarch=arm64 ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac
has() { command -v "$1" >/dev/null 2>&1; }

# build-essential: Orca's SSH relay compiles node-pty on Linux (no prebuilt); without
# make/g++ remote terminals fail with "could not locate its node-pty install directory".
sudo -E apt-get update -qq
sudo -E apt-get install -y -qq unzip git jq tmux ripgrep apt-transport-https gnupg build-essential python3 >/dev/null

# Node 22 in /usr/bin: Orca's relay runs on the NON-interactive PATH (no nvm/Volta shims).
if ! has node || [[ "$(readlink -f "$(command -v node)")" != /usr/bin/node ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null
  sudo -E apt-get install -y -qq nodejs >/dev/null
fi

if ! has aws; then
  (cd /tmp && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awsarch}.zip" -o awscli.zip \
    && unzip -q -o awscli.zip && sudo ./aws/install >/dev/null && rm -rf aws awscli.zip)
fi
if ! has session-manager-plugin; then
  curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${smp}/session-manager-plugin.deb" -o /tmp/smp.deb
  sudo dpkg -i /tmp/smp.deb >/dev/null && rm /tmp/smp.deb
fi
if ! has gh; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  echo "deb [arch=${debarch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo -E apt-get update -qq && sudo -E apt-get install -y -qq gh >/dev/null
fi
if [[ "$GCLOUD" == on ]] && ! has gcloud; then
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  sudo -E apt-get update -qq && sudo -E apt-get install -y -qq google-cloud-cli >/dev/null
fi

# Claude Code lives in ~/.local (data volume); expose it on the system PATH so Orca's
# non-interactive shells and sudo find it.
[[ -x "$HOME/.local/bin/claude" ]] || curl -fsSL https://claude.ai/install.sh | bash >/dev/null
sudo ln -sf "$HOME/.local/bin/claude" /usr/local/bin/claude

v() { "$@" 2>/dev/null | head -1; }
echo "node $(v /usr/bin/node --version) | $(v aws --version | cut -d' ' -f1) | smp $(v session-manager-plugin --version)"
echo "$(v gh --version) | docker $(v docker --version | cut -d' ' -f3 | tr -d ,) | claude $(v claude --version | cut -d' ' -f1)${GCLOUD:+ | gcloud: $( [[ $GCLOUD == on ]] && v gcloud --version || echo off)}"
