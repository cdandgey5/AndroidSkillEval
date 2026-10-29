#!/usr/bin/env bash
# Run the with/without-skills matrix on Android Bench 1.0 via Harbor.
#
# One Harbor job per (agent config, condition, task). Jobs that already have a
# job-level result.json are skipped, so the script is safe to re-run after a crash
# or spot-VM preemption. All conditions for a task run back to back, then the
# task image is deleted: images are big, and pulling each one once saves hours.
#
# Usage:
#   scripts/run_matrix.sh pilot      # 5 tasks, k=1, to measure time and cost
#   scripts/run_matrix.sh core       # all 100 tasks, C0 + C1
#   scripts/run_matrix.sh targeted   # targeted tasks: extra trials + C2 (forced skill)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PHASE="${1:?usage: run_matrix.sh pilot|core|targeted}"
DATASET="${DATASET:-android-bench/android-bench}"
JOBS="${JOBS:-$ROOT/jobs}"
N_CONCURRENT="${N_CONCURRENT:-3}"  # each trial asks for 8 CPU / 32 GB; 3 fit on n2-standard-32
K_CORE="${K_CORE:-3}"
K_TARGETED="${K_TARGETED:-5}"

# "agent|model|effort". Confirm the exact model ids with your provider in the pilot.
AGENT_CONFIGS=(${AGENT_CONFIGS:-"claude-code|anthropic/claude-haiku-5-5|medium"})

# Same for every condition: no web access, so skills are the only new knowledge source.
COMMON_ARGS=(--ak disable_web_search=true -r 2 -n "$N_CONCURRENT" -q -y)

all_tasks() { harbor download "$DATASET" -o "$ROOT/.cache/dataset" >/dev/null 2>&1 || true; ls "$ROOT/.cache/dataset/${DATASET#*/}"; }
targeted_tasks() { python3 -c "import json;[print(t['task']) for t in json.load(open('$ROOT/config/targeted_tasks.json'))['tasks']]"; }
skill_for() { python3 -c "import json,sys;print(next(t['skill'] for t in json.load(open('$ROOT/config/targeted_tasks.json'))['tasks'] if t['task']==sys.argv[1]))" "$1"; }

run_one() {  # run_one <agent_cfg> <condition> <task> <k>
  local cfg="$1" cond="$2" task="$3" k="$4"
  IFS='|' read -r agent model effort <<<"$cfg"
  local name="${agent}__${model//\//-}__${cond}__${task}__k${k}"
  if [[ -f "$JOBS/$name/result.json" ]]; then echo "done  $name"; return; fi
  rm -rf "${JOBS:?}/$name"

  local extra=()
  case "$cond" in
    C0) ;;                                            # baseline: no skills
    C1) extra=(--skill "$ROOT/skills/all") ;;         # all official skills, agent decides
    C2) local s; s="$(skill_for "$task")"             # only the matching skill, explicitly requested
        extra=(--skill "$ROOT/skills/single/$s"
               --extra-instruction "Before you start, read the \`$s\` skill and follow it.") ;;
  esac

  echo "run   $name"
  harbor run -d "$DATASET" -i "*$task" -a "$agent" -m "$model" --effort "$effort" \
    -k "$k" -o "$JOBS" --job-name "$name" "${COMMON_ARGS[@]}" "${extra[@]}" \
    || echo "FAIL  $name (re-run the script to retry)"
}

prune_task_image() {
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -F "/$1:" | xargs -r docker rmi -f >/dev/null || true
}

run_task_block() {  # run_task_block <task> <k> <conditions...>
  local task="$1" k="$2"; shift 2
  # Shuffle condition order per task so time-of-day / API drift doesn't line up with one condition.
  local conds; conds=$(printf '%s\n' "$@" | shuf)
  for cfg in "${AGENT_CONFIGS[@]}"; do
    for cond in $conds; do run_one "$cfg" "$cond" "$task" "$k"; done
  done
  prune_task_image "$task"
}

[[ -d "$ROOT/skills/all" ]] || "$ROOT/scripts/prepare_skills.sh"
mkdir -p "$JOBS"

case "$PHASE" in
  pilot)    for t in $(targeted_tasks | head -3) airbnb__lottie-android-pr_2427 coil-kt__coil-pr_2033; do
              run_task_block "$t" 1 C0 C1; done ;;
  core)     for t in $(all_tasks); do run_task_block "$t" "$K_CORE" C0 C1; done ;;
  targeted) for t in $(targeted_tasks); do run_task_block "$t" "$K_TARGETED" C0 C1 C2; done ;;
  *) echo "unknown phase: $PHASE" >&2; exit 1 ;;
esac
