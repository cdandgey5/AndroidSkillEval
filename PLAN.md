# AndroidSkillEval: Do Google's official Android skills improve agent results?

Plan written 2026-10-29. All facts below were checked against primary sources that day (links at the end).

---

## 1. Verdict

**Build it. It's feasible, cheap enough, and the gap is real.** Nobody has published independent with/without numbers. Google's own posts give no pass rates either, only "internal experiments" and "3x faster".

**But the idea as written ("run a subset of Android Bench with and without skills") will most likely give a null result, for the wrong reason.** I downloaded all 100 public Android Bench tasks and checked them against the 36 official skills. **Only 11 of the 100 overlap with any skill, and only 5 overlap strongly.** Most Android Bench tasks are generic bug fixes (Coil, Jerboa, Thunderbird, rich-text editor bugs). The skills target narrow, fast-moving areas (AGP 9, Navigation 3, adaptive layouts, Wear M3, XR). A random subset will show "no difference", and readers will rightly say you tested the wrong tasks.

**Fix: a three-slice design (section 5).**
1. All 100 tasks: does installing every skill help or hurt general Android work? (This is the no-harm test.)
2. The 11 targeted tasks with more trials: do skills help when they're relevant?
3. A "forced skill" condition: is any gap caused by the agent not loading the skill, or by the skill content?

Phase 2 adds ~10 custom tasks built squarely on skill domains, for a second post.

**This works without a Mac.** Android Bench needs x86_64 Linux with KVM, 8 CPU and 32 GB per trial. Rent a cloud VM.

---

## 2. What / Why / How / Risks

| | |
|---|---|
| **What** | An open, reproducible benchmark of Google's `android/skills` on Android Bench 1.0 (100 public tasks) using Harbor, Google's own benchmark harness. You publish the numbers, code and raw results. |
| **Why** | Google released the skills in April 2026 (36 now) and moved Android Bench to Harbor in July 2026. Harbor injects skills with one flag (`--skill`). The tooling exists but no one has published numbers. Every Android dev using Claude Code or Codex is deciding right now whether to run `android skills add --all`. |
| **How** | One rented Linux VM with KVM, the Harbor CLI, about 800 agent trials, and a pre-registered analysis. About 3 weeks part-time to the first post. |
| **Risks** | Null result (mitigated by the slice design), ceiling effects (mitigated by model choice), infra pain (mitigated by a day-1 pilot), cost overrun (mitigated by pilot-based budget caps). Full list in section 10. |

---

## 3. Verified facts (2026-10-29)

**Android Bench**
- **v1.0:** 100 tasks, **public** on Harbor Hub as `android-bench/android-bench`. 88 come from real GitHub PRs and 12 were written by experts. About 71% are Kotlin and 41% use Compose. Verification is by unit and instrumentation tests (fail-to-pass and pass-to-pass), and the reward is binary.
- **v2.0:** 30 long-horizon tasks, **private** (Google withholds them to avoid contamination). **You cannot run v2.** Only v1 is usable.
- **Saturation:** v1 is nearly saturated at the top. Claude Opus 5 scores 91.8%, GPT 5.6 Sol 90.8% and GPT 5.6 Luna 87.6% (mini-swe-agent harness). Mid-tier models still have headroom, for example Gemini 3.5 Flash-Lite at 50.6% and Gemma 4 31b at 37.1%.
- **Hardware per task (from `task.toml`):** 8 CPU, 32 GB RAM, 120 GB storage, and `/dev/kvm` for the emulator. Images are prebuilt at `us-central1-docker.pkg.dev/android-bench-public/...`, so there's no local image build.
- **Timeouts:** agent timeout 20,000 s and verifier timeout 7,200 s per task.
- The old GitHub repo `android-bench/android-bench` was archived on 2026-07-08. Harbor is the supported path now.

**Android skills (`github.com/android/skills`, Apache 2.0)**
- **36 skills at commit `6daa53e` (2026-10-29),** nested by area, for example `build-system/agp/agp-9-upgrade/SKILL.md`.
- **Official install:** `android skills add --all`, or as a plugin in Claude Code and Codex.
- **Google's own evals:** each skill must pass its evals with the skill and fail without it. The evals check that the build passes, plus an LLM diff judge. The eval infra is internal, and **no numbers are published.**
- **Token cost:** Google says each installed skill adds about 100 to 200 tokens to every task's context. Loading a skill can cost thousands of tokens.
- **Selection:** Google only ships a skill where SOTA models show a "verifiable knowledge gap". That's why they're narrow.

**Harbor (`harbor` CLI 0.25.0)**
- Pre-integrated agents include `claude-code`, `codex`, `gemini-cli` and `antigravity-cli`.
- `--skill <dir>` copies skills into the agent's native location: `$CLAUDE_CONFIG_DIR/skills` for Claude Code and `$HOME/.agents/skills` for Codex.
- `--extra-instruction` appends text to the task prompt.
- `--ak disable_web_search=true` turns off web tools for Claude Code and Codex.
- `-k` sets the number of attempts.
- The job lock records each skill's SHA-256, so runs are traceable.
- **Tested here:** `harbor run ... --skill ... --extra-instruction ... --print-config` resolves to the config this plan uses.

**Prior work:** SkillsBench (arXiv 2602.12670) found curated skills add about 18 to 20 points for Claude Code and Codex on general tasks, while self-generated skills hurt. There's nothing Android-specific. **Your post is the first Android-specific independent data.**

---

## 4. Weak spots in the original idea, and fixes

| # | Weak spot | Why it matters | Fix |
|---|---|---|---|
| 1 | "A subset of Android Bench" | 89% of tasks fall outside every skill's domain. A random subset gives a null result that says nothing about the skills. | Run all 100 tasks and report the targeted slice separately (section 5). |
| 2 | Frontier models are at about 90% on v1 | There's little room to improve, so a skill effect gets hidden. | Choose a model whose pilot baseline is 40–75%. |
| 3 | Skills load only if the agent decides to | "Skills didn't help" could just mean "skills never loaded". | Log skill activation from trajectories, and add the forced-skill condition C2. |
| 4 | 11 targeted tasks is a small sample | 95% CIs will be about ±25 pp, so only big effects show. | Use 5 trials per targeted task, state the CI plainly, and add custom tasks in Phase 2. |
| 5 | v1 tasks are public PRs from 2023–2025 | Models may have memorized fixes, which raises the baseline. | Contamination affects both conditions equally, so the delta is still valid. Note it as a limitation. Phase 2 custom tasks are new code. |
| 6 | Web search could leak the same docs | It confounds what the skills add. | Disable web tools in every condition. |
| 7 | The `android-cli` skill assumes the `android` binary exists | Task images don't ship it, so the skill would send the agent down dead ends. | Exclude it (done in `scripts/prepare_skills.sh`) and state that in the post. |
| 8 | Cherry-picking after seeing results | Kills credibility on LinkedIn. | Pre-register: commit `PREREGISTRATION.md` before any real run. The git timestamp is your proof. |

---

## 5. Research design

### Questions
- **Q1:** Does installing all official skills change the pass rate on general Android tasks? This is the help-or-harm question.
- **Q2:** On tasks inside a skill's domain, do skills raise the pass rate?
- **Q3:** When a relevant skill is present, how often does the agent actually load it? Does forcing it close the gap?
- **Q4:** What do skills cost in tokens, dollars and time?

### Conditions

| ID | Setup | Harbor flags |
|---|---|---|
| **C0** | Baseline, no skills | none |
| **C1** | All 35 official skills (minus `android-cli`), auto-triggered. This is the realistic `android skills add --all` setup. | `--skill skills/all` |
| **C2** | Only the matching skill, plus "read the `<skill>` skill and follow it". Targeted tasks only. This is the upper bound. | `--skill skills/single/<s> --extra-instruction ...` |

In every condition: same agent version, model and effort, web tools off, the same Android Bench timeouts, and condition order shuffled per task.

There's no separate placebo arm. C1 on the 89 non-targeted tasks *is* the placebo, because skills are present but irrelevant. That measures distraction cost for free.

### Tasks
- **Core:** all 100 Android Bench 1.0 tasks, k=3 trials per condition (C0, C1).
- **Targeted (`config/targeted_tasks.json`):** 11 tasks hand-checked against each skill's `SKILL.md`, k=5 per condition (C0, C1, C2).

| Tier | Task | Skill |
|---|---|---|
| 1 | `android__nowinandroid-pr_553` | adaptive |
| 1 | `nowinandroid-adaptive-1` | adaptive |
| 1 | `cahier-adaptive-1` | adaptive |
| 1 | `coil-kt__coil-pr_1964` | jetpack-compose-performance |
| 1 | `lemmynet__jerboa-pr_941` | navigation-event |
| 2 | `thunderbird__thunderbird-android-pr_7103` | navigation-event |
| 2 | `automattic__pocket-casts-android-pr_757` | android-permissions-security |
| 2 | `getsentry__sentry-java-pr_4724` | anr-audit-and-fix |
| 2 | `chrisbanes__haze-pr_250` | agp-9-upgrade |
| 2 | `android_snippets_1` | agp-9-upgrade |
| 2 | `android_androidify_gradleplugin` | agp-9-upgrade |

This list is frozen before any run. Don't edit it after seeing results.

### Agents and models
- **Post 1 (primary):** `claude-code` with a mid-tier Claude model, starting with Claude Haiku 5.5. Claude Code is the most-used coding agent, and Google ships an official Claude Code plugin for these skills.
- **Post 2:** `codex` with a cheap GPT model (GPT 6 Luna costs $5.30 for the whole v2 leaderboard run), plus `gemini-cli` with Gemini Flash. Google tunes its skills on Gemini Flash, so this tests whether they transfer to other agents.
- **Model selection rule (pre-registered):** in the pilot, run C0 on 10 random tasks. Use the model if its baseline is between 40% and 75%. If it's above 75%, step down a tier. If it's below 40%, step up.

### Metrics
- **Primary:** task resolve rate, where the Android Bench reward is 1 if all fail-to-pass and pass-to-pass tests pass.
- **Secondary:**
  - Activation rate: did the agent open the target skill, based on ATIF tool calls?
  - Cost in USD, input and output tokens, and wall time per trial.
  - Infra-error rate, reported and excluded.

### Statistics
- The unit is the task. Each task's score is the mean reward over its k trials.
- The effect is the paired delta, C1 minus C0, over shared tasks, in percentage points.
- **95% CI:** paired bootstrap over tasks with 10,000 resamples. Also report win/loss counts.
- **Rough power:** with 100 tasks, the CI is about ±6 pp. With 11 tasks, it's about ±25 pp. Say this in the post. Don't oversell the targeted slice.
- Infra errors, where the agent never started, are excluded and retried. Agent timeouts and crashes count as failures.
- `scripts/analyze.py` already implements all of this and is tested on synthetic Harbor output.

---

## 6. Infrastructure and budget

### Recommended: a GCP spot VM in `us-central1`
The task images live in `us-central1` Artifact Registry. A VM in the same region pulls them fastest. Toronto is closer to Brampton, but proximity doesn't matter for a batch job.

```bash
# New GCP accounts get $300 credit, but free-trial accounts cap at 8 vCPUs.
# Upgrade to a paid account (you keep the credit) before creating this VM.
gcloud compute instances create android-bench \
  --zone=us-central1-a \
  --machine-type=n2-standard-32 \
  --enable-nested-virtualization \
  --provisioning-model=SPOT --instance-termination-action=STOP \
  --boot-disk-size=750GB --boot-disk-type=pd-balanced \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud

# On the VM:
sudo apt-get update && sudo apt-get install -y docker.io git python3 cpu-checker
sudo usermod -aG docker,kvm $USER && newgrp docker
kvm-ok                                   # must say "KVM acceleration can be used"
curl -LsSf https://astral.sh/uv/install.sh | sh && uv tool install harbor
git clone https://github.com/cdandgey5/AndroidSkillEval && cd AndroidSkillEval
export ANTHROPIC_API_KEY=...             # and/or OPENAI_API_KEY, GEMINI_API_KEY
harbor run -d android-bench/android-bench -i "*airbnb__lottie-android-pr_2427" -a oracle   # infra check
```

- **Spec:** n2-standard-32 has 32 vCPU and 128 GB, which fits 3 concurrent trials at 8 CPU / 32 GB each with headroom for the host. That's why `N_CONCURRENT` defaults to 3 to match k=3.
- **Spot preemption** is handled. Every (agent, condition, task) is its own Harbor job, and `run_matrix.sh` skips finished jobs, so you can just re-run it.
- **Images:** the script runs all conditions for a task back to back, then deletes that image. Each image is pulled once, and the disk never fills.
- **Alternative:** a Hetzner or OVH bare-metal box with 16+ cores and 128 GB, which is cheaper by the month. Only worth it if you'll keep running evals after Phase 2.
- **Check first:** whether `harbor run --launch` (Harbor Hub hosted runs) supports this dataset and what it costs. If it does, you can skip the VM entirely.

### Budget for Post 1 (one agent config)

| Item | Count | Estimate |
|---|---|---|
| Oracle check (all 100 tasks, k=1) | 100 trials | compute only |
| Core: 100 tasks × C0/C1 × k=3 | 600 trials | |
| Targeted: 11 tasks × C0/C1/C2 × k=5 | 165 trials | |
| **Total** | **~865 trials** | |
| VM compute (~6–7 days at about 35 min per 3-trial job) | ~160 h | ~$60–90 spot, ~$250 on-demand |
| Disk (750 GB pd-balanced, ~2 weeks) | | ~$35 |
| API (unknown until the pilot; Claude Code with a Haiku-class model at $0.20–0.80/trial) | ~765 agent trials | ~$150–600 |
| **Total** | | **~$250–700** |

**Set hard spend caps** in the Anthropic, OpenAI and Google consoles before the core run. Re-estimate from pilot numbers. If API cost per trial comes in above $0.80, cut the core to k=2, which saves a third.

---

## 7. Execution plan

Each phase has an exit gate. Don't start the next phase until it passes.

### Phase 0: Setup and pre-registration (days 1–2)
- [ ] Commit `PREREGISTRATION.md` and `config/targeted_tasks.json` **before** any agent run.
- [ ] Create the VM (section 6), confirm `kvm-ok`, and install Harbor.
- [ ] `scripts/prepare_skills.sh` flattens 35 skills into `skills/all` and writes `config/SKILLS_LOCK.md`.
- [ ] Oracle run on all 100 tasks at k=1: `harbor run -d android-bench/android-bench -a oracle -n 3`. Drop any task where the oracle fails on your infra, and list the dropped tasks in the post.
- **Gate:** at least 95 tasks pass the oracle.

### Phase 1: Pilot (days 3–4)
- [ ] Confirm the exact model ids with your provider.
- [ ] `AGENT_CONFIGS="claude-code|anthropic/<model>|medium" scripts/run_matrix.sh pilot` (5 tasks, C0 and C1, k=1).
- [ ] `python3 scripts/analyze.py` and check:
  - cost per trial
  - minutes per job
  - that skills appear in `$CLAUDE_CONFIG_DIR/skills` (from the trial logs)
  - that the activation detector fires on at least one trial
- [ ] Run C0 on 10 random tasks and apply the model selection rule.
- **Gate:** the model is in the 40–75% band, the cost estimate fits the budget, and activation detection works.

### Phase 2: Core and targeted runs (days 5–12, mostly unattended)
- [ ] `scripts/run_matrix.sh core`, then `scripts/run_matrix.sh targeted`. Run them in `tmux`.
- [ ] Each day, re-run the script to resume after any preemption, then check `analyze.py` output for infra-error spikes.
- **Gate:** at least 95% of planned trials have a verifier result.

### Phase 3: Analysis and write-up (days 13–18)
- [ ] `analyze.py` produces `results/summary.md` and `results/trials.csv`. Commit both.
- [ ] Make 3 charts:
  1. Paired delta with CI per slice (all, tier 1, tier 1+2, non-targeted).
  2. Activation rate, C1 vs C2.
  3. Cost and tokens per trial by condition.
- [ ] Read 6 trajectories by hand: 2 where skills helped, 2 where they hurt, and 2 where the skill was present but not opened. Quote them in the post.
- [ ] Upload the jobs to Harbor Hub (`harbor run ... --upload`, or upload the jobs dir) so anyone can inspect the trials.

### Phase 4: Publish post 1 (days 19–21)
See section 9.

### Phase 5 (optional, weeks 4–7): Custom skill-targeted tasks, then post 2
Build about 10 Harbor tasks, one per high-value skill, using Google's own eval pattern: a small real app, a precise prompt, and deterministic checks. Verify with the build passing, hidden unit/UI tests, and grep or lint rules. Avoid LLM judges.

| Skill | Task idea | Deterministic check |
|---|---|---|
| agp-9-upgrade | Upgrade a sample from AGP 8.x to 9 | `assembleDebug` passes; no `org.jetbrains.kotlin.android` plugin left |
| navigation-3 | Migrate a 3-screen Nav2 app to Nav3 | Build passes; `NavDisplay` used; hidden UI test navigates all screens |
| migrate-xml-views-to-jetpack-compose | Convert one XML screen to Compose | Build passes; hidden Compose test finds the same nodes |
| edge-to-edge | Make a targetSdk 35 app edge-to-edge-correct | Hidden screenshot or bounds test: content not under bars |
| r8-analyzer | Tighten over-broad keep rules | Release build passes; APK size under a threshold; app test passes |
| wear-compose-m3 | Google's own pager example | `HorizontalPagerScaffold` + `AnimatedPage` + build passes |
| play-billing-library-version-upgrade | Move PBL 6 to the current version | Build passes; no removed APIs remain |
| camerax | Replace Camera1 code | Build passes; no `android.hardware.Camera` imports |
| navigation-event | Add predictive back to a custom screen | Hidden instrumentation test for back handling |
| testing-setup | Add Compose UI test infra | The given test file compiles and runs |

Run C0, C1 and C2 with 2 agents (Claude Code and Codex or Gemini), k=5. This is where a real effect is most likely, and it becomes a second post ("Part 2: when the task is in the skill's domain").

---

## 8. Repo layout

```
AndroidSkillEval/
├── PLAN.md                     # this file
├── PREREGISTRATION.md          # hypotheses + analysis, committed before runs
├── README.md                   # how to reproduce in 5 commands
├── config/
│   ├── targeted_tasks.json     # frozen 11-task targeted slice
│   └── SKILLS_LOCK.md          # generated: skill names, sizes, hashes
├── scripts/
│   ├── prepare_skills.sh       # pin + flatten android/skills
│   ├── run_matrix.sh           # pilot | core | targeted (idempotent)
│   └── analyze.py              # trials.csv + summary.md with bootstrap CIs
├── results/                    # committed summaries (not raw jobs)
├── report/                     # charts + blog post draft
├── jobs/                       # gitignored raw Harbor output
└── skills/                     # gitignored, generated
```

---

## 9. Publication plan

### Blog post (personal site, dev.to or Medium; also as a LinkedIn article)
**Title:** "I ran Google's official Android skills through Android Bench. Here's what they actually change."

1. **TL;DR:** 3 numbers. The all-task delta, the targeted delta, and the activation rate.
2. **Why this matters:** skills shipped in April with no public numbers, and every dev is deciding whether to install them.
3. **Setup:** Harbor, Android Bench 1.0, conditions C0/C1/C2, models, k, web off, pre-registration link.
4. **Result 1, general tasks:** help or harm, plus token cost.
5. **Result 2, targeted tasks:** the effect, with its honest CI.
6. **Result 3, activation:** how often agents ignore a relevant skill, and what forcing it does.
7. **Two trajectory excerpts:** one win, one miss.
8. **Practical advice:** for example "install only the skills for your stack" or "mention the skill in your prompt". Base this on your data, not assumptions.
9. **Limitations:** the v1 slice is small, contamination, one agent, skills at commit `6daa53e`.
10. **Reproduce it:** the repo, 5 commands, and the Harbor Hub job link.

### LinkedIn post (about 150 words, chart image attached)
- **Hook:** the single most surprising number.
- **Context:** 3 lines on Google skills, Android Bench and the fact that no independent data existed.
- **Findings:** 3 bullets.
- **Close:** one line on what you'd tell an Android team, the repo link, and the post link.
- Post Tuesday to Thursday, 8–10 am ET.
- Reply to every comment in the first 2 hours.
- Tag the work's topics (#AndroidDev, #AIagents), not people, unless they engage.

### Credibility multipliers (cheap and high-value)
- The pre-registration commit, dated before the runs.
- Public raw `trials.csv` plus the Harbor Hub upload.
- A friendly heads-up to Android DevRel before posting, through the `android/skills` issues or the Android Bench community repo. Offer the data; don't ask for endorsement.
- File any skill bugs you find (for example, skills that never trigger) as issues on `android/skills`, and link them in the post.

---

## 10. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| KVM or emulator fails on the VM | Medium | Blocks everything | Day-1 oracle run on one task. N2 with `--enable-nested-virtualization` is supported. Fall back to bare metal. |
| Oracle fails on some tasks | Medium | Smaller dataset | Drop and report them (gate: at least 95 tasks). |
| Ceiling effect | High with frontier models | Hides the effect | Model selection rule in the pilot. |
| Null result overall | High on all tasks | "Boring" post | Expected and pre-registered. The targeted slice, activation and cost data still make it useful. Phase 5 custom tasks. |
| API cost overrun | Medium | Money | Pilot-based estimate, console spend caps, k=2 fallback. |
| Spot preemption | Medium | Lost hours | Idempotent per-job design; re-run the script. |
| Skills repo changes mid-run | High (updated weekly) | Mixed versions | Pinned SHA plus `SKILLS_LOCK.md`. |
| Someone else publishes first | Medium | Less novelty | Aim for post 1 by about 2026-11-19. Your pre-registration and full reproducibility still set you apart. |
| Agent version changes mid-run | Medium | Confound | Pin versions with `--ak version=<x>` once the pilot shows which version installed; condition order is shuffled per task. |
| Harbor `utils/agent` volume path missing locally | Low | Task won't start | The oracle run catches it. Use `harbor download` into the cache and run with `-d`, not `-p`. |

---

## 11. Next actions (today)

1. **Read `PREREGISTRATION.md`,** change anything you disagree with, and commit it. This is the timestamp that matters.
2. **Create a GCP account and upgrade it to paid** (you keep the $300 credit). Then run the `gcloud` command in section 6.
3. **On the VM, run the oracle check on one task.** If it passes, the hardest risk is gone.
4. Add API keys, set spend caps, and run `scripts/run_matrix.sh pilot`.

---

## Sources
- [Android Bench leaderboard](https://developer.android.com/bench) and [methodology v2](https://developer.android.com/bench/methodology/2)
- [Android Bench 2.0 announcement](https://developer.android.com/blog/posts/android-bench-2-0-pushing-the-frontier-with-challenging-long-horizon-tasks)
- [Android Bench 1.0 announcement](https://developer.android.com/blog/posts/elevating-ai-assisted-android-development-and-improving-ll-ms-with-android-bench)
- [Android Bench 1.0 dataset on Harbor Hub](https://hub.harborframework.com/datasets/android-bench/android-bench/latest)
- [android/skills repo](https://github.com/android/skills) and [Android skills docs](https://developer.android.com/tools/agents/android-skills)
- [Android CLI and skills launch post (Apr 2026)](https://android-developers.googleblog.com/2026/04/build-android-apps-3x-faster-using-any-agent.html)
- [Inside Android Skills: Built for deprecation (Aug 2026)](https://developer.android.com/blog/posts/inside-android-skills-built-for-deprecation)
- [Device Streaming and Android skills (Oct 2026)](https://android-developers.googleblog.com/2026/10/android-cli-device-streaming-and-skills.html)
- [Harbor docs: skills](https://docs.harborframework.com/jobs/skills), [agents](https://docs.harborframework.com/agents/pre-integrated-agents), [run a job](https://docs.harborframework.com/jobs/run-a-job)
- [SkillsBench (arXiv 2602.12670)](https://arxiv.org/abs/2602.12670)
