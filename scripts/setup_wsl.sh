#!/usr/bin/env bash
# One-time setup inside Ubuntu (WSL2 on Windows 11, or native Ubuntu).
# Installs Docker Engine, the tools the scripts use, uv and Harbor, and makes
# /dev/kvm usable on every WSL start. Safe to run more than once.
#
# Usage: bash scripts/setup_wsl.sh            (DRY_RUN=1 prints the commands instead)
set -euo pipefail
ME="${USER:-$(id -un)}"

HARBOR_VERSION="${HARBOR_VERSION:-0.25.0}"  # the version these scripts were checked against
run() { echo "+ $*"; [[ -n "${DRY_RUN:-}" ]] || "$@"; }
say() { echo; echo "=== $*"; }
in_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

say "1/6 Basic tools (git, python3, curl, kvm-ok, tmux)"
run sudo apt-get update -q
run sudo apt-get install -y -q git python3 curl ca-certificates cpu-checker tmux

say "2/6 Docker Engine"
if docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -qi "docker desktop"; then
  echo "This Ubuntu is using Docker Desktop. Docker Desktop can't give the Android emulator KVM access."
  echo "In Docker Desktop: Settings > Resources > WSL integration > turn OFF Ubuntu (or quit Docker Desktop),"
  echo "then run this script again."
  exit 1
fi
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  echo "Docker Engine with the compose plugin is already installed"
else
  # Docker's official installer. Under WSL it prints a Docker Desktop notice and waits 20 s, then continues.
  run curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  run sudo sh /tmp/get-docker.sh
fi
run sudo usermod -aG docker "$ME"
if [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]]; then
  run sudo systemctl enable --now docker
else
  echo "systemd isn't running yet; Docker will start automatically after the WSL restart below"
fi

say "3/6 KVM access for the Android emulator"
if in_wsl; then
  # Make /dev/kvm usable by your user on every WSL start, and make sure systemd is on.
  if ! grep -q 'chmod 666 /dev/kvm' /etc/wsl.conf 2>/dev/null; then
    if grep -q '^\[boot\]' /etc/wsl.conf 2>/dev/null; then
      run sudo sed -i '/^\[boot\]/a command = chmod 666 /dev/kvm' /etc/wsl.conf
    else
      echo "+ append [boot] section to /etc/wsl.conf"
      [[ -n "${DRY_RUN:-}" ]] || printf '\n[boot]\nsystemd=true\ncommand = chmod 666 /dev/kvm\n' | sudo tee -a /etc/wsl.conf >/dev/null
    fi
  fi
  grep -q '^systemd *= *true' /etc/wsl.conf 2>/dev/null || [[ -n "${DRY_RUN:-}" ]] \
    || sudo sed -i '/^\[boot\]/a systemd=true' /etc/wsl.conf
  echo "/etc/wsl.conf now contains:"; sed 's/^/    /' /etc/wsl.conf 2>/dev/null || true
else
  run sudo groupadd -f kvm
  run sudo usermod -aG kvm "$ME"
fi

say "4/6 uv (Python tool installer)"
if ! command -v uv >/dev/null && [[ ! -x "$HOME/.local/bin/uv" ]]; then
  run sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
fi
export PATH="$HOME/.local/bin:$PATH"

say "5/6 Harbor $HARBOR_VERSION (benchmark runner)"
run uv tool install --force "harbor==$HARBOR_VERSION"

say "6/6 Done"
cat <<EOF

Next:
  1. In Windows PowerShell, run:   wsl --shutdown
  2. Open Ubuntu again from the Start menu, then run:
       cd ~/AndroidSkillEval && scripts/check_machine.sh
     Every line should say OK or WARN, with no FAIL. Then run scripts/phase0.sh.
EOF
