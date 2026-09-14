# Windows No Sleep — V1 Product & Architecture Plan

Status: **OWNER-APPROVED PRODUCT DIRECTION / IMPLEMENTATION AUTHORITY**  
Date: 2026-09-14  
Repository: `bohanyt/windows_no_sleep`  
Canonical branch for authority docs: `main`

This document is the source of truth for V1 unless a later commit on `main` explicitly supersedes it.

---

## 1. Product goal

Build a very small portable Windows utility whose job is to keep the **computer and its workloads running**, not to keep the monitor illuminated.

Primary target:

- Windows 11, across current and mixed factory/office versions.
- Windows 11 Modern Standby (S0 low-power idle) systems.
- Headless or display-off NUC/desktop PCs.
- Laptops, including best-effort operation with the lid closed.

Secondary compatibility target:

- Windows 10 where the same supported APIs are available without adding major complexity.

The intended operator experience is:

1. copy one small folder to the machine;
2. double-click the launch file;
3. protection becomes active immediately;
4. no settings window opens at startup;
5. a tray icon appears in the notification area;
6. clicking the tray icon opens advanced settings/status;
7. exiting the app releases its requests and restores every temporary Windows setting it changed.

GitHub is the project source of truth. Local chat history is not authority.

---

## 2. What “protected” means

While Protection is active, the desired behavior is:

- prevent normal idle system sleep;
- prevent normal idle standby / Modern Standby entry as far as supported Windows APIs and temporary policy overrides allow;
- prevent normal idle hibernation while protection is active;
- keep NUC/desktop workloads running when the monitor turns off, is physically switched off, is disconnected, or no display is attached;
- keep protecting a laptop while on battery until Battery Safety takes priority;
- on laptops, temporarily make lid-close do nothing when that capability is available and safe to apply;
- resist normal/unattended shutdown or restart attempts while Protection is active, including ordinary update-driven restart paths where Windows honors application shutdown blocking;
- recover the original Windows power settings after a clean exit and after a detected unclean previous run.

Display behavior is deliberately separate:

- Windows may dim the display;
- Windows may turn the display off;
- monitor presence is not required;
- `DisplayRequired` is **not** part of default protection.

Optional advanced setting later: “Keep display on”. It is OFF by default and is not needed for V1 acceptance.

---

## 3. Safety always wins

The utility must never value “stay awake” above hardware/data safety.

### 3.1 Battery Safety

Default Battery Safety threshold: **15%**.

If a readable Windows-configured critical battery threshold is higher, the effective safety threshold should be at least **critical + 5 percentage points**. The implementation may clamp pathological values to a documented sane range.

When battery percentage reaches the effective Battery Safety threshold while on DC:

1. stop fighting sleep/hibernate/shutdown;
2. release active power requests;
3. restore any temporary lid/sleep/hibernate values changed by this app;
4. stop blocking shutdown/restart;
5. change tray/status state to `BATTERY SAFETY`;
6. let Windows/OEM critical-battery behavior take over.

V1 does **not** promise universal “save every open file”. There is no generic supported API that safely saves arbitrary third-party applications. Hibernate/normal shutdown lets Windows and individual applications preserve state according to their own contracts.

The app must never disable the Windows critical-battery mechanism.

### 3.2 Forced OS/admin/hardware actions

V1 does not claim to defeat:

- forced shutdown/restart APIs;
- enterprise policy that intentionally overrides application requests;
- firmware/thermal protection;
- power loss;
- an empty or failed battery;
- an administrator deliberately killing the process.

The goal is to eliminate ordinary unattended “it slept/hibernated/restarted overnight” behavior, not to defeat Windows at all costs.

---

## 4. Windows mechanisms

Use supported Windows mechanisms first. No mouse-jiggling, fake keystrokes, service sabotage, or update-service hacks.

### 4.1 Primary awake request

Primary API:

- `PowerCreateRequest`
- `PowerSetRequest`
- `PowerClearRequest`

Default request:

- `PowerRequestSystemRequired`

Do **not** set `PowerRequestDisplayRequired` by default.

Reason: the computer/workload must remain active while the monitor is allowed to power down.

`SetThreadExecutionState` is not the primary V1 contract. It may only be added later as a proven compatibility fallback for a specific tested Windows failure, with a documented reason and test proving why it is needed.

### 4.2 Modern Standby on battery

Microsoft documents that on Modern Standby systems on DC power, System/ExecutionRequired power requests can be terminated after the configured system sleep timeout expires plus a bounded interval. Therefore an indefinite “closed-lid laptop on battery” mode cannot rely only on a power request.

For the laptop/DC path, V1 may temporarily override the active power scheme’s relevant sleep/hibernate timeout(s) to `Never` while Protection is active, but only under the snapshot/restore rules in this document.

The implementation must first prove the minimum values that need overriding on the local Windows 11 S0 test machine. Do not mutate unrelated power settings.

### 4.3 Lid-close handling

Windows has an official Lid Switch Close Action. Value `0` means `Do Nothing`.

For machines with a lid capability, V1 should support temporary lid protection:

- snapshot original AC lid action;
- snapshot original DC lid action;
- set only the needed lid action values to `Do Nothing` while Protection is active;
- restore the exact original values on clean exit;
- restore from the previous-session snapshot before starting a new protection session if an unclean run is detected.

If policy/permissions prevent changing lid behavior:

- do not bypass the policy;
- keep normal awake protection active;
- expose `Lid protection unavailable` in Settings/diagnostics.

Do not touch power-button behavior.

### 4.4 Hibernation

Do **not**:

- run `powercfg /hibernate off`;
- delete/resize `hiberfil.sys`;
- globally disable the hibernation feature.

If V1 needs to prevent timer-driven hibernation while protection is active, it may only temporarily override the relevant active-plan timeout value and restore it exactly afterward.

### 4.5 Shutdown/restart guard

While normal Protection is active, use the supported GUI shutdown-block contract:

- create a hidden/real window handle owned by the tray process;
- call `ShutdownBlockReasonCreate` with a clear reason;
- handle `WM_QUERYENDSESSION` / `WM_ENDSESSION` correctly;
- reject normal session shutdown while protection is active;
- release the blocker during Battery Safety, explicit Stop Protection, or Exit.

This is a guard against ordinary/unattended shutdown/restart. It is not a promise against forced restart.

The app must not disable Windows Update services, Windows Update Medic, BITS, or Task Scheduler jobs.

V1 does not modify Windows Update Group Policy/MDM policy automatically. If ordinary application shutdown blocking proves insufficient on a factory image, a separately documented optional managed-policy lane may be considered later.

---

## 5. Temporary power-setting transaction

Any Windows power setting mutation must behave like a transaction.

Before the **first** mutation:

1. identify the current active power scheme;
2. read every exact AC/DC value the app plans to change;
3. persist a recovery snapshot;
4. mark the snapshot `dirty` / `restore_required`;
5. only then apply changes.

On normal Stop/Exit:

1. release power requests and shutdown blocker;
2. restore each original value exactly;
3. re-read values to verify restoration where practical;
4. mark/remove the recovery snapshot only after successful restore.

On next launch after an unclean run:

1. detect an unfinished recovery snapshot;
2. restore the recorded original values **before** applying a new protection session;
3. log whether restoration succeeded;
4. if restoration cannot be proven, do not pile new mutations on top of uncertain state.

Never create a replacement/custom power plan merely to implement V1.

Never change the active power scheme as part of normal protection.

---

## 6. UI / operator contract

### 6.1 Launch

Normal launch must be quiet:

- no main window;
- no wizard;
- Protection starts immediately with saved/default settings;
- tray icon appears.

Single-instance behavior is required. A second launch should focus/open the existing instance’s Settings instead of creating a second protection owner.

### 6.2 Tray icon

Tray state must be visually distinguishable at minimum for:

- `PROTECTED`
- `BATTERY SAFETY`
- `DEGRADED` (for example lid override unavailable)
- `STOPPED`

Click tray icon: open Settings/status window.

Right-click menu may provide:

- Open Settings
- Stop/Start Protection
- Exit

### 6.3 Settings window

Keep the window small and close to the simplicity of the old ScreenSaverDisabler UI.

Proposed controls:

- overall status (`Protected`, `Battery Safety`, `Degraded`, `Stopped`);
- `Keep computer awake` — master protection;
- `Protect on battery` — default ON;
- `Keep running with lid closed` — default ON where applicable;
- `Block automatic restart/shutdown` — default ON;
- `Start with Windows` — default OFF;
- optional/advanced `Keep display on` — default OFF, may be deferred past first acceptance build;
- battery safety percentage — default 15%, advanced setting;
- local diagnostics/log view;
- Stop Protection;
- Exit.

Do not overwhelm normal operators with raw GUIDs or `powercfg` details.

---

## 7. Packaging decision

Owner preference: avoid a custom unsigned `.exe` if a simple portable non-EXE package works reliably with factory security software.

### V1 implementation lane

Start with a transparent source-first portable package:

```text
WindowsNoSleep/
  WindowsNoSleep.cmd      # operator double-click target
  WindowsNoSleep.ps1      # tray app / Win32 interop / policy transaction
```

Development-only files may live under `src/` and `tests/`; a release folder may contain only the operator files plus optional icon/readme.

Constraints:

- Windows PowerShell 5.1 compatibility unless a stronger reason is documented;
- no network fetch at runtime;
- no encoded PowerShell payloads;
- no obfuscation;
- no security-product bypass tricks;
- do not persistently change execution policy;
- do not attempt to defeat AppLocker/WDAC/SentinelOne policy.

Important compatibility gate: Windows execution policy and endpoint security can block `.ps1` files. The first local integration pass must therefore test the actual launcher on the intended endpoint. If the source-first package is blocked or materially less trustworthy than a normal binary, V1 packaging may move to a conventional portable signed/allowlisted application. The behavior contract stays the same.

The project will not use suspicious tricks merely to avoid an `.exe` extension.

---

## 8. Runtime state and storage

Keep the app portable, but do not require its program folder to be writable.

Preferred runtime state location:

`%LOCALAPPDATA%\WindowsNoSleep\`

Suggested contents:

- `settings.json`
- `recovery.json`
- `events.log`

Rules:

- no secrets;
- bounded log size / rotation;
- recovery snapshot contains only power-setting values needed for restoration;
- settings format must be versioned;
- a corrupt settings file falls back to safe defaults;
- a corrupt recovery file must surface `DEGRADED` and avoid blind power-plan mutation.

---

## 9. Architecture

Keep this deliberately small. Logical components, even if initially contained in one script:

1. **App/Tray Host**
   - single-instance ownership;
   - hidden message window / WinForms context;
   - tray icon;
   - Settings window;
   - shutdown/session/power events.

2. **Protection Controller**
   - authoritative state machine;
   - coordinates power request, temporary plan transaction, restart guard, battery safety;
   - idempotent Start/Stop.

3. **Power Request Provider**
   - `PowerCreateRequest` / `PowerSetRequest` / `PowerClearRequest`;
   - handle lifecycle;
   - error reporting.

4. **Power Policy Provider**
   - read active scheme;
   - read exact current AC/DC setting values;
   - apply only approved temporary overrides;
   - exact restoration.

5. **Battery Monitor**
   - AC/DC state;
   - battery percentage where available;
   - configured critical threshold where readable;
   - transitions into/out of Battery Safety.

6. **Shutdown Guard**
   - block reason lifecycle;
   - shutdown messages;
   - no blocking during Battery Safety or explicit exit.

7. **Recovery Store**
   - write-before-mutate snapshot;
   - crash/unclean-exit recovery;
   - bounded local diagnostics.

Do not add a Windows service, driver, background scheduled task, or external dependency in V1.

---

## 10. State machine

Minimum states:

```text
STARTING
  -> RECOVERING_PREVIOUS_STATE (only if needed)
  -> PROTECTED

PROTECTED
  -> DEGRADED          (partial capability unavailable but core can continue)
  -> BATTERY_SAFETY    (battery threshold reached)
  -> STOPPED           (operator stops protection)
  -> EXITING

DEGRADED
  -> PROTECTED         (capability recovered)
  -> BATTERY_SAFETY
  -> STOPPED
  -> EXITING

BATTERY_SAFETY
  -> PROTECTED         (AC restored / battery safely above hysteresis threshold)
  -> STOPPED
  -> EXITING

STOPPED
  -> PROTECTED
  -> EXITING
```

Battery Safety should use hysteresis to avoid toggling rapidly near the threshold. Proposed resume point: threshold + 5 percentage points, or immediately on AC power.

Every state transition must be idempotent and logged.

---

## 11. Default behavior

Unless later changed by owner decision:

- protection on immediately at launch;
- keep system awake: ON;
- protect on battery: ON;
- lid protection: ON where applicable;
- automatic restart/shutdown guard: ON;
- display-on forcing: OFF;
- start with Windows: OFF;
- Battery Safety: 15% base threshold;
- logs: ON, local and bounded.

No user prompt is required on ordinary launch.

---

## 12. Autostart

Autostart is optional and default OFF.

If enabled, use a per-user, non-admin mechanism only. V1 must not create a privileged scheduled task or service just for autostart.

Autostart must be removable from the Settings UI and must not be required to use the application manually.

For factory NUC deployment, enabling autostart can be part of the deployment procedure after the endpoint image is validated.

---

## 13. Compatibility and privilege strategy

Normal protection must aim to run without elevation.

Capabilities that require more privilege on a particular Windows build must fail closed:

- do not silently self-elevate;
- do not bypass policy;
- report exactly which capability is unavailable;
- keep non-privileged protections active where safe.

Compatibility matrix to prove:

- Windows 11 S0 Modern Standby laptop (current local 25H2 test machine);
- Windows 11 desktop/NUC traditional always-on/headless scenario;
- at least one older supported Windows 11 build when available;
- Windows 10 as secondary compatibility if accessible.

A lack of access to every OS version is not a reason to add speculative hacks.

---

## 14. Explicit non-goals / forbidden changes

V1 must not:

- disable Windows Update service;
- disable Windows Update Medic Service;
- disable BITS;
- disable Task Scheduler;
- use “pause updates until year 20xx” tricks;
- write undocumented update registry hacks;
- disable hibernation globally;
- delete `hiberfil.sys`;
- create or switch to a custom power plan;
- permanently set sleep/display/hibernate/lid values to Never/Do Nothing as the product mechanism;
- change power-button action;
- disable critical-battery action;
- use fake mouse/keyboard activity;
- use `ES_AWAYMODE_REQUIRED` for normal protection;
- install a driver;
- install a service;
- require a cloud connection;
- collect telemetry;
- attempt to evade EDR/AV policy.

---

## 15. Implementation phases

### Phase P0 — Authority and plan

- commit this plan;
- commit Control Tower/handoff contract;
- commit safe test plan;
- update README/PROGRESS.

Exit: owner intent is recoverable from GitHub alone.

### Phase P1 — Pure/source-safe core

Implement without touching the test laptop’s power settings yet:

- launcher skeleton;
- single-instance host;
- tray icon and Settings UI;
- configuration parsing;
- state machine;
- Win32 declarations behind providers;
- mockable transaction/recovery logic;
- unit-like tests for state transitions and snapshot serialization.

Exit: code reviewable from GitHub; no Windows mutation proof claimed.

### Phase P2 — Non-mutating Windows integration

Implement/test:

- power request acquire/release;
- battery/power-source observation;
- shutdown blocker lifecycle;
- diagnostics;
- verify process exit clears handles.

No lid/sleep plan mutations yet.

Exit: `powercfg /requests` or equivalent evidence shows request appears/disappears; restart guard behavior is observed safely.

### Phase P3 — Transactional lid / DC protection

Implement the minimal required active-plan overrides with recovery snapshot.

Local executor required here because correctness depends on real Windows power policy and physical lid behavior.

Exit: exact original values are restored after normal exit, Stop, failed start, and simulated unclean-session recovery.

### Phase P4 — Modern Standby / battery safety soak

On the Windows 11 S0 laptop:

- closed-lid test on AC;
- closed-lid test on DC;
- display-off/headless-equivalent test;
- battery safety transition test without draining to dangerous levels;
- sleep-timeout accelerated test using snapshot/restore only if needed;
- multi-hour soak after short tests are clean.

Exit: observed workload stays alive for intended scenarios and restoration is proven.

### Phase P5 — Packaging / endpoint-security gate

Test the actual portable package:

- double-click launch;
- no elevation for normal path;
- PowerShell execution policy behavior;
- SentinelOne/other endpoint-security reaction where available;
- no suspicious bypass flags or obfuscation.

If the script lane is blocked, decide whether to ship a conventional signed/allowlisted portable binary rather than weakening security posture.

### Phase P6 — Release candidate

- minimal operator README;
- release folder;
- version number;
- known limitations;
- clean-machine smoke test.

---

## 16. Definition of done for V1

V1 is done only when all of these are evidenced:

1. double-click starts protection with no initial settings window;
2. tray icon appears and Settings opens from it;
3. a headless/display-off desktop/NUC scenario keeps workload execution alive;
4. display is still allowed to dim/off by default;
5. normal idle sleep is prevented while protected;
6. the local Modern Standby laptop remains operational in the approved AC scenario;
7. closed-lid behavior works where the temporary lid override is permitted;
8. DC/battery behavior is proven, including Battery Safety release;
9. ordinary shutdown/restart blocker behavior is proven and documented;
10. Stop/Exit releases requests;
11. every temporary power-policy mutation is restored exactly;
12. previous-session crash recovery restores recorded values before new mutations;
13. no global hibernation disable, update-service sabotage, or permanent power-plan mutation exists;
14. packaging works on the intended endpoint security image or a documented packaging fallback is selected;
15. source, tests, limitations, and current evidence are all in GitHub.

---

## 17. Technical references that motivated the plan

Primary Microsoft contracts to keep linked in code comments/docs where relevant:

- `PowerSetRequest`: `PowerRequestSystemRequired` keeps the system running instead of sleeping because of user inactivity. Microsoft also documents a Modern Standby/DC limitation after the system sleep timeout.
- Lid Switch Close Action: value `0` = `Do Nothing`, available since Windows Vista.
- Battery settings / critical battery action: Windows has its own critical threshold/action and it must remain authoritative for safety.
- `ShutdownBlockReasonCreate` and session-end messages: supported GUI application mechanism for blocking normal shutdown with a user-visible reason.

Do not infer stronger guarantees than the Windows documentation actually provides.
