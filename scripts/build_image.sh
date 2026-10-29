#!/usr/bin/env bash
# Build one Android Bench task image locally and tag it with the registry name
# Harbor expects, so Harbor uses the local image instead of pulling.
#
# Needed because Google's public registry (android-bench-public) currently
# rejects pulls ("requires billing to be enabled"). The Harbor task Dockerfiles
# are the same ones the archived android-bench repo generates, so this builds
# the same image: Ubuntu 22.04 + Android SDK/emulators -> repo base -> task.
#
# Usage: scripts/build_image.sh <task-name>     e.g. lemmynet__jerboa-pr_941
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK="${1:?usage: build_image.sh <task-name>}"
AB_SHA="${AB_SHA:-65a86bf41e45dde517a65d6e65a6dc7cdd2063ea}"  # android-bench main when archived (2026-07-08)
SRC="$ROOT/.cache/android-bench"
REGISTRY="us-central1-docker.pkg.dev/android-bench-public/android-bench-tasks"
TARGET="$REGISTRY/$TASK:latest"

if docker image inspect "$TARGET" >/dev/null 2>&1; then exit 0; fi

if [[ ! -d "$SRC/.git" ]]; then
  git clone -q https://github.com/android-bench/android-bench "$SRC"
  git -C "$SRC" checkout -q "$AB_SHA"
fi

# The archived repo keeps the original-case id (LemmyNet__jerboa-pr_941); Harbor lowercases it.
ID="$(ls "$SRC/dataset/tasks" | grep -ix -- "$TASK" || true)"
[[ -n "$ID" ]] || { echo "task $TASK not found in archived android-bench repo" >&2; exit 1; }

# Builds android-bench-env (cached after the first time), <repo>-base, then the task image.
(cd "$SRC" && uv run build_images --build --task_id "$ID" --max_workers 1)

# The builder doesn't fail with a non-zero exit code, so check the result directly.
docker image inspect "$TASK" >/dev/null 2>&1 || { echo "build failed for $TASK" >&2; exit 1; }
docker tag "$TASK" "$TARGET"
echo "built $TARGET"
