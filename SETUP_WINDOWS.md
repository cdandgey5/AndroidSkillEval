# Windows setup, step by step

This sets up your Windows 11 PC to run the benchmark. You need about **30–45 minutes**. After that, the first test (Phase 0) runs on its own for about 1–1.5 hours.

**What gets installed (all free, nothing replaces Windows):**

| Software | What it is | Where |
|---|---|---|
| WSL2 + Ubuntu 24.04 | Microsoft's "Linux inside Windows". Ubuntu runs in a window like any app. | Windows |
| Docker Engine | Runs each task in a sealed box (container) | Inside Ubuntu |
| uv + Harbor 0.25.0 | Harbor runs the benchmark; uv installs Harbor | Inside Ubuntu |
| git, python3, tmux, kvm-ok | Small helper tools | Inside Ubuntu |

**How to paste commands:**
- In **PowerShell**, right-click to paste.
- In the **Ubuntu** window, right-click or press `Ctrl+Shift+V` to paste.
- Press Enter after each block.

---

## Part A: Check your PC (5 min)

**A1. Windows 11.** Press `Win+R`, type `winver`, and press Enter. It must say **Windows 11**. Windows 10 can't give Linux access to virtualization, so this won't work there.

**A2. Virtualization is on.** Press `Ctrl+Shift+Esc` to open Task Manager, then go to **Performance → CPU**. Bottom right should say **Virtualization: Enabled**.
- If it says Disabled: restart, open the BIOS/UEFI (usually by pressing `F2` or `Del` while the PC starts), turn on **Intel Virtualization Technology (VT-x)** or **AMD SVM Mode**, then save and exit.
- While you're on that screen, note the **Logical processors** number.

**A3. Free space.** Pick the drive with **about 300 GB free** (see it in File Explorer → This PC). If it's not `C:`, you'll use the "other drive" option in B1.

**A4. Docker Desktop (only if you already have it).** Quitting it isn't enough. While its "WSL integration" is on, it puts its own `docker` command inside Ubuntu, and that version can't run the Android emulator. Do **one** of these:
- **If you don't use Docker Desktop for anything else:** uninstall it. Go to Settings → Apps → Installed apps → **Docker Desktop** → Uninstall. This also deletes its own containers and images.
- **If you use it for other projects:** open Docker Desktop → **Settings → Resources → WSL integration**. Turn **off** "Enable integration with my default WSL distro" and every distro switch, click **Apply & restart**, then quit Docker Desktop. Also untick Settings → General → "Start Docker Desktop when you sign in".

---

## Part B: Settings file for WSL (2 min)

**B1.** Open **PowerShell**: press Start, type `PowerShell`, and press Enter. Paste **one** of these blocks.

If Ubuntu goes on **C:**:
```powershell
@'
[wsl2]
memory=28GB

[general]
instanceIdleTimeout=-1
'@ | Set-Content -Path "$env:USERPROFILE\.wslconfig" -Encoding ascii
```

If Ubuntu goes on **another drive**, for example `D:` (change `D` in both places if needed):
```powershell
mkdir D:\WSL -Force
@'
[wsl2]
memory=28GB

[general]
instanceIdleTimeout=-1
distributionInstallPath=D:\\WSL
'@ | Set-Content -Path "$env:USERPROFILE\.wslconfig" -Encoding ascii
```

What these settings do:
- `memory=28GB` gives Ubuntu 28 of your 32 GB. The default is only half, which isn't enough.
- `instanceIdleTimeout=-1` keeps Ubuntu running after you close its window. Without it, Windows stops Ubuntu a few seconds later and kills a long run.
- `distributionInstallPath` puts Ubuntu's disk, and with it all the Docker images, on the drive you choose.

**B2.** Check the file: `notepad "$env:USERPROFILE\.wslconfig"`. You should see exactly the lines above. Close Notepad without changing anything.

---

## Part C: Install Ubuntu (10 min + one restart)

**C1.** Open **PowerShell as administrator**: press Start, type `PowerShell`, right-click it and choose **Run as administrator**. Then run:
```powershell
wsl --install -d Ubuntu-24.04
```
If it asks you to restart, restart the PC. Ubuntu usually opens by itself afterwards. If not, open **Ubuntu 24.04** from the Start menu.

**C2.** Ubuntu asks for a **username** (lowercase, no spaces) and a **password**.
- Nothing appears while you type the password. That's normal.
- **Remember this password**, because Ubuntu asks for it when installing software.

**C3.** In a normal PowerShell window, check the install:
```powershell
wsl --update
wsl -l -v
```
You should see `Ubuntu-24.04` with **VERSION 2**.

**If the list also shows a plain `Ubuntu`** (an older install), that's a separate Linux with its own files. Use **Ubuntu-24.04** for this project:
- Open it with `wsl -d Ubuntu-24.04` in PowerShell, or with **"Ubuntu 24.04 LTS"** in the Start menu. The plain **"Ubuntu"** entry opens the other one.
- After Docker Desktop is dealt with (A4), make it the default: `wsl --set-default Ubuntu-24.04`.
- To check which one you're in, run `echo $WSL_DISTRO_NAME` inside it. It should print `Ubuntu-24.04`.
- Leave the plain `Ubuntu` alone unless you're sure nothing in it matters. `wsl --unregister Ubuntu` deletes it and everything inside it for good.

**C4 (other drive only).** Check that Ubuntu's disk went where you wanted:
```powershell
Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss | ForEach-Object { Get-ItemProperty $_.PSPath } | Select-Object DistributionName, BasePath
```
`BasePath` should start with your chosen drive.

---

## Part D: Install everything else inside Ubuntu (10–15 min)

**D1.** In the **Ubuntu-24.04** window, download the project and run the setup script. The script stops with a clear message if you're in the wrong Ubuntu, or if Docker Desktop's `docker` is still present (A4).
```bash
cd ~
git clone https://github.com/cdandgey5/AndroidSkillEval
cd AndroidSkillEval
bash scripts/setup_wsl.sh
```
- It asks for your Ubuntu password once.
- Docker's installer may print a long notice about Docker Desktop and pause for 20 seconds. That's expected; let it continue.
- At the end it prints "Done" and the next steps.

Keep the project where it is (`~/AndroidSkillEval`, inside Ubuntu). Don't move it to a Windows folder such as `/mnt/c/...`: builds there are much slower and file permissions break.

**D2.** Restart Ubuntu so the settings take effect. Either:
- in **Ubuntu**, type `wsl.exe --shutdown` (with **.exe**), or
- in **PowerShell**, type `wsl --shutdown`.

Plain `wsl --shutdown` inside Ubuntu doesn't work, because `wsl` there is an unrelated Linux tool. The Ubuntu window closes. Wait 10 seconds, then open **Ubuntu 24.04 LTS** from the Start menu again.
- Opening Ubuntu from PowerShell starts it in a Windows folder like `/mnt/c/WINDOWS/system32`. Always run `cd ~/AndroidSkillEval` before running the project's scripts.

---

## Part E: Check that everything works (2 min)

In **Ubuntu**:
```bash
cd ~/AndroidSkillEval
scripts/check_machine.sh
```

Each line says OK, WARN or FAIL. On your 32 GB PC, a few WARN lines are expected:
- the RAM line (28 GB is enough for one trial at a time)
- the line listing your Windows drives' free space
- the image registry line (Google's server is down, so images get built locally)

The last line should say **"Verdict: this machine can run the benchmark."**

| If you see FAIL on… | Fix |
|---|---|
| `/dev/kvm missing` | Virtualization is off in BIOS (A2), or you're on Windows 10 (A1). |
| `/dev/kvm ... isn't writable` or `docker ... not usable` | In PowerShell run `wsl --shutdown`, reopen Ubuntu, and check again. If it still fails, run `bash scripts/setup_wsl.sh` again. |
| `RAM visible to Linux` below 24 GB | The `.wslconfig` file wasn't picked up. Repeat B1, check it with B2, then run `wsl --shutdown`. |
| `free disk` | Free up space on the drive Ubuntu is on (C4 shows which one). |

---

## Part F: Keep the PC awake (2 min)

- **Settings → System → Power** (or Power & battery) → **Screen, sleep & hibernate timeouts**: set "When plugged in, put my device to sleep after" to **Never**.
- **Settings → Windows Update → Pause updates**: pause for 3 weeks or more, so Windows doesn't restart in the middle of a run. If it ever restarts anyway, nothing is lost; you just run the same command again.

---

## Part G: Run the first test, Phase 0 (about 1–1.5 h, free, no API key)

In **Ubuntu**:
```bash
cd ~/AndroidSkillEval
tmux new -s bench
scripts/phase0.sh
```

`tmux` keeps the run going even if you close the Ubuntu window:
- **Leave it running:** press `Ctrl+B`, let go, then press `D`.
- **Check on it later:** open Ubuntu and run `tmux attach -t bench`.

It ends with **PASS** or **FAIL**. Either way, send me the last 20 lines:
```bash
tail -20 ~/AndroidSkillEval/jobs/phase0.log
```

---

## Later, not now
- **API key:** the pilot (the step after Phase 0) needs an Anthropic API key from console.anthropic.com. Set a monthly spend limit there first. You don't need it for Phase 0.
- **Removing everything afterwards:** in PowerShell run `wsl --unregister Ubuntu-24.04`. That deletes Ubuntu and everything inside it, including Docker images. Then delete `%UserProfile%\.wslconfig`.
