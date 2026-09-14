# windows_no_sleep

Status snapshot for planning. **No rewrite yet.** Surveyed locally on 2026-09-14 by the Cursor local executor. Planning happens with GPT 5.6 + owner.

Goal: a small Windows 11 tool that keeps the display from turning off, robust across Windows 11 versions and updates. The current tool sometimes fails, especially on latest Windows 11.

Repo: https://github.com/bohanyt/windows_no_sleep  
Local workspace: `C:\Users\vincentius\Documents\ISTW IT Projects\ScreenSaverDisabler`

The legacy `.exe` stays on the laptop (third-party binary). This repo has the full survey so planning does not depend on chat history.

---

## 1. What exists locally

Only a 2023 Debug binary. **No C# source.** Local folder was not a git repo before this snapshot.

```
screenseverdisable/
  ScreenSaverDisabler.exe         9216 bytes, 2023-11-08 08:36
  ScreenSaverDisabler.exe.config  .NET Framework 4.7
  ScreenSaverDisabler.pdb         Debug symbols
```

| Field | Value |
|---|---|
| Assembly | `ScreenSaverDisabler, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null` |
| PE | AnyCPU MSIL |
| Target | `.NETFramework,Version=v4.7` |
| SHA256 | `AA0F62E5C00A3CF2BB82DDC1FA8373F66F8DD956D0A8A94A90705261A6E3B044` |
| PDB original path | `F:\dev\download\screensaver-disabler\ScreenSaverDisabler\obj\Debug\ScreenSaverDisabler.pdb` |
| Process at survey | not running |
| Autostart / scheduled task | none found |

Config file is also in this repo as `screenseverdisable/ScreenSaverDisabler.exe.config`.

---

## 2. Identity of the old program

This is **not** an original ISTW app. It matches [pedrolcl/screensaver-disabler](https://github.com/pedrolcl/screensaver-disabler) 1:1:

- Namespace `Monon`, types `FormMain` + `Program`
- Window title `Screensaver Disabler`, checkbox `Disable ScreenSaver` (`keepOnSw`)
- Copyright Pedro Lopez-Cabanillas 2020
- License **BSD-3-Clause** (see `legacy/LICENSE`)
- README of the original targets **Windows 10**, 32/64-bit, .NET Framework 4.7
- Original author also points people to PowerToys Awake

Referenced assemblies: `mscorlib`, `System`, `System.Windows.Forms`, `System.Drawing` (all 4.0.0.0).

---

## 3. Exact logic (from original Form1.cs + local IL)

The whole keep-awake implementation:

```csharp
SetThreadExecutionState(ES_DISPLAY_REQUIRED | ES_CONTINUOUS); // checkbox on
SetThreadExecutionState(ES_CONTINUOUS);                       // checkbox off / form close
```

On `FormMain_Load`, the checkbox is set `Checked = true`, which fires `CheckedChanged` and applies the display-required state once.

**Not used:**

- `ES_SYSTEM_REQUIRED` (enum exists, never passed)
- `ES_AWAYMODE_REQUIRED`
- `PowerCreateRequest` / `PowerSetRequest`
- Periodic timer refresh
- `SystemParametersInfo(SPI_SETSCREENSAVEACTIVE)`
- Resume / session-unlock / power-source-change handlers
- Tray icon, autostart, watchdog, logging

The window must stay open. Closing the form clears the execution state.

P/Invoke: `kernel32.dll` `SetThreadExecutionState`, `asInvoker`, no admin required.

---

## 4. Why it fails on latest Windows 11 (likely, not yet reproduced this session)

This is a 2020 Win10 one-shot `SetThreadExecutionState` design. It is a poor fit for Windows 11 24H2/25H2 + Modern Standby.

1. **API is per-thread**, not per-process. One call on the UI thread. If Windows resets thread execution state after lock, sleep, update, or UI stall, protection is gone and nothing re-applies it.
2. **No `ES_SYSTEM_REQUIRED`.** Display-required alone does not reliably block Modern Standby.
3. **On Modern Standby (S0ix), display off is the entry to sleep.** Desktop apps are then paused by the Desktop Activity Monitor. After that, a WinForms app cannot wake the panel.
4. **Screensaver is a different subsystem.** This app never disables the screensaver via SPI. Microsoft docs also note `SetThreadExecutionState` is about idle sleep/display timers, not a guaranteed screensaver kill.
5. **Does not survive:** lid close, Start-menu Sleep, Group Policy, Dynamic Lock, Presence Sensing, Adaptive Dimming, user-initiated sleep.
6. **Must keep a visible window running.** Easy to close; no tray.
7. Original target was Windows 10. Windows 11 25H2 power policy is stricter.

Conclusion from survey: the EXE is probably working as designed, but the design lost against current Windows power management. Treat this as a **rewrite**, not a binary patch.

---

## 5. Test laptop (local executor machine)

Survey time: 2026-09-14, session **not elevated**.

| Item | Value |
|---|---|
| OS | Windows 11 Pro for Workstations **25H2** |
| Build | `10.0.26200.9445` (`CurrentBuild` 26200, UBR 9445) |
| Arch | 64-bit |
| Sleep states | **S0 Low Power Idle (Modern Standby), network connected**. S1/S2/S3 not available. Hibernate not enabled. Hybrid sleep N/A. Fast startup N/A. |
| Power scheme | Balanced (`381b4222-f694-41f0-9685-ff5bb260df2e`) |
| Display off AC | **never** (`0`) |
| Display off DC | **600 s = 10 min** |
| Sleep after AC | **never** (`0`) |
| Sleep after DC | **1200 s = 20 min** |
| Hibernate after AC | never |
| Hibernate after DC | `0x3f480` seconds |
| Battery | present, 100%, `BatteryStatus=2` (on AC) at survey |
| Screensaver | `ScreenSaveActive=1`, but **no** `SCRNSAVE.EXE`, timeout empty |
| .NET Framework | 4.8 (`Release` 533509) — old EXE can still run |
| .NET SDK | 8.0.421 + `Microsoft.WindowsDesktop.App` 8.0.27 — rewrite on .NET 8 is feasible |
| PowerToys | not installed |
| `gh` CLI | not installed |
| `powercfg /requests` | **access denied** without admin — could not verify execution requests |

Implication for the user "screen dies" complaint: on this machine, a classic screensaver is probably not the culprit. More likely **display idle timeout on battery** and/or **Modern Standby after display off**. On AC, display-off is already "never," so failures on AC would point to Modern Standby / lock / policy, not the 10-minute DC timeout.

---

## 6. GitHub / git at survey time

- Repo created 2026-09-14, public, empty (no default branch, API 409).
- Owner `bohanyt` has admin.
- Local folder was **not** a git repo.
- This first commit is documentation only: survey + original license + the `.exe.config`. The `.exe` / `.pdb` remain on the laptop.

---

## 7. What the local executor did **not** do

- Did not launch `ScreenSaverDisabler.exe`
- Did not change `powercfg`, registry, startup, or sleep settings
- Did not write application source
- Did not reproduce the "screen still turns off" bug in this session

---

## 8. Safety constraints for later testing

The laptop may be used as a test device. Do not brick power settings.

- Snapshot current scheme before any `powercfg` change; restore after.
- Do **not** permanently set sleep/display to never as the product.
- Keep-awake must be scoped to "while the app is on," and must clear on exit.
- Prefer user-level APIs (`SetThreadExecutionState` / `PowerSetRequest`). Avoid requiring admin.
- Lid-close and Start-menu Sleep should remain user-controlled unless the owner explicitly wants otherwise.
- First tests: short display-timeout overlay, then restore. Confirm with `powercfg /requests` (needs admin) that the request appears and disappears.

---

## 9. Open questions for GPT 5.6 + owner

1. Scope: keep **display on**, keep **system awake**, or both? Lid close: allow sleep or hold?
2. UI: tray icon, small window, or silent background?
3. Autostart at logon?
4. AC vs battery: same keep-awake, or allow battery to save power?
5. Clean rewrite vs fork of BSD-3-Clause original (attribution required if code is reused)?
6. Stack: .NET 8 WinForms + tray looks like the best fit for this machine.

Likely rewrite direction (not decided): .NET 8 tray app, `PowerCreateRequest` + `PowerSetRequest` **and** refreshed `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)`, re-apply on resume/unlock, no permanent power-plan mutation.

---

## 10. Roles

| Role | Who |
|---|---|
| Planner | GPT 5.6 + owner |
| Local executor / test machine | Cursor agent on this Windows 11 25H2 laptop |
| Publish | this GitHub repo |

After a plan exists, the local executor implements and tests here, then pushes source to this repo.
