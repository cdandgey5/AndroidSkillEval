# AndroidSkillEval

**Do Google's official Android skills improve coding-agent results?** This repo is an independent, pre-registered benchmark of [`android/skills`](https://github.com/android/skills) on [Android Bench 1.0](https://developer.android.com/bench), run with [Harbor](https://docs.harborframework.com).

- Full plan: [PLAN.md](PLAN.md)
- Hypotheses and analysis, fixed before the runs: [PREREGISTRATION.md](PREREGISTRATION.md)
- Results: `results/summary.md`, once the runs finish

## Conditions
| ID | Setup |
|---|---|
| C0 | No skills |
| C1 | All official skills installed; the agent decides when to use them |
| C2 | Only the relevant skill, and the agent is told to use it (targeted tasks only) |

## Reproduce
You need an x86_64 PC running Linux, or Windows 11 with WSL2, with KVM, 32 GB RAM per concurrent trial, about 300 GB free disk, Docker, and [uv](https://docs.astral.sh/uv/). A Mac won't work. No cloud account is needed. Run `scripts/check_machine.sh` to check your PC.

Google's public registry for the task images currently rejects pulls, so the run script builds each image locally (`scripts/build_image.sh`) from Google's archived builder. See [PLAN.md](PLAN.md) section 6.

```bash
uv tool install harbor
export ANTHROPIC_API_KEY=...   # or OPENAI_API_KEY / GEMINI_API_KEY
scripts/prepare_skills.sh      # pin + flatten android/skills
export AGENT_CONFIGS="claude-code|anthropic/claude-haiku-5-5|medium|"   # agent|model|effort|version
scripts/run_matrix.sh pilot    # 10 tasks, k=1, separate output
scripts/run_matrix.sh targeted # 9 targeted tasks, C0/C1/C2, k=5
scripts/run_matrix.sh core     # remaining tasks, C0/C1, k=3
python3 scripts/analyze.py     # writes results/summary.md and results/trials.csv
```

For each task, the run script runs Google's reference solution (the oracle) first and drops the task if it fails. Then it runs every condition and deletes the task image. Re-run it after a crash or preemption: it resumes interrupted jobs and skips finished ones. Raw output goes to `jobs/oracle`, `jobs/pilot` and `jobs/main`.
