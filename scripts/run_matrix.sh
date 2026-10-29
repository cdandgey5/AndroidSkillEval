#!/usr/bin/env bash
# Run the with/without-skills matrix on Android Bench 1.0 via Harbor.
#
# Per task: get the image (local, else pull, else build it locally with
# scripts/build_image.sh), run the oracle (drop the task if the reference fix
# fails on this machine), run every agent condition, then delete the task image.
# Each image is fetched once and the disk holds one task image at a time.
#
# One Harbor job per (agent config, condition, task). A job counts as done only
# when its result.json has finished_at set (Harbor writes result.json when a job
# starts), so the script is safe to re-run after a crash or spot preemption.
#
# Usage:
#   scripts/run_matrix.sh pilot      # 10 fixed tasks, C0 + C1, k=1 -> jobs/pilot
#   scripts/run_matrix.sh targeted   # targeted tasks, C0/C1/C2, k=5 -> jobs/main
#   scripts/run_matrix.sh core       # all tasks (targeted ones are skipped if done) -> jobs/main
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PHASE="${1:?usage: run_matrix.sh pilot|targeted|core}"
DATASET="${DATASET:-android-bench/android-bench}"
ORACLE_JOBS="$ROOT/jobs/oracle"
N_CONCURRENT="${N_CONCURRENT:-3}"  # each trial asks for 8 CPU / 32 GB; scripts/check_machine.sh suggests a value
# Extra flags for every harbor run, e.g. "--cpus ignore" on a PC with fewer than 8 CPU threads.
read -r -a EXTRA_HARBOR_ARGS <<<"${EXTRA_HARBOR_ARGS:-}"
REGISTRY="us-central1-docker.pkg.dev/android-bench-public/android-bench-tasks"
K_CORE="${K_CORE:-3}"
K_TARGETED="${K_TARGETED:-5}"
# Optional agent-timeout cap, decided in the pilot (default task timeout is 20,000 s).
AGENT_TIMEOUT_MULT="${AGENT_TIMEOUT_MULT:-1}"

# "agent|model|effort|version". Leave version empty in the pilot, then pin the
# version the pilot installed. Confirm exact model ids with your provider.
read -r -a AGENT_CONFIGS <<<"${AGENT_CONFIGS:-claude-code|anthropic/claude-haiku-5-5|medium|}"

PILOT_TASKS=(  # 3 tier-1 targeted + 7 non-targeted of mixed size
  android__nowinandroid-pr_553 coil-kt__coil-pr_1964 lemmynet__jerboa-pr_941
  airbnb__lottie-android-pr_2427 coil-kt__coil-pr_2033 usuiat__zoomable-pr_334
  tuskyapp__tusky-pr_4821 thunderbird__thunderbird-android-pr_8020
  mohamedrejeb__compose-rich-editor-pr_335 pocketcasts-room-3
)

COMMON_ARGS=(-r 2 -n "$N_CONCURRENT" -q -y "${EXTRA_HARBOR_ARGS[@]}")

mapfile -t TARGETED < <(python3 -c "import json;[print(t['task']) for t in json.load(open('$ROOT/config/targeted_tasks.json'))['tasks']]")
is_targeted() { [[ " ${TARGETED[*]} " == *" $1 "* ]]; }
skill_for() { python3 -c "import json,sys;print(next(t['skill'] for t in json.load(open('$ROOT/config/targeted_tasks.json'))['tasks'] if t['task']==sys.argv[1]))" "$1"; }

job_done() {
  [[ -f "$1/result.json" ]] && python3 -c "import json,sys;sys.exit(0 if json.load(open(sys.argv[1])).get('finished_at') else 1)" "$1/result.json"
}

oracle_passed() {
  python3 - "$1" <<'PY'
import json, pathlib, sys
rs = [json.loads(p.read_text()) for p in pathlib.Path(sys.argv[1]).glob("*/result.json")]
sys.exit(0 if any(((r.get("verifier_result") or {}).get("rewards") or {}).get("reward") == 1 for r in rs) else 1)
PY
}

oracle_dir() { echo "$ORACLE_JOBS/oracle__none__OR__${1}__k1"; }

run_oracle() {  # returns 0 if the reference solution passes on this machine
  local task="$1" dir; dir="$(oracle_dir "$1")"
  if ! job_done "$dir"; then
    rm -rf "$dir"
    harbor run -d "$DATASET" -i "*$task" -a oracle -k 1 -o "$ORACLE_JOBS" --job-name "$(basename "$dir")" \
      "${COMMON_ARGS[@]}" || true
  fi
  oracle_passed "$dir"
}

job_name() {  # job_name <agent_cfg> <condition> <task> <k>
  local agent model effort version
  IFS='|' read -r agent model effort version <<<"$1"
  echo "${agent}__${model//\//-}${effort:+-$effort}__${2}__${3}__k${4}"
}

run_one() {  # run_one <agent_cfg> <condition> <task> <k>
  local cfg="$1" cond="$2" task="$3" k="$4"
  local agent model effort version
  IFS='|' read -r agent model effort version <<<"$cfg"
  local name; name="$(job_name "$cfg" "$cond" "$task" "$k")"
  if job_done "$JOBS/$name"; then echo "done  $name"; return; fi
  rm -rf "${JOBS:?}/$name"

  local args=(--ak disable_web_search=true --agent-timeout-multiplier "$AGENT_TIMEOUT_MULT")
  [[ -n "$effort" ]] && args+=(--effort "$effort")
  [[ -n "$version" ]] && args+=(--ak "version=$version")
  case "$cond" in
    C0) ;;                                                   # baseline: no skills
    C1) args+=(--skill "$ROOT/skills/all") ;;                # all official skills, agent decides
    C2) local s; s="$(skill_for "$task")"                    # only the matching skill, explicitly requested
        args+=(--skill "$ROOT/skills/all/$s"
               --extra-instruction "Before you start, read the \`$s\` skill and follow it.") ;;
  esac

  echo "run   $name"
  harbor run -d "$DATASET" -i "*$task" -a "$agent" -m "$model" -k "$k" \
    -o "$JOBS" --job-name "$name" "${COMMON_ARGS[@]}" "${args[@]}" \
    || echo "FAIL  $name (re-run the script to retry)"
}

ensure_image() {  # returns 0 once the task image is available locally under its registry name
  local task="$1" img="$REGISTRY/$1:latest" marker="$ORACLE_JOBS/build_failed__$1"
  [[ -f "$marker" ]] && return 1
  docker image inspect "$img" >/dev/null 2>&1 && return 0
  docker pull -q "$img" >/dev/null 2>&1 && return 0
  echo "build $task (registry pull failed; building locally)"
  if "$ROOT/scripts/build_image.sh" "$task" >"$ORACLE_JOBS/build__$task.log" 2>&1; then return 0; fi
  touch "$marker"  # don't retry a failed build on every re-run; delete the marker to retry
  return 1
}

prune_task_image() {  # keep the shared SDK and per-repo base images; drop the task image
  docker rmi -f "$REGISTRY/$1:latest" "$1" >/dev/null 2>&1 || true
  docker image prune -f >/dev/null || true
}

run_task_block() {  # run_task_block <task> <k> <conditions...>
  local task="$1" k="$2"; shift 2
  # Decide from finished jobs alone first, so a re-run never fetches or rebuilds an image it won't use.
  if job_done "$(oracle_dir "$task")" && ! oracle_passed "$(oracle_dir "$task")"; then
    echo "drop  $task (oracle failed on this machine)"; return
  fi
  local pending=0 cfg cond
  job_done "$(oracle_dir "$task")" || pending=1
  for cfg in "${AGENT_CONFIGS[@]}"; do
    for cond in "$@"; do job_done "$JOBS/$(job_name "$cfg" "$cond" "$task" "$k")" || pending=1; done
  done
  if (( ! pending )); then echo "done  $task"; return; fi

  if ! ensure_image "$task"; then
    echo "drop  $task (image build failed; see $ORACLE_JOBS/build__$task.log)"
    return
  fi
  if ! run_oracle "$task"; then
    echo "drop  $task (oracle failed on this machine)"
    prune_task_image "$task"
    return
  fi
  # Shuffle condition order per task so time-of-day / API drift doesn't line up with one condition.
  local conds; conds=$(printf '%s\n' "$@" | shuf)
  for cfg in "${AGENT_CONFIGS[@]}"; do
    for cond in $conds; do run_one "$cfg" "$cond" "$task" "$k"; done
  done
  prune_task_image "$task"
}

plan_task() {  # full-study plan for one task
  if is_targeted "$1"; then run_task_block "$1" "$K_TARGETED" C0 C1 C2
  else run_task_block "$1" "$K_CORE" C0 C1; fi
}

all_tasks() {
  local dir="$ROOT/.cache/dataset/${DATASET#*/}"
  for _ in 1 2 3; do
    [[ -d "$dir" ]] && break
    harbor download "$DATASET" -o "$ROOT/.cache/dataset" >/dev/null 2>&1 || sleep 5
  done
  ls "$dir" 2>/dev/null || true
}

[[ -d "$ROOT/skills/all" ]] || "$ROOT/scripts/prepare_skills.sh"
mkdir -p "$ORACLE_JOBS"

case "$PHASE" in
  pilot)
    JOBS="$ROOT/jobs/pilot"; mkdir -p "$JOBS"
    for t in "${PILOT_TASKS[@]}"; do run_task_block "$t" 1 C0 C1; done ;;
  targeted)
    JOBS="$ROOT/jobs/main"; mkdir -p "$JOBS"
    for t in "${TARGETED[@]}"; do plan_task "$t"; done ;;
  core)
    JOBS="$ROOT/jobs/main"; mkdir -p "$JOBS"
    mapfile -t TASKS < <(all_tasks)
    (( ${#TASKS[@]} == 100 )) || { echo "expected 100 tasks, got ${#TASKS[@]}; check 'harbor download $DATASET'" >&2; exit 1; }
    for t in "${TASKS[@]}"; do plan_task "$t"; done ;;
  *) echo "unknown phase: $PHASE" >&2; exit 1 ;;
esac
