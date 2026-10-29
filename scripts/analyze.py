#!/usr/bin/env python3
"""Summarize Harbor jobs written by run_matrix.sh.

Writes results/trials.csv (one row per trial) and results/summary.md (paired
comparisons with bootstrap CIs). The unit of analysis is the task: each task's
score is the mean reward over its trials, and conditions are compared on the
same tasks only. Tasks whose oracle failed are dropped.

Usage: python3 scripts/analyze.py [jobs_dir]   (default: jobs/main)
"""

import csv
import json
import random
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JOBS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "jobs/main"
ORACLE_JOBS = ROOT / "jobs/oracle"
OUT = ROOT / "results"
CFG = json.loads((ROOT / "config/targeted_tasks.json").read_text())
TARGETED = {t["task"]: t for t in CFG["tasks"]}
HARM_WATCH = set(CFG["harm_watch"]["tasks"])
NON_INFERIORITY_PP = -10.0  # pre-registered margin for H2
N_BOOT = 10_000


def skill_names():
    if (ROOT / "skills/all").exists():
        return {p.name for p in (ROOT / "skills/all").iterdir() if p.is_dir()}
    lock = (ROOT / "config/SKILLS_LOCK.md").read_text()
    return set(re.findall(r"^\| ([a-z0-9-]+) \| \d+ \|", lock, re.M))


SKILLS = skill_names()
SKILL_PATH = re.compile(r"skills/([a-z0-9-]+)(?:/|\\?\"|$)")


def read_trajectory(trial_dir):
    """(skills opened, number of doc lookups) from the ATIF trajectory, or (None, None).

    Only tool calls count, so skill names listed in the system prompt don't.
    A skill is opened by a Skill tool call naming it or by any tool call
    touching skills/<name>/. A doc lookup is a web tool call or a tool call
    mentioning developer.android.com (agents can still curl it from a shell).
    """
    path = trial_dir / "agent" / "trajectory.json"
    if not path.exists():
        return None, None
    used, lookups = set(), 0
    for step in json.loads(path.read_text()).get("steps", []):
        for call in step.get("tool_calls") or []:
            fn, args = call.get("function_name") or "", call.get("arguments") or {}
            blob = json.dumps(args)
            if fn == "Skill":
                used |= {str(v).split(":")[-1] for v in args.values()} & SKILLS
            used |= set(SKILL_PATH.findall(blob)) & SKILLS
            if fn in ("WebFetch", "WebSearch") or "developer.android.com" in blob:
                lookups += 1
    return used, lookups


def parse_job(name):
    parts = name.split("__")
    if len(parts) < 5:
        return None
    return dict(agent=parts[0], model=parts[1], cond=parts[2], task="__".join(parts[3:-1]))


def trial_results(job_dir):
    for trial in sorted(p for p in job_dir.iterdir() if p.is_dir() and (p / "result.json").exists()):
        yield trial, json.loads((trial / "result.json").read_text())


def reward_of(r):
    return ((r.get("verifier_result") or {}).get("rewards") or {}).get("reward")


def oracle_status():
    """task -> True if the reference solution passed; False if it failed or the image didn't build."""
    status = {}
    if ORACLE_JOBS.exists():
        for marker in ORACLE_JOBS.glob("build_failed__*"):
            status[marker.name.removeprefix("build_failed__")] = False
        for job in ORACLE_JOBS.iterdir():
            meta = parse_job(job.name) if job.is_dir() else None
            if meta:
                status[meta["task"]] = any(reward_of(r) == 1 for _, r in trial_results(job))
    return status


def load_trials():
    rows = []
    for job in sorted(p for p in JOBS.iterdir() if p.is_dir()):
        meta = parse_job(job.name)
        if not meta:
            continue
        task = meta["task"]
        for trial, r in trial_results(job):
            ctx = r.get("agent_result") or {}
            exc = (r.get("exception_info") or {}).get("exception_type")
            reward = reward_of(r)
            # Harbor still runs the verifier after agent timeouts and crashes, so a
            # missing reward means the environment or verifier failed: exclude it.
            status = "no_reward" if reward is None else ("ok" if exc is None else f"agent_error:{exc}")
            used, lookups = read_trajectory(trial)
            rows.append(dict(
                **meta, trial=trial.name, status=status,
                reward=None if reward is None else float(reward),
                targeted=task in TARGETED, tier=TARGETED.get(task, {}).get("tier", ""),
                harm_watch=task in HARM_WATCH,
                target_skill=TARGETED.get(task, {}).get("skill", ""),
                skills_opened=";".join(sorted(used or ())),
                target_skill_opened="" if used is None or task not in TARGETED or meta["cond"] == "C0"
                else int(TARGETED[task]["skill"] in used),
                doc_lookups=lookups,
                input_tokens=ctx.get("n_input_tokens"), cache_tokens=ctx.get("n_cache_tokens"),
                output_tokens=ctx.get("n_output_tokens"), cost_usd=ctx.get("cost_usd"),
                task_checksum=r.get("task_checksum"),
            ))
    return rows


def per_task(rows, key="reward"):
    by = defaultdict(list)
    for r in rows:
        if r["status"] != "no_reward" and r[key] not in (None, ""):
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
                delta=100 * statistics.mean(d), lo=100 * boots[int(0.025 * N_BOOT)],
                hi=100 * boots[int(0.975 * N_BOOT)], wins=sum(x > 0 for x in d), losses=sum(x < 0 for x in d))


def mean_or_na(values, fmt):
    values = [v for v in values if v not in (None, "")]
    return fmt.format(statistics.mean(values)) if values else "n/a"


def main():
    oracle = oracle_status()
    dropped = sorted(t for t, ok in oracle.items() if not ok)
    rows = [r for r in load_trials() if r["task"] not in dropped]
    if not rows:
        sys.exit(f"no trials found under {JOBS}")
    OUT.mkdir(exist_ok=True)
    with open(OUT / "trials.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    checksums = defaultdict(set)
    for r in rows:
        checksums[r["task"]].add(r["task_checksum"])
    changed = sorted(t for t, c in checksums.items() if len(c) > 1)
    no_oracle = sorted({r["task"] for r in rows} - set(oracle))

    rng = random.Random(0)
    slices = {
        "All tasks": lambda t: True,
        "Targeted, tier 1": lambda t: TARGETED.get(t, {}).get("tier") == 1,
        "Targeted, all": lambda t: t in TARGETED,
        "Not targeted": lambda t: t not in TARGETED,
        "Harm watch (descriptive)": lambda t: t in HARM_WATCH,
    }
    comparisons = [("C0", "C1", "No skills → all skills", list(slices)),
                   ("C0", "C2", "No skills → forced skill", ["Targeted, tier 1", "Targeted, all"]),
                   ("C1", "C2", "All skills → forced skill", ["Targeted, tier 1", "Targeted, all"])]

    lines = ["# Results", "",
             "Score = mean reward per task over its trials. Delta in percentage points (pp), "
             "95% paired bootstrap CI over tasks. W/L = tasks where the second condition scored higher/lower.", "",
             f"- Tasks dropped (image build or oracle failed): {', '.join(dropped) or 'none'}",
             f"- Tasks with no oracle run (check these): {', '.join(no_oracle) or 'none'}",
             f"- Tasks whose checksum changed mid-study: {', '.join(changed) or 'none'}", ""]
    for agent, model in sorted({(r["agent"], r["model"]) for r in rows}):
        sub = [r for r in rows if r["agent"] == agent and r["model"] == model]
        by_cond = {c: per_task([r for r in sub if r["cond"] == c]) for c in ("C0", "C1", "C2")}
        lines += [f"## {agent} + {model}", "",
                  "| Comparison | Slice | Tasks | Before | After | Delta (pp) | 95% CI | W/L |",
                  "|---|---|---|---|---|---|---|---|"]
        h2 = None
        for c_a, c_b, label, names in comparisons:
            for sname in names:
                keep = slices[sname]
                res = paired({t: v for t, v in by_cond[c_a].items() if keep(t)},
                             {t: v for t, v in by_cond[c_b].items() if keep(t)}, rng)
                if not res:
                    continue
                if (c_a, c_b, sname) == ("C0", "C1", "Not targeted"):
                    h2 = res
                lines.append(f"| {label} | {sname} | {res['n']} | {100 * res['a']:.1f}% | {100 * res['b']:.1f}% | "
                             f"{res['delta']:+.1f} | [{res['lo']:+.1f}, {res['hi']:+.1f}] | {res['wins']}/{res['losses']} |")
        if h2:
            verdict = "met" if h2["lo"] > NON_INFERIORITY_PP else "not met"
            lines += ["", f"H2 non-inferiority (CI lower bound > {NON_INFERIORITY_PP:+.0f} pp): **{verdict}** "
                      f"(lower bound {h2['lo']:+.1f} pp)."]

        lines += ["", "| Condition | Trials | No reward (excluded) | Cost/trial ($) | Input tokens | Output tokens | "
                  "Trials with doc lookups | Target skill opened (targeted) | Any skill opened (not targeted) |",
                  "|---|---|---|---|---|---|---|---|---|"]
        for cond in sorted({r["cond"] for r in sub}):
            cr = [r for r in sub if r["cond"] == cond]
            ok = [r for r in cr if r["status"] != "no_reward"]
            non = [r for r in ok if not r["targeted"]]
            lines.append("| " + " | ".join([
                cond, str(len(cr)), str(len(cr) - len(ok)),
                mean_or_na([r["cost_usd"] for r in ok], "{:.3f}"),
                mean_or_na([r["input_tokens"] for r in ok], "{:.0f}"),
                mean_or_na([r["output_tokens"] for r in ok], "{:.0f}"),
                f"{100 * sum(bool(r['doc_lookups']) for r in ok) / len(ok):.0f}%" if ok else "n/a",
                mean_or_na([100 * r["target_skill_opened"] for r in ok if r["target_skill_opened"] != ""], "{:.0f}%"),
                "n/a" if cond == "C0" or not non else f"{100 * sum(bool(r['skills_opened']) for r in non) / len(non):.0f}%",
            ]) + " |")

        opened = Counter((s, r["targeted"]) for r in sub if r["cond"] == "C1" for s in filter(None, r["skills_opened"].split(";")))
        if opened:
            lines += ["", "Skills opened in C1 (trials):", "", "| Skill | On targeted tasks | On other tasks |", "|---|---|---|"]
            for s in sorted({s for s, _ in opened}, key=lambda s: -(opened[(s, True)] + opened[(s, False)])):
                lines.append(f"| {s} | {opened[(s, True)]} | {opened[(s, False)]} |")
        lines.append("")
    (OUT / "summary.md").write_text("\n".join(lines))
    print("\n".join(lines))


if __name__ == "__main__":
    main()
