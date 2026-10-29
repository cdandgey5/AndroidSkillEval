#!/usr/bin/env python3
"""Summarize Harbor jobs written by run_matrix.sh.

Writes results/trials.csv (one row per trial) and results/summary.md (paired
comparisons with bootstrap CIs). The unit of analysis is the task: each task's
score is the mean reward over its trials, and conditions are compared on the
same tasks only.

Usage: python3 scripts/analyze.py [jobs_dir]
"""

import csv
import json
import random
import statistics
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JOBS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "jobs"
OUT = ROOT / "results"
TARGETED = {t["task"]: t for t in json.loads((ROOT / "config/targeted_tasks.json").read_text())["tasks"]}
SKILL_NAMES = {p.name for p in (ROOT / "skills/all").iterdir()} if (ROOT / "skills/all").exists() else set()
N_BOOT = 10_000


def skills_used(trial_dir):
    """Skill names the agent actually opened, from tool calls in the ATIF trajectory.

    Skill names listed in the system prompt don't count: only a Skill tool call or a
    tool call whose arguments touch skills/<name>/ does.
    """
    path = trial_dir / "agent" / "trajectory.json"
    if not path.exists():
        return None
    used = set()
    for step in json.loads(path.read_text()).get("steps", []):
        for call in step.get("tool_calls") or []:
            args = json.dumps(call.get("arguments", {}))
            if call.get("function_name") == "Skill":
                used |= {s for s in SKILL_NAMES if s in args}
            used |= {s for s in SKILL_NAMES if f"skills/{s}/" in args or f"skills/{s}\"" in args}
    return used


def load_trials():
    rows = []
    for job in sorted(p for p in JOBS.iterdir() if p.is_dir()):
        parts = job.name.split("__")
        if len(parts) < 5:
            continue
        agent, model, cond, task = parts[0], parts[1], parts[2], "__".join(parts[3:-1])
        for trial in sorted(p for p in job.iterdir() if (p / "result.json").exists()):
            r = json.loads((trial / "result.json").read_text())
            ver = r.get("verifier_result") or {}
            ctx = r.get("agent_result") or {}
            exc = (r.get("exception_info") or {}).get("exception_type")
            agent_ran = bool((r.get("agent_execution") or {}).get("started_at"))
            reward = (ver.get("rewards") or {}).get("reward")
            if reward is None and not agent_ran:
                status = "infra_error"  # excluded: the agent never got to work
            else:
                status = "ok" if exc is None else f"agent_error:{exc}"
                reward = float(reward or 0.0)
            used = skills_used(trial)
            rows.append(dict(
                agent=agent, model=model, cond=cond, task=task, trial=trial.name,
                status=status, reward=reward,
                targeted=task in TARGETED, tier=TARGETED.get(task, {}).get("tier", ""),
                target_skill=TARGETED.get(task, {}).get("skill", ""),
                skills_used=";".join(sorted(used)) if used else "",
                target_skill_used="" if used is None or task not in TARGETED
                else int(TARGETED[task]["skill"] in used),
                input_tokens=ctx.get("n_input_tokens"), cache_tokens=ctx.get("n_cache_tokens"),
                output_tokens=ctx.get("n_output_tokens"), cost_usd=ctx.get("cost_usd"),
            ))
    return rows


def per_task(rows, key):
    by = defaultdict(list)
    for r in rows:
        if r["status"] != "infra_error" and r[key] not in (None, ""):
            by[r["task"]].append(float(r[key]))
    return {t: statistics.mean(v) for t, v in by.items()}


def paired(a, b, rng):
    """Mean of (b - a) over shared tasks, with a 95% paired bootstrap CI."""
    tasks = sorted(set(a) & set(b))
    if not tasks:
        return None
    d = [b[t] - a[t] for t in tasks]
    boots = sorted(statistics.mean(rng.choices(d, k=len(d))) for _ in range(N_BOOT))
    return dict(n=len(tasks), a=statistics.mean(a[t] for t in tasks), b=statistics.mean(b[t] for t in tasks),
                delta=statistics.mean(d), lo=boots[int(0.025 * N_BOOT)], hi=boots[int(0.975 * N_BOOT)],
                wins=sum(x > 0 for x in d), losses=sum(x < 0 for x in d))


def pct(x):
    return f"{100 * x:+.1f}" if x is not None else "n/a"


def main():
    rows = load_trials()
    if not rows:
        sys.exit(f"no trials found under {JOBS}")
    OUT.mkdir(exist_ok=True)
    with open(OUT / "trials.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    rng = random.Random(0)
    slices = {
        "All tasks": lambda t: True,
        "Targeted (tier 1)": lambda t: TARGETED.get(t, {}).get("tier") == 1,
        "Targeted (tier 1+2)": lambda t: t in TARGETED,
        "Not targeted": lambda t: t not in TARGETED,
    }
    lines = ["# Results", "", "Score = mean reward per task over its trials. Delta in percentage points, "
             "95% paired bootstrap CI over tasks. W/L = tasks where the second condition scored higher/lower.", ""]
    for (agent, model) in sorted({(r["agent"], r["model"]) for r in rows}):
        sub = [r for r in rows if r["agent"] == agent and r["model"] == model]
        lines += [f"## {agent} + {model}", "",
                  "| Comparison | Slice | Tasks | Before | After | Delta (pp) | 95% CI | W/L |",
                  "|---|---|---|---|---|---|---|---|"]
        for c_a, c_b, label in [("C0", "C1", "No skills → all skills"),
                                ("C0", "C2", "No skills → forced skill"),
                                ("C1", "C2", "All skills → forced skill")]:
            for sname, keep in slices.items():
                a = {t: v for t, v in per_task([r for r in sub if r["cond"] == c_a], "reward").items() if keep(t)}
                b = {t: v for t, v in per_task([r for r in sub if r["cond"] == c_b], "reward").items() if keep(t)}
                res = paired(a, b, rng)
                if res:
                    lines.append(f"| {label} | {sname} | {res['n']} | {100*res['a']:.1f}% | {100*res['b']:.1f}% | "
                                 f"{pct(res['delta'])} | [{pct(res['lo'])}, {pct(res['hi'])}] | {res['wins']}/{res['losses']} |")
        lines += ["", "| Condition | Trials | Infra errors | Mean cost/trial ($) | Mean output tokens | "
                  "Target skill opened (targeted tasks) | Any skill opened (non-targeted) |",
                  "|---|---|---|---|---|---|---|"]
        for cond in sorted({r["cond"] for r in sub}):
            cr = [r for r in sub if r["cond"] == cond]
            ok = [r for r in cr if r["status"] != "infra_error"]
            cost = [r["cost_usd"] for r in ok if r["cost_usd"] is not None]
            outt = [r["output_tokens"] for r in ok if r["output_tokens"] is not None]
            tgt = [r["target_skill_used"] for r in ok if r["target_skill_used"] != ""]
            non = [r for r in ok if not r["targeted"]]
            cells = [cond, str(len(cr)), str(len(cr) - len(ok)),
                     f"{statistics.mean(cost):.3f}" if cost else "n/a",
                     f"{statistics.mean(outt):.0f}" if outt else "n/a",
                     f"{100 * statistics.mean(tgt):.0f}%" if tgt else "n/a",
                     f"{100 * sum(bool(r['skills_used']) for r in non) / len(non):.0f}%" if non else "n/a"]
            lines.append("| " + " | ".join(cells) + " |")
        lines.append("")
    (OUT / "summary.md").write_text("\n".join(lines))
    print("\n".join(lines))


if __name__ == "__main__":
    main()
