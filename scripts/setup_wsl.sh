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
# Docker Desktop's WSL integration puts its own `docker` command into the distro (a link into
# /mnt/wsl/docker-desktop). It works without Docker Engine, so `docker` existing proves nothing.
docker_is_desktop() {
  command -v docker >/dev/null || return 1
  [[ "$(readlink -m "$(command -v docker)")" == *docker-desktop* ]] && return 0
  docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -qi "docker desktop"
}

# Run in the distro the guide installs, so you don't end up with the project split across two.
. /etc/os-release
echo "Running in: ${WSL_DISTRO_NAME:-native Linux} ($PRETTY_NAME)"
if in_wsl && [[ "$VERSION_ID" != "24.04" && -z "${ALLOW_ANY_UBUNTU:-}" ]]; then
  echo
  echo "This is not Ubuntu 24.04. The guide uses the distro named Ubuntu-24.04."
  echo "In PowerShell, run:  wsl -d Ubuntu-24.04"
  echo "and run this script there. (To use this distro anyway: ALLOW_ANY_UBUNTU=1 bash scripts/setup_wsl.sh)"
  exit 1
fi

say "1/6 Basic tools (git, python3, curl, kvm-ok, tmux)"
run sudo apt-get update -q
run sudo apt-get install -y -q git python3 curl ca-certificates cpu-checker tmux

say "2/6 Docker Engine"
if docker_is_desktop; then
  echo "The 'docker' command here belongs to Docker Desktop ($(readlink -m "$(command -v docker)"))."
  echo "Docker Desktop can't give the Android emulator KVM access, so this needs Docker Engine instead."
  echo "Do ONE of these in Windows, then run this script again:"
  echo "  a) Uninstall Docker Desktop: Settings > Apps > Installed apps > Docker Desktop > Uninstall"
  echo "  b) Keep it: open Docker Desktop > Settings > Resources > WSL integration, turn OFF"
  echo "     'Enable integration with my default WSL distro' and every distro, Apply & restart, then Quit it."
  echo "     Then in PowerShell run: wsl --shutdown"
  exit 1
fi
if command -v dockerd >/dev/null && docker compose version >/dev/null 2>&1; then
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
  1. Restart WSL. Either type this here (note the .exe):   wsl.exe --shutdown
     or run   wsl --shutdown   in Windows PowerShell. Plain 'wsl' inside Ubuntu is a different tool.
  2. Open "Ubuntu 24.04 LTS" from the Start menu again, then run:
       cd ~/AndroidSkillEval && scripts/check_machine.sh
     Every line should say OK or WARN, with no FAIL. Then run scripts/phase0.sh.
EOF
