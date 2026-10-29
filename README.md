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
You need x86_64 Linux with KVM, 32 GB RAM per concurrent trial, Docker, and [uv](https://docs.astral.sh/uv/).

```bash
uv tool install harbor
export ANTHROPIC_API_KEY=...   # or OPENAI_API_KEY / GEMINI_API_KEY
scripts/prepare_skills.sh      # pin + flatten android/skills
AGENT_CONFIGS="claude-code|anthropic/claude-haiku-5-5|medium" scripts/run_matrix.sh pilot
scripts/run_matrix.sh core && scripts/run_matrix.sh targeted
python3 scripts/analyze.py     # writes results/summary.md and results/trials.csv
```

The run script is idempotent: re-run it after a crash and it skips finished jobs.
