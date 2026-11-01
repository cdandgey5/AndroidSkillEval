# Pre-registration

Commit this file before any agent run. The commit timestamp shows that the hypotheses and the analysis were fixed in advance. If you change it later, add a dated entry under "Deviations" and give the reason.

## Hypotheses
- **H1 (help on target):** on the 9 targeted tasks (`config/targeted_tasks.json`), C1 (all skills) scores higher than C0 (no skills). With 9 tasks, this is reported as an estimate with its CI. It's expected to be directional only.
- **H2 (no meaningful harm elsewhere):** on non-targeted tasks, C1 is non-inferior to C0. That means the lower bound of the 95% CI on the C1 − C0 delta is above the margin for the chosen study size: −10 percentage points (full) or −20 (lean).
- **H3 (triggering gap):** on targeted tasks, C2 (forced skill) scores at least as high as C1.
- **H4 (skill opens):** in C1, agents open the target skill in fewer than 100% of targeted trials.
- **H5 (cost):** C1 uses more input tokens per trial than C0 on non-targeted tasks.

## Study size (choose one before the first main run, and write it here)
- **Full:** all 100 tasks. Targeted tasks at k=5 (C0/C1/C2), the other 91 at k=3 (C0/C1). 681 agent trials. H2 margin −10 pp.
- **Lean:** the 9 targeted tasks at k=3 (C0/C1/C2), plus the 6 harm-watch tasks and a fixed sample of 40 other tasks at k=2 (C0/C1). 265 agent trials. H2 margin **−20 pp**, because about 46 tasks at k=2 give a CI of roughly ±15 pp. The 40 are the tasks outside both slices with the lowest sha256 of their name. The full list is in `config/LEAN_TASKS.md`, and the non-targeted slice includes the harm-watch tasks.
- **Chosen: lean** (decided 2026-11-01, before any agent run). Full may follow later as a separate, labelled extension.

## Fixed before running
- **Dataset:** Android Bench 1.0 (`android-bench/android-bench` on Harbor Hub), 100 tasks. Each task's oracle runs first on our machine. A task whose oracle fails is dropped before any agent trial, and the results list it.
- **Skills:** `android/skills` at commit `6daa53ef27fa2aa87827d183a85c06cedceca833`, all skills except `android-cli`, whose `android` binary isn't in the task images. Hashes are in `config/SKILLS_LOCK.md`.
- **Targeted slice:** the 9 tasks in `config/targeted_tasks.json`. Tier 1 is 6 tasks; tiers 1+2 together are 9.
- **Harm-watch slice:** the 6 tasks under `harm_watch` in the same file. Descriptive only, no hypothesis.
- **Conditions:**
  - C0: no skills.
  - C1: `--skill skills/all`.
  - C2: `--skill skills/all/<skill>` plus the extra instruction "Before you start, read the `<skill>` skill and follow it."
- **Same in every condition:**
  - web tools disabled (`disable_web_search=true`)
  - the same agent version, model and reasoning effort
  - the same agent timeout
  - up to 2 Harbor retries
  - condition order shuffled per task
- **Trials:** as set by the chosen study size above.
- **Model selection:** in the pilot (10 fixed tasks, k=1), pick the first model whose **C0** pass rate is between 40% and 75%. C1 pilot results are never used for model choice. Pilot trials are kept separate and are not part of the main analysis.

## Analysis
- **Primary metric:** Android Bench pass/fail reward (all fail-to-pass and pass-to-pass tests pass).
- **Task score:** the mean reward over that task's trials.
- **Effect:** the paired mean of (condition B − condition A) over shared tasks, in percentage points.
- **Uncertainty:** 95% paired bootstrap CI over tasks (10,000 resamples, seed 0), plus win/loss counts.
- **Slices, all reported whatever the result:** all tasks, targeted tier 1, targeted (all), non-targeted, and harm watch.
- **Exclusions:** trials with no verifier reward (environment or verifier failure) are excluded and counted per condition. Agent timeouts and crashes still get a verifier reward, and count as they score.
- **Skill opens:** a trial counts if an ATIF tool call is a Skill call naming the skill or touches `skills/<skill>/`.
- **Implementation:** `scripts/analyze.py` at the commit that adds this file. For the lean study, run it as `H2_MARGIN_PP=-20 python3 scripts/analyze.py`.

## Filled in after the pilot, before the main runs
- Agent / model / effort / version: _TBD_
- Pilot C0 pass rate on the 10 tasks: _TBD_
- Agent timeout multiplier (default 1 = 20,000 s): _TBD_

## Deviations
_None yet._
