# Pre-registration

Commit this file before any agent run. The commit timestamp shows that the hypotheses and the analysis were fixed in advance. If you change it later, add a dated entry under "Deviations" and give the reason.

## Hypotheses
- **H1 (help on target):** on the 11 targeted tasks (`config/targeted_tasks.json`), C1 (all skills) scores higher than C0 (no skills).
- **H2 (no harm elsewhere):** on the 89 non-targeted tasks, the C1 − C0 delta lies within ±3 pp.
- **H3 (triggering gap):** on targeted tasks, C2 (forced skill) scores at least as high as C1.
- **H4 (activation):** in C1, agents open the target skill in fewer than 100% of targeted trials.
- **H5 (cost):** C1 uses more input tokens per trial than C0 on non-targeted tasks.

## Fixed before running
- **Dataset:** Android Bench 1.0 (`android-bench/android-bench` on Harbor Hub), 100 tasks. Tasks the oracle fails on our infra are dropped before any agent run, and the post lists them.
- **Skills:** `android/skills` at commit `6daa53ef27fa2aa87827d183a85c06cedceca833`, all skills except `android-cli`. Hashes are in `config/SKILLS_LOCK.md`.
- **Targeted slice:** the 11 tasks in `config/targeted_tasks.json`. Tier 1 is 5 tasks; tiers 1+2 together are 11.
- **Conditions:**
  - C0: no skills.
  - C1: `--skill skills/all`.
  - C2: `--skill skills/single/<skill>` plus the extra instruction "Before you start, read the `<skill>` skill and follow it."
- **Same in every condition:**
  - web tools disabled (`disable_web_search=true`)
  - the same agent version, model and reasoning effort
  - the dataset's own timeouts
  - up to 2 retries for infra errors
- **Trials:**
  - Core: k=3 per task per condition (C0, C1).
  - Targeted: k=5 per task per condition (C0, C1, C2).
- **Model selection:** in the pilot, run C0 on 10 random tasks. Pick the first model whose baseline is between 40% and 75%. The choice is recorded in this file before the core run.

## Analysis
- **Primary metric:** Android Bench binary reward (all fail-to-pass and pass-to-pass tests pass).
- **Task score:** the mean reward over that task's trials.
- **Effect:** the paired mean of (condition B − condition A) over shared tasks, in percentage points.
- **Uncertainty:** 95% paired bootstrap CI over tasks (10,000 resamples, seed 0), plus win/loss counts.
- **Slices, all reported whatever the result:** all tasks, tier 1, tiers 1+2, non-targeted.
- **Exclusions:** trials where the agent never started (infra errors) are excluded. Agent errors and timeouts count as reward 0.
- **Activation:** a trial counts as activated if an ATIF tool call opens `skills/<target-skill>/` or calls the Skill tool with that name.
- **Implementation:** `scripts/analyze.py` at the commit that adds this file.

## Model choice (fill in after the pilot, before the core run)
- Agent / model / effort: _TBD_
- Pilot C0 baseline on 10 tasks: _TBD_

## Deviations
_None yet._
