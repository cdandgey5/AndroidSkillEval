#!/usr/bin/env bash
# Check whether this machine can run Android Bench locally, and suggest settings.
# Run it inside Linux (native, or the Ubuntu distro in WSL2 on Windows 11).
set -uo pipefail

ok=1
pass() { echo "  OK    $*"; }
fail() { echo "  FAIL  $*"; ok=0; }
warn() { echo "  WARN  $*"; }

echo "Hardware"
arch="$(uname -m)"
[[ "$arch" == "x86_64" ]] && pass "CPU architecture: $arch" || fail "CPU architecture: $arch (needs x86_64 Intel/AMD; Macs can't run this)"
threads="$(nproc)"
ram_gb="$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)"
(( threads >= 8 )) && pass "CPU threads: $threads" || warn "CPU threads: $threads (fewer than 8: set EXTRA_HARBOR_ARGS=\"--cpus ignore\")"
(( ram_gb >= 30 )) && pass "RAM visible to Linux: ${ram_gb} GB" \
  || fail "RAM visible to Linux: ${ram_gb} GB (need ~32 GB per trial; on WSL2 raise 'memory=' in %UserProfile%\\.wslconfig)"
if grep -qi microsoft /proc/version 2>/dev/null; then warn "Running in WSL2: keep Windows awake, disable sleep, and use Docker Engine inside this distro (not Docker Desktop)"; fi

echo "Virtualization"
if [[ -e /dev/kvm ]]; then
  [[ -r /dev/kvm && -w /dev/kvm ]] && pass "/dev/kvm is usable" || fail "/dev/kvm exists but isn't writable: sudo usermod -aG kvm \$USER, then log out and in"
else
  fail "/dev/kvm missing: enable VT-x/AMD-V (SVM) in BIOS; on WSL2 needs Windows 11 (nestedVirtualization is on by default)"
fi

echo "Software"
if command -v docker >/dev/null; then
  docker info >/dev/null 2>&1 && pass "docker: $(docker --version | cut -d, -f1)" || fail "docker installed but not usable by this user: sudo usermod -aG docker \$USER"
  docker compose version >/dev/null 2>&1 && pass "docker compose plugin" || fail "docker compose plugin missing: curl -fsSL https://get.docker.com | sudo sh"
  root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)" || root=/var/lib/docker
else
  fail "docker missing: curl -fsSL https://get.docker.com | sudo sh"
  root=/var/lib
fi
while [[ ! -d "$root" ]]; do root="$(dirname "$root")"; done  # nearest existing dir
free_gb="$(df -BG --output=avail "$root" 2>/dev/null | tail -1 | tr -dc 0-9)"
(( ${free_gb:-0} >= 300 )) && pass "free disk for Docker ($root): ${free_gb} GB" \
  || fail "free disk for Docker ($root): ${free_gb:-?} GB (need ~300 GB: shared SDK image + repo bases + one task image + build cache)"
command -v uv >/dev/null && pass "uv" || fail "uv missing: curl -LsSf https://astral.sh/uv/install.sh | sh"
command -v harbor >/dev/null && pass "harbor $(harbor --version 2>/dev/null)" || fail "harbor missing: uv tool install harbor"

echo "Task images"
REG=us-central1-docker.pkg.dev; REPO=android-bench-public/android-bench-tasks/airbnb__lottie-android-pr_2427
resp="$(curl -sS "https://$REG/v2/token?scope=repository:$REPO:pull&service=$REG" 2>&1)"
if [[ "$resp" == *'"token"'* ]]; then pass "Google's image registry serves pulls"
else warn "Google's image registry rejects pulls ($(echo "$resp" | grep -o 'requires billing[^.]*' || echo 'error')): images will be built locally (scripts/build_image.sh), ~10-30 min per task"; fi

echo
slots=$(( ram_gb / 32 )); cpu_slots=$(( threads / 8 )); (( cpu_slots < slots )) && slots=$cpu_slots; (( slots < 1 )) && slots=1
if (( ok )); then
  echo "Verdict: this machine can run the benchmark. Suggested: N_CONCURRENT=$slots"
  (( threads < 8 )) && echo "         and EXTRA_HARBOR_ARGS=\"--cpus ignore\""
else
  echo "Verdict: fix the FAIL lines above first (or use the cloud VM in PLAN.md section 6)."
fi
