# AndroidSkillEval: Do Google's official Android skills improve agent results?

Plan written 2026-10-29 and rechecked twice the same day (see the revision log at the end). Facts were checked against primary sources, and Harbor behavior was checked against its source code (`harbor` 0.25.0).

---

## 1. Verdict

**Build it. It's feasible, it costs a few hundred dollars, and the gap is real.** Nobody has published independent with/without numbers. Google's own posts give no pass rates, only "internal experiments" and "3x faster".

**But the idea as written ("run a subset of Android Bench with and without skills") will most likely give a null result, for the wrong reason.** I checked all 100 public Android Bench tasks against the 36 official skills: their problem text, their solution patches, and each skill's `SKILL.md`. **Only 9 of the 100 tasks fall inside a skill's scope, and only 6 strongly.** Most tasks are generic bug fixes (Coil, Jerboa, Thunderbird, rich-text editor bugs). The skills target narrow, fast-moving areas (AGP 9, Navigation 3, adaptive layouts, Wear M3, XR). A random subset will show "no difference", and readers will rightly say you tested the wrong tasks.

**Fix: a three-question design (section 5).**
1. All 100 tasks: does installing every skill help or hurt general Android work? (The no-harm test.)
2. The 9 targeted tasks, with more trials: do skills help when they're relevant?
3. A "forced skill" condition: is any gap caused by the agent not loading the skill, or by the skill content?

**Be clear about what post 1 can prove.** With 9 targeted tasks, the 95% CI is about ±20–30 percentage points (pp). Post 1 can firmly answer questions 1 and 3, plus cost. Question 2 will only be directional. Phase 5 (about 10 custom skill-domain tasks) is what answers question 2 properly, so plan for a part 2.

**You can run it on your own PC (no Google Cloud needed),** if the PC is x86_64 Linux or Windows 11 with KVM, has 32 GB+ RAM and about 300 GB free disk. Macs can't run it, so use a cloud VM instead (section 6).

**Current blocker:** Google's public registry for the task images rejects all pulls (their project's billing is off). The scripts work around it by building each image locally from Google's archived builder (section 6.0).

---

## 2. What / Why / How / Risks

| | |
|---|---|
| **What** | An open, pre-registered, reproducible benchmark of Google's `android/skills` on Android Bench 1.0 (100 public tasks) using Harbor, the harness Google now runs Android Bench on. You publish the numbers, code and raw results. |
| **Why** | Google released the skills in April 2026 (36 now) and moved Android Bench to Harbor in July 2026. Harbor injects skills with one flag, but nobody has published numbers. Every Android dev using Claude Code or Codex is deciding right now whether to run `android skills add --all`. |
| **How** | Your own Linux or Windows 11 PC with KVM (or a rented VM), the Harbor CLI, about 700 agent trials plus 100 oracle trials, and a pre-registered analysis. About 3 weeks part-time to the first post. |
| **Risks** | Null result (mitigated by the slice design), ceiling effects (model choice), infra pain (day-1 oracle check), cost overrun (pilot-based caps), small targeted slice (honest CIs plus part 2). Full list in section 10. |

---

## 3. Verified facts (2026-10-29)

**Android Bench**
- **v1.0:** 100 tasks, **public** on Harbor Hub as `android-bench/android-bench`.
  - 88 come from real GitHub PRs and 12 were written by experts. About 71% are Kotlin and 41% use Compose.
  - Verification is by unit and instrumentation tests (fail-to-pass plus pass-to-pass). `test.sh` runs with partial scoring disabled, so the reward is pass/fail.
- **v2.0:** 30 long-horizon tasks, **private** (withheld to avoid contamination). **You can't run v2.** Only v1 is usable.
- **v1 is nearly saturated at the top** (Google's own benchmark agent): Claude Opus 5 scores 91.8%, GPT 5.6 Sol 90.8% and GPT 5.6 Luna 87.6%. Mid-tier models still have headroom, for example Gemini 3.5 Flash-Lite at 50.6% and Gemma 4 31b at 37.1%.
- **Every task's `task.toml` (all 100 identical):**
  - 8 CPU, 32 GB RAM, 120 GB storage, and `/dev/kvm` (emulator API 31–36)
  - agent timeout **20,000 s (5.5 h)** and verifier timeout 7,200 s
  - prebuilt image at `us-central1-docker.pkg.dev/android-bench-public/...`. **As of 2026-10-29 that registry rejects all pulls** (section 6.0). Every image can be rebuilt from the archived repo's builder.
- The old GitHub repo `android-bench/android-bench` was archived on 2026-07-08. Harbor is the supported path.

**Android skills (`github.com/android/skills`, Apache 2.0)**
- **36 skills at commit `6daa53e` (2026-10-29),** nested by area, for example `build-system/agp/agp-9-upgrade/SKILL.md`.
- **Official install:** `android skills add --all`, or as a plugin in Claude Code and Codex.
- **Google's own evals:** each skill must pass its evals with the skill and fail without it. The evals check that the build passes, plus an LLM diff judge. The eval infra is internal, and **no numbers are published.**
- **Token cost:** each installed skill adds about 100–200 tokens to every task's context, per Google. Loading a skill can cost thousands.
- **Watch-out found while checking:** `agp-9-upgrade` says "do not use for KMP", and tells the agent to **stop and ask the user** if AGP is below 9. In a headless benchmark that could cause failures. That's why section 5 has a "harm watch" slice.

**Harbor (`harbor` CLI 0.25.0, checked in source)**
- `--skill <dir>` copies skills into the agent's native location: `$CLAUDE_CONFIG_DIR/skills` for Claude Code and `$HOME/.agents/skills` for Codex. A dir can be one skill or a root of skills.
- Other flags this plan uses:
  - `--extra-instruction` appends text to the prompt.
  - `--ak disable_web_search=true` removes WebSearch/WebFetch for Claude Code and Codex.
  - `--ak version=<x>` pins the agent version.
  - `--agent-timeout-multiplier` scales the agent timeout.
- **A job's `result.json` is written when the job *starts*.** It's complete only when `finished_at` is set. The run script checks for that.
- After an agent timeout or crash, Harbor still runs the verifier. So a missing reward means an environment or verifier failure, not an agent failure.
- Each trial records a `task_checksum`, and the job lock records skill SHA-256s. Runs are traceable.
- Harbor calls `docker compose`, so the Compose plugin must be installed.

**Prior work:** SkillsBench (arXiv 2602.12670) found curated skills add about 18–20 points for Claude Code and Codex on general tasks, while self-generated skills hurt. There's nothing Android-specific. **Your post is the first Android-specific independent data.**

---

## 4. Weak spots in the original idea, and fixes

| # | Weak spot | Why it matters | Fix |
|---|---|---|---|
| 1 | "A subset of Android Bench" | 91% of tasks fall outside every skill's scope. A random subset gives a null result that says nothing about the skills. | Run all 100 tasks and report the targeted slice separately. |
| 2 | Frontier models are at about 90% on v1 | There's no room left for skills to show a gain. | Choose a model whose pilot baseline is 40–75%. |
| 3 | Skills load only if the agent decides to | "Skills didn't help" could just mean "skills never loaded". | Log skill opens from trajectories, and add the forced-skill condition C2. |
| 4 | 9 targeted tasks is a small sample | The 95% CI is about ±20–30 pp, so only big effects show. | k=5 on targeted tasks, honest CIs, and part 2 with custom tasks. |
| 5 | v1 tasks are public PRs from 2023–2025 | Models may have memorized fixes, which raises the baseline. | Contamination affects both conditions equally, so the delta is still valid. Note it as a limitation. Part 2 uses new code. |
| 6 | Web search could leak the same docs | It confounds what the skills add. | Turn off web tools everywhere, and count `developer.android.com` fetches from the shell in every condition. |
| 7 | The `android-cli` skill assumes the `android` binary exists | Task images don't ship it, so the skill would send the agent down dead ends. | Exclude it (done in `scripts/prepare_skills.sh`) and state that in the post. |
| 8 | A skill can actively mislead | `agp-9-upgrade` says to stop and ask when AGP is below 9. | Use the "harm watch" slice of 6 build/toolchain tasks, reported descriptively. |
| 9 | Cherry-picking after seeing results | Kills credibility on LinkedIn. | `PREREGISTRATION.md` and the task list are committed before any run. The git timestamp is your proof. |

---

## 5. Research design

### Questions
- **Q1:** Does installing all official skills change the pass rate on general Android tasks? This is the help-or-harm question.
- **Q2:** On tasks inside a skill's scope, do skills raise the pass rate?
- **Q3:** When a relevant skill is present, how often does the agent actually open it? Does forcing it change the result?
- **Q4:** What do skills cost in tokens, dollars and time?

### Conditions

| ID | Setup | Harbor flags |
|---|---|---|
| **C0** | Baseline, no skills | none |
| **C1** | All 35 official skills (minus `android-cli`), auto-triggered. This is the realistic `android skills add --all` setup. | `--skill skills/all` |
| **C2** | Only the matching skill, plus "Before you start, read the `<skill>` skill and follow it". Targeted tasks only. This is the upper bound. | `--skill skills/all/<s> --extra-instruction ...` |

In every condition: same agent version, model and effort, web tools off, the same timeouts, and condition order shuffled per task.

There's no separate placebo arm. C1 on the 91 non-targeted tasks is the placebo, because skills are present but irrelevant. That measures distraction cost for free.

### Tasks
- **Oracle first, on every task:** Harbor runs Google's reference solution. If it fails on your machine, the task is dropped before any agent trial, which saves API money. Dropped tasks are listed in the results.
- **Non-targeted (91 tasks):** k=3 per condition (C0, C1).
- **Targeted (`config/targeted_tasks.json`, 9 tasks):** k=5 per condition (C0, C1, C2).

| Tier | Task | Skill | Evidence in the solution patch |
|---|---|---|---|
| 1 | `android__nowinandroid-pr_553` | adaptive | window size class decides bottom bar vs rail |
| 1 | `nowinandroid-adaptive-1` | adaptive | `NavigationSuite` |
| 1 | `cahier-adaptive-1` | adaptive | `rememberSaveable` for config changes |
| 1 | `coil-kt__coil-pr_1964` | jetpack-compose-performance | `@Stable` to stop recompositions |
| 1 | `nowinandroid-custom-modifier-node` | jetpack-compose-performance | custom `Modifier.Node` (skill ships a custom-modifiers reference) |
| 1 | `lemmynet__jerboa-pr_941` | navigation-event | `BackHandler` closes the drawer |
| 2 | `automattic__pocket-casts-android-pr_757` | android-permissions-security | `POST_NOTIFICATIONS` runtime request |
| 2 | `getsentry__sentry-java-pr_4724` | anr-audit-and-fix | main-thread disk reads (StrictMode) |
| 2 | `lemmynet__jerboa-pr_991` | navigation-event | `BackHandler` inside a 30-file refactor |

- **Harm watch (descriptive):** `android_snippets_1`, `android_androidify_gradleplugin`, `chrisbanes__haze-pr_250`, `badoo__reaktive-pr_763`, `badoo__reaktive-pr_764` and `lemmynet__jerboa-pr_1485`. These are build/toolchain tasks where `agp-9-upgrade` might trigger although it doesn't apply.
- **Rejected during the recheck:**
  - `haze-pr_250`: KMP, which the skill excludes.
  - `android_snippets_1`: AGP 8.12 to 8.13, not AGP 9.
  - `androidify_gradleplugin`: a convention-plugin refactor, not AGP 9.
  - `thunderbird-pr_7103`: ViewModel back-stack logic, not back-handling APIs.

The list is frozen before any run. Don't edit it after seeing results.

### Agents and models
- **Post 1 (primary):** `claude-code` with a mid-tier Claude model, starting with Claude Haiku 5.5. Claude Code is the most-used coding agent, and Google ships an official Claude Code plugin for these skills.
- **Part 2:** `codex` with a cheap GPT model (GPT 6 Luna cost $5.30 for its whole v2 leaderboard run), plus `gemini-cli` with Gemini Flash. Google tunes its skills on Gemini Flash, so this tests whether they transfer to other agents.
- **Model selection rule (pre-registered):** in the pilot, look at **C0 only** on the 10 pilot tasks. Use the model if its baseline is between 40% and 75%. If it's above 75%, step down a tier. If it's below 40%, step up. Never pick a model based on C1 results.

### Metrics
- **Primary:** task resolve rate, where the Android Bench reward is 1 if all fail-to-pass and pass-to-pass tests pass.
- **Secondary:**
  - target-skill open rate, and which skills open on unrelated tasks
  - cost in USD, input and output tokens, and wall time per trial
  - doc-lookup rate
  - excluded-trial rate per condition

### Statistics
- The unit is the task. Each task's score is the mean reward over its k trials.
- The effect is the paired delta (condition B minus A) over shared tasks, in pp.
- **95% CI:** paired bootstrap over tasks (10,000 resamples, seed 0), plus win/loss counts.
- **H2 (no harm) is non-inferiority.** It's met if the CI's lower bound on non-targeted tasks is above **−10 pp**. A tighter margin isn't testable at this budget. On worst-case stub data (every task a coin flip, true effect zero), the CI half-width was about ±8 pp. Real tasks are partly deterministic, so expect ±5–8 pp, which gives roughly 65–95% power if the true effect is zero. To raise power, use k=4 on non-targeted tasks (about 180 more trials).
- **Exclusions:** a trial with no verifier reward (environment or verifier failure) is excluded and counted per condition. Agent timeouts and crashes count as 0.
- `scripts/analyze.py` implements all of this. It was tested on synthetic Harbor-shaped output, including dropped tasks, excluded trials and skill-open detection.

---

## 6. Infrastructure and budget

### 6.0 Blocker found 2026-10-29: Google's image registry rejects all pulls
- **What fails:** every pull from `us-central1-docker.pkg.dev/android-bench-public/android-bench-tasks` fails with *"This API method requires billing to be enabled"* on Google's project #895445738779. A control image from another public Google registry pulls fine, so the problem is their project, not your setup. **Your own Google Cloud account doesn't fix it.**
- **Workaround (built into the scripts):** `scripts/build_image.sh` rebuilds each image from the archived `android-bench/android-bench` repo (commit `65a86bf`), the same builder Google used.
  - It builds Ubuntu 22.04 plus the Android SDK and emulators, then a base image per app repo, then the task image.
  - It tags the result with the registry name, and Harbor uses the local image without pulling.
  - The Harbor task Dockerfiles are identical to the archived ones, and all 100 tasks are in the archived repo.
- **What `run_matrix.sh` does per task:** use the local image if there is one; otherwise try a pull (in case Google fixes billing); otherwise build. If the build fails, the task is dropped and reported, like an oracle failure.
- **Cost of the workaround:**
  - About 30–60 min once for the shared SDK image, then about 10–30 min per task.
  - More downloads: the SDK, repo clones and Gradle dependencies.
  - Builds pull dependencies as they exist today, so a few old tasks may no longer build or pass. The oracle step catches those.
- **Report it** (2 minutes, and it helps everyone) as an issue on `android-bench/community-dataset`, for example: *"Pulling Android Bench 1.0 task images from us-central1-docker.pkg.dev/android-bench-public fails with 'requires billing to be enabled' on project 895445738779 (checked 2026-10-29). The Harbor dataset is unusable without them. Could billing be re-enabled or the images mirrored?"*

### 6.1 Can this run on your own computer? Usually yes, and it's cheaper
You don't need Google Cloud. I first picked it only because a cloud VM easily meets the hardware needs and sat next to Google's (now broken) image registry.

**Requirements** (check them with `scripts/check_machine.sh`):

| Need | Why | Minimum | Better |
|---|---|---|---|
| x86_64 Intel/AMD CPU with VT-x/AMD-V enabled in BIOS | The Android emulator needs KVM | any recent desktop/laptop CPU | |
| Linux, or **Windows 11** + WSL2 | KVM. WSL2 exposes it on Windows 11 only. | | native Linux (fewest surprises) |
| RAM | Each trial is allowed 32 GB (Gradle, emulator, agent) | 32 GB (1 trial at a time) | 64 GB (2 at a time), 128 GB (3) |
| CPU threads | Each trial is allowed 8 | 8. With fewer, set `EXTRA_HARBOR_ARGS="--cpus ignore"` and expect slowness. | 16–24 |
| Free SSD | Shared SDK image + repo bases + one task image + build cache | ~300 GB | 500 GB+ |
| Internet | SDK, repos, Gradle deps, agent installs | Roughly a few hundred GB over the study. Check your plan's cap. | unlimited plan |

**Won't work:** any Mac (no KVM for x86 emulators; Android Bench's own docs say so), Windows 10, or a PC with less than about 30 GB RAM.

**Native Linux setup:**
```bash
curl -fsSL https://get.docker.com | sudo sh          # Docker + the compose plugin Harbor needs
sudo apt-get install -y git python3 cpu-checker tmux
sudo usermod -aG docker,kvm $USER                    # then log out and back in
curl -LsSf https://astral.sh/uv/install.sh | sh && uv tool install harbor
git clone https://github.com/cdandgey5/AndroidSkillEval && cd AndroidSkillEval
scripts/check_machine.sh                             # prints a verdict and a suggested N_CONCURRENT
```

**Windows 11 setup (WSL2):**
1. Turn on virtualization in BIOS (Intel VT-x or AMD SVM). Then, in PowerShell, run `wsl --install -d Ubuntu-24.04`.
2. Create `%UserProfile%\.wslconfig`. By default WSL2 gets only **50% of your RAM**:
   ```ini
   [wsl2]
   memory=56GB          # total RAM minus ~8 GB for Windows
   processors=16        # your logical processor count
   swap=8GB
   ```
   Then run `wsl --shutdown` and reopen Ubuntu. Nested virtualization (KVM) is on by default on Windows 11.
3. Inside Ubuntu, run the native Linux setup above. Use Docker Engine installed **inside** Ubuntu, not Docker Desktop: Docker Desktop runs containers in its own VM, and passing `/dev/kvm` through it is unreliable.
4. **Disk:** WSL stores Linux files in a virtual disk on `C:`. If `C:` lacks about 300 GB free, move the distro to a bigger drive with `wsl --export` / `wsl --import` before you start.
5. Keep the PC awake for the whole run:
   - Set Windows sleep to "Never" while plugged in.
   - Pause Windows Update for the run's duration, since a forced restart stops the run. (It resumes safely, but you lose hours.)

**How long it takes locally** (rough; the pilot measures real numbers):

| Study size | What runs | 32 GB PC (1 trial at a time) | 64 GB PC (2 at a time) |
|---|---|---|---|
| **Lean** (`STUDY=lean`) | 9 targeted tasks × 3 setups × 3 tries, plus 40 other tasks × 2 setups × 2 tries = 241 trials, 49 image builds | **~6–7 days of machine time** | ~4 days |
| **Full** (default) | 100 tasks, 681 trials, 100 image builds | ~17 days | ~10–11 days |

- **Assumptions:** about 30 min per trial, 25 min per oracle and 20 min per image build. Many tasks are small, so real numbers may be lower.
- **It doesn't have to run nonstop.** Stop it any time (Ctrl+C, a reboot, overnight-only runs) and re-run the same command. Finished work is kept, and only the interrupted trial restarts. Six days of machine time can be 12 nights.
- **Maybe 2 at a time on 32 GB:** the 32 GB per trial is a cap, not what a trial actually uses. In the pilot, watch `docker stats`. If one trial peaks under about 13 GB, try `N_CONCURRENT=2` and check that no trials fail from lack of memory. That would roughly halve the trial time.
- **Lean vs full:** the lean study answers the same questions with wider error bars. It can only rule out *large* harm on general tasks (more than about 20 points), versus 10 points for the full study. Start lean, publish post 1, and run the full study later only if the results justify it.

**Recommendation:**
- **If `check_machine.sh` says OK, run it on your PC.** It saves about $75–325 of cloud compute, and electricity is about $10–20 at Ontario rates.
- **If you're on a Mac, or have under 32 GB of RAM, use 6.2.**
- **Don't buy hardware for this.** A month of cloud VM time is cheaper than a RAM upgrade.

### 6.2 Alternative: a GCP VM in `us-central1`
Use this if your PC doesn't qualify, or you want the shortest wall-clock time.

**Before you create the VM:**
- **Upgrade the account to paid.** You keep the $300 credit. Google's trial terms cap trial accounts at 8 concurrent vCPUs.
- **Check quota.** In IAM & Admin → Quotas, confirm `us-central1` allows 32 N2 CPUs, and 32 preemptible CPUs if you use Spot. New projects often start lower. Request an increase early, since approval can take hours to a day.
- Google's nested virtualization docs list E2, AMD (except N4D) and Arm as unsupported. They don't mention Spot, so `kvm-ok` on day 1 is the real test. If it fails on Spot, recreate the VM without the two Spot flags.

```bash
gcloud compute instances create android-bench \
  --zone=us-central1-a \
  --machine-type=n2-standard-32 \
  --enable-nested-virtualization \
  --provisioning-model=SPOT --instance-termination-action=STOP \
  --boot-disk-size=750GB --boot-disk-type=pd-balanced \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud
# Then on the VM: the "Native Linux setup" block in 6.1.
```

- **Spec:** n2-standard-32 has 32 vCPU and 128 GB, so 3 concurrent trials (`N_CONCURRENT=3`).
- **Restarts are safe** on either option. Each (agent, condition, task) is its own Harbor job, and it only counts as done when Harbor sets `finished_at`. After a preemption or reboot, re-run the same command. Finished tasks are skipped without rebuilding their images, and interrupted trials re-run, which costs a little extra API spend.
- **Images:** one task image on disk at a time. The shared SDK image and the per-repo base images are kept, because later tasks reuse them.
- **Check first:** whether `harbor run --launch` (Harbor Hub hosted runs) supports this dataset and what it costs. It would also need the images.

### Budget for post 1 (one agent config)

| Item | Count | Own PC | Cloud VM |
|---|---|---|---|
| Pilot (10 tasks × C0/C1 × k=1) | 20 agent trials | | |
| Image builds + oracle (100 tasks) | 100 each | | |
| Targeted: 9 tasks × C0/C1/C2 × k=5 | 135 trials | | |
| Non-targeted: 91 tasks × C0/C1 × k=3 | 546 trials | | |
| Machine time | | full: 8–17 days depending on RAM; lean: ~6–7 days on 32 GB | full: ~9 days (~220 h); lean: ~3–4 days |
| Machine cost | | ~$10–20 electricity | ~$290 on-demand (about $1.55/h); Spot is typically 60–90% less. Disk ~$35. |
| API (assumed $0.20–0.80 per trial with a Haiku-class model in Claude Code; the pilot measures it) | ~700 full / ~240 lean | full ~$140–560, lean ~$50–200 | same |
| **Total** | | **full ~$150–580, lean ~$60–220** | **full ~$220–900** |

**Cost guards:**
- Set hard spend caps in the provider console before the main runs.
- If API cost exceeds $0.80 per trial, cut non-targeted trials to k=2, which saves about a third of API cost and time.
- **Runaway trials:** the default agent timeout is 5.5 h. If the pilot shows trials running past 2 h, set `AGENT_TIMEOUT_MULT=0.36` (2 h) for every condition. Record it in `PREREGISTRATION.md` before the main runs.

---

## 7. Execution plan

Each phase has an exit gate. Don't start the next phase until it passes.

### Phase 0: Setup and pre-registration (days 1–2)
- [ ] Review `PREREGISTRATION.md` and `config/targeted_tasks.json`, and commit any edits **before** any agent run.
- [ ] Set up your PC (section 6.1) or a VM (6.2), then run `scripts/check_machine.sh` until it says OK.
- [ ] Report the registry outage (section 6.0).
- [ ] Build one image and run its oracle. The first build includes the shared SDK image, about 1 hour:
  `scripts/build_image.sh airbnb__lottie-android-pr_2427 && harbor run -d android-bench/android-bench -i "*airbnb__lottie-android-pr_2427" -a oracle`
- **Gate:** the oracle passes on that task. That proves KVM, Docker, the local build and Harbor all work.

### Phase 1: Pilot (days 3–4)
- [ ] Confirm the exact model id with your provider, and set API keys and spend caps.
- [ ] `AGENT_CONFIGS="claude-code|anthropic/<model>|medium|" scripts/run_matrix.sh pilot`. Results go to `jobs/pilot` and never mix with the main results.
- [ ] `python3 scripts/analyze.py jobs/pilot`, then check:
  - cost per trial, and minutes per job
  - the longest agent run (for the timeout cap)
  - that C1 trial logs show skills under `$CLAUDE_CONFIG_DIR/skills`
  - that skill-open detection fires on at least one C1 trial, by reading one trajectory by hand
- [ ] Apply the model selection rule (C0 only), then pin the agent version the pilot installed: `AGENT_CONFIGS="claude-code|anthropic/<model>|medium|<version>"`.
- [ ] Record the model, version and any timeout cap in `PREREGISTRATION.md`, and commit.
- **Gate:** the model is in the 40–75% band, cost fits the budget, detection works, and the pilot oracles pass.

### Phase 2: Main runs (days 5–13 on a VM or a 128 GB PC, up to day ~22 on a 32 GB PC; mostly unattended in `tmux`)
- [ ] Choose the study size (full or lean) and write it in `PREREGISTRATION.md`. Then `export STUDY=lean` (or leave it unset for full) for every command below.
- [ ] `scripts/run_matrix.sh targeted` first. It takes about 1.5 days and gives you the most interesting numbers early.
- [ ] Then `scripts/run_matrix.sh core`. It skips the targeted tasks that are already done.
- [ ] Each day: if the machine rebooted or was preempted, re-run the same command. Run `analyze.py` and watch for spikes in excluded trials.
- **Gate:** at least 95 tasks are kept after the oracle, and at least 95% of planned trials have a reward.

### Phase 3: Analysis and write-up (days 14–18)
- [ ] `python3 scripts/analyze.py` writes `results/summary.md` and `results/trials.csv`. Commit both.
- [ ] Make 3 charts:
  1. Delta with CI per slice.
  2. Target-skill open rate, C1 vs C2.
  3. Cost and tokens per trial by condition.
- [ ] Read 6 trajectories by hand and quote them: 2 where skills helped, 2 where they hurt, and 2 where the right skill was present but never opened. Also check any harm-watch trial where `agp-9-upgrade` opened.
- [ ] Upload the jobs to Harbor Hub so anyone can inspect the trials. `harbor upload` takes one job dir at a time and is private by default: `harbor auth login`, then `for d in jobs/main/*/; do harbor upload --public "$d"; done`.

### Phase 4: Publish post 1 (days 19–21)
See section 9.

### Phase 5 (recommended, weeks 4–7): Custom skill-targeted tasks, then part 2
This is what answers Q2 properly. Build about 10 Harbor tasks (`harbor init`), one per high-value skill, using Google's own eval pattern: a small real app, a precise prompt, and deterministic checks. Verify with the build passing, hidden unit/UI tests, and grep or lint rules. Avoid LLM judges.

| Skill | Task idea | Deterministic check |
|---|---|---|
| agp-9-upgrade | Upgrade a non-KMP sample that's already on AGP 9 to built-in Kotlin and the new DSL. Starting below 9 triggers the skill's "stop and ask" step. | `assembleDebug` passes; `org.jetbrains.kotlin.android` plugin removed |
| navigation-3 | Migrate a 3-screen Nav2 app to Nav3 | Build passes; `NavDisplay` used; hidden UI test visits all screens |
| migrate-xml-views-to-jetpack-compose | Convert one XML screen to Compose | Build passes; hidden Compose test finds the same nodes |
| edge-to-edge | Make a targetSdk 35 app edge-to-edge-correct | Hidden bounds test: content not under the system bars |
| r8-analyzer | Tighten over-broad keep rules | Release build passes; APK under a size threshold; app test passes |
| wear-compose-m3 | Google's own pager example | `HorizontalPagerScaffold` + `AnimatedPage` + build passes |
| play-billing-library-version-upgrade | Move Play Billing Library 6 to the current version | Build passes; no removed APIs remain |
| camerax | Replace Camera1 code | Build passes; no `android.hardware.Camera` imports |
| navigation-event | Add predictive back to a custom screen | Hidden instrumentation test for back handling |
| testing-setup | Add Compose UI test infra | The given test file compiles and runs |

Run C0, C1 and C2 with 2 agents (Claude Code and Codex or Gemini), k=5.

---

## 8. Repo layout

```
AndroidSkillEval/
├── PLAN.md                     # this file
├── PREREGISTRATION.md          # hypotheses + analysis, committed before runs
├── README.md                   # how to reproduce
├── config/
│   ├── targeted_tasks.json     # frozen targeted slice + harm-watch slice
│   └── SKILLS_LOCK.md          # generated: skill names, sizes, hashes
├── scripts/
│   ├── prepare_skills.sh       # pin + flatten android/skills
│   ├── check_machine.sh        # can this PC run it? suggests N_CONCURRENT
│   ├── build_image.sh          # build a task image locally (registry outage workaround)
│   ├── run_matrix.sh           # pilot | targeted | core (resumable)
│   └── analyze.py              # trials.csv + summary.md with bootstrap CIs
├── results/                    # committed summaries (created by analyze.py)
├── jobs/                       # gitignored raw Harbor output: oracle/, pilot/, main/
└── skills/                     # gitignored, generated
```

---

## 9. Publication plan

### Blog post (personal site, dev.to or Medium; also as a LinkedIn article)
**Title:** "I ran Google's official Android skills through Android Bench. Here's what they actually change."

1. **TL;DR:** 3 numbers. The all-task delta, the skill-open rate, and the cost per trial.
2. **Why this matters:** skills shipped in April with no public numbers, and every dev is deciding whether to install them.
3. **Setup:** Harbor, Android Bench 1.0, conditions C0/C1/C2, model, k, web off, pre-registration link.
4. **Result 1, general tasks:** help or harm, plus token cost.
5. **Result 2, targeted tasks:** the effect with its honest, wide CI, and why only 9 of 100 tasks qualify.
6. **Result 3, skill opens:** how often agents ignore a relevant skill, and what forcing it does.
7. **Harm watch:** did any skill trigger where it shouldn't?
8. **Two trajectory excerpts:** one win, one miss.
9. **Practical advice:** for example "install only the skills for your stack" or "name the skill in your prompt". Base this on your data, not assumptions.
10. **Limitations:** a small targeted slice, contamination, one agent, skills at commit `6daa53e`.
11. **Reproduce it:** the repo, the commands, and the Harbor Hub job link. Tease part 2.

### LinkedIn post (about 150 words, chart image attached)
- **Hook:** the single most surprising number.
- **Context:** 3 lines on Google skills, Android Bench and the fact that no independent data existed.
- **Findings:** 3 bullets.
- **Close:** one line on what you'd tell an Android team, the repo link, and the post link.
- Post Tuesday to Thursday, 8–10 am ET.
- Reply to every comment in the first 2 hours.
- Use topic hashtags (#AndroidDev, #AIagents). Don't tag people unless they engage.

### Credibility multipliers (cheap and high-value)
- The pre-registration commit, dated before the runs.
- Public raw `trials.csv` plus the Harbor Hub upload.
- A friendly heads-up to Android DevRel before posting, through the `android/skills` issues or the Android Bench community repo (`android-bench/community-dataset`). Offer the data; don't ask for endorsement.
- File any skill problems you find (for example, `agp-9-upgrade` stopping a headless run) as issues on `android/skills`, and link them in the post.

---

## 10. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Google's image registry stays down | Happening now | No prebuilt images | Local builds via `scripts/build_image.sh`; report the issue. If Google fixes it, the script pulls instead. |
| Old tasks no longer build (dependency drift) | Medium | Fewer tasks | Build failures drop the task before any agent spend, and are listed in the results. |
| KVM fails on Spot / WSL2 | Unknown | Blocks the run | `check_machine.sh` + one-task oracle on day 1; on GCP recreate as on-demand; on Windows check BIOS virtualization and Windows 11. |
| Home PC sleeps or Windows Update restarts it | Medium | Lost hours | Sleep off, updates paused; the run resumes safely. |
| ISP data cap | Low–medium | Overage fees | Check your plan; builds and agent installs download a few hundred GB. |
| N2 CPU quota too low | Medium on new projects | Can't create the VM | Check quotas first and request an increase early. |
| Oracle fails on some tasks | Medium | Smaller dataset | Dropped automatically before any agent spend, and listed in results. |
| Ceiling effect | High with frontier models | Hides the effect | Model selection rule in the pilot (C0 only). |
| Null result overall | High on all tasks | "Boring" post | Expected and pre-registered. Skill opens, harm watch and cost still make it useful. Part 2 custom tasks. |
| Targeted CI too wide | High | Q2 unanswered in post 1 | Say so plainly; part 2 is designed for it. |
| API cost overrun | Medium | Money | Pilot estimate, console caps, k=2 fallback, timeout cap. |
| Runaway trials (5.5 h timeout) | Medium | Time + money | Pilot measures, then cap at 2 h for all conditions if needed. |
| Spot preemption | Medium | Lost hours | Resumable per-job design (checks `finished_at`); re-run the script. |
| Skills repo changes mid-run | High (updated weekly) | Mixed versions | Pinned SHA plus `SKILLS_LOCK.md`. |
| Dataset changes mid-run | Low | Mixed task versions | `analyze.py` flags any task whose `task_checksum` changed. |
| Agent version changes mid-run | Medium | Confound | Pin with `version` after the pilot; condition order shuffled per task. |
| Someone else publishes first | Medium | Less novelty | Aim for post 1 by about 2026-11-20. Pre-registration and full reproducibility still set you apart. |

---

## 11. Next actions (today)

1. **Read `PREREGISTRATION.md`,** change anything you disagree with, and commit it. That timestamp matters.
2. **Run `scripts/check_machine.sh` on your PC** (in Ubuntu on WSL2 if you're on Windows 11). If it says OK, skip Google Cloud. If not, use the VM in section 6.2.
3. **Build one image and run its oracle** (Phase 0, last step). If it passes, the hardest risks are gone.
4. Report the registry outage (section 6.0).
5. Add API keys, set spend caps, and run `scripts/run_matrix.sh pilot`.

---

## Revision log
- **2026-10-29, recheck (summarized in the commit that adds this log):**
  - The targeted slice went from 11 tasks to 9 after reading the solution patches.
  - Added the harm-watch slice.
  - Fixed resume detection (`finished_at`).
  - Moved the oracle into each task's run, which avoids filling the disk and skips agent spend on broken tasks.
  - Merged targeted runs so their images aren't pulled twice.
  - Separated pilot output from the main results.
  - Simplified the exclusion rule to match Harbor's behavior.
  - Changed H2 from "within ±3 pp" (untestable) to non-inferiority at −10 pp.
  - Setup fixes: the Compose plugin, quota, Spot/KVM check, and the timeout cap.
  - Recomputed the budget.

- **2026-10-29, second recheck ("can I run it on my own PC?"):**
  - Found that Google's image registry rejects all pulls, and added the local image build (`scripts/build_image.sh`) and the fallback in `run_matrix.sh`.
  - Fixed re-runs that rebuilt images for already-finished tasks.
  - Added the own-PC option (Linux / Windows 11 WSL2), `scripts/check_machine.sh`, `EXTRA_HARBOR_ARGS` for under-8-thread PCs, local timing, and a split budget.
- **2026-10-29, third pass ("do we need 17 days?"):** added `STUDY=lean` (241 trials, about 6–7 days on a 32 GB PC), the `plan` command to preview a study, the lean H2 margin (−20 pp), and the note that runs can stop and resume.

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
- [GCP nested virtualization overview](https://docs.cloud.google.com/compute/docs/instances/nested-virtualization/overview)
- [GCP free trial terms](https://cloud.google.com/terms/free-trial/index-20170308)
- [WSL `.wslconfig` reference](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
- [Archived android-bench repo (image builder)](https://github.com/android-bench/android-bench)
- [SkillsBench (arXiv 2602.12670)](https://arxiv.org/abs/2602.12670)
