#!/usr/bin/env bash
# Phase 0: prove this machine can run the benchmark before spending anything on API calls.
#   1. check the machine   2. pin the skills   3. get one task image (pull, else build locally)
#   4. run Google's reference fix (the oracle) on it and check the tests pass
# No API key needed. The first image build also builds the shared Android SDK image (~30-60 min).
#
# Usage: scripts/phase0.sh [task]     (default: airbnb__lottie-android-pr_2427, a small task)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK="${1:-airbnb__lottie-android-pr_2427}"
REGISTRY="us-central1-docker.pkg.dev/android-bench-public/android-bench-tasks"
JOB="oracle__none__OR__${TASK}__k1"   # same name run_matrix.sh uses, so this result is reused later
read -r -a EXTRA_HARBOR_ARGS <<<"${EXTRA_HARBOR_ARGS:-}"
cd "$ROOT"
mkdir -p jobs/oracle
exec > >(tee -a jobs/phase0.log) 2>&1

step() { echo; echo "=== $(date '+%H:%M') $*"; }

step "1/4 Checking this machine"
scripts/check_machine.sh || { echo "Fix the FAIL lines above, then run this again."; exit 1; }

step "2/4 Pinning Android skills"
[[ -d skills/all ]] || scripts/prepare_skills.sh

step "3/4 Getting the task image for $TASK"
if docker image inspect "$REGISTRY/$TASK:latest" >/dev/null 2>&1; then
  echo "already on disk"
elif docker pull "$REGISTRY/$TASK:latest"; then
  echo "pulled from Google's registry"
else
  echo "registry pull failed; building locally (first build ~30-60 min, then ~10-30 min per task)"
  scripts/build_image.sh "$TASK"
fi

step "4/4 Running the reference fix (oracle) on $TASK"
rm -rf "jobs/oracle/$JOB"
harbor run -d android-bench/android-bench -i "*$TASK" -a oracle -k 1 \
  -o jobs/oracle --job-name "$JOB" -y "${EXTRA_HARBOR_ARGS[@]}" || true

if python3 - "jobs/oracle/$JOB" <<'PY'
import json, pathlib, sys
rs = [json.loads(p.read_text()) for p in pathlib.Path(sys.argv[1]).glob("*/result.json")]
sys.exit(0 if any(((r.get("verifier_result") or {}).get("rewards") or {}).get("reward") == 1 for r in rs) else 1)
PY
then
  step "PASS: Docker, KVM, the image build and Harbor all work on this machine."
  echo "Next: add your API key and spend cap, then run the pilot (PLAN.md section 7, Phase 1)."
else
  step "FAIL: the reference fix did not pass. Send jobs/phase0.log and jobs/oracle/$JOB/ to debug."
  exit 1
fi
