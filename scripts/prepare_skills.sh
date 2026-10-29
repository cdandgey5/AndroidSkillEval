#!/usr/bin/env bash
# Clone android/skills at a pinned commit and flatten it into skills/all/<skill-name>/.
# Harbor's --skill <dir> expects a root whose immediate children each contain SKILL.md,
# but android/skills nests them (e.g. build-system/agp/agp-9-upgrade/SKILL.md).
set -euo pipefail

SKILLS_SHA="${SKILLS_SHA:-6daa53ef27fa2aa87827d183a85c06cedceca833}"  # android/skills main @ 2026-10-29
# android-cli tells the agent to call the `android` binary, which the task images don't ship.
EXCLUDE="${EXCLUDE:-android-cli}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/skills/src"
OUT="$ROOT/skills/all"

rm -rf "$SRC" "$OUT"
mkdir -p "$OUT"
git clone --quiet https://github.com/android/skills "$SRC"
git -C "$SRC" checkout --quiet "$SKILLS_SHA"

find "$SRC" -name SKILL.md -not -path '*/.git/*' | sort | while read -r f; do
  dir="$(dirname "$f")"
  name="$(basename "$dir")"
  if [[ " $EXCLUDE " == *" $name "* ]]; then
    echo "skip  $name"
    continue
  fi
  if [[ -e "$OUT/$name" ]]; then
    echo "duplicate skill name: $name" >&2
    exit 1
  fi
  cp -r "$dir" "$OUT/$name"
done

# One directory per skill too, for the forced (single-skill) condition.
mkdir -p "$ROOT/skills/single"
for d in "$OUT"/*/; do
  name="$(basename "$d")"
  mkdir -p "$ROOT/skills/single/$name"
  cp -r "$d" "$ROOT/skills/single/$name/$name"
done

{
  echo "# Skills lock"
  echo
  echo "- Source: https://github.com/android/skills"
  echo "- Commit: \`$SKILLS_SHA\`"
  echo "- Excluded: \`$EXCLUDE\`"
  echo
  echo "| Skill | SKILL.md chars | sha256 (all files) |"
  echo "|---|---|---|"
  for d in "$OUT"/*/; do
    name="$(basename "$d")"
    chars="$(wc -c < "$d/SKILL.md")"
    digest="$(cd "$d" && find . -type f | sort | xargs sha256sum | sha256sum | cut -c1-16)"
    echo "| $name | $chars | $digest |"
  done
} > "$ROOT/config/SKILLS_LOCK.md"

echo "flattened $(ls "$OUT" | wc -l) skills into $OUT"
