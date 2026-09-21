# HARDENED.md — PEN-300 Lab Considerations

The default files in this repo pass a lab with Defender's real-time scanner
enabled but **without** AppLocker, LSA protection, or EDR network inspection.
PEN-300 challenge labs enable all four. This document lists what changes.

## What PEN-300 labs enable

- Windows Defender with real-time + AMSI + network inspection (WdNisSvc)
- AppLocker with default rules (signed-only executables)
- LSA protection (RunAsPPL=1) on some targets
- Windows Firewall with restrictive egress rules on internal segments
- Domain-joined, so GPO-enforced policies apply

## What that means for each vector

### DOC vector

**Works as-is** provided you:
- Replace the `f.Write` placeholder in `PersistScheduledTask` with the
  base64-encoded poller body (see below).
- Use the UPDATED `activate_poller.ps1` from this repo (split strings).

The VBA macro itself passes Defender scan because it contains no shellcode
and uses split strings for the cradle. The WMI de-chaining means Office-spawns-
PowerShell heuristics do not trigger.

### PDF vector

**Fails as-is.** The original `payload.cs` was a plain downloader — Defender
flags it on extraction. The updated `payload.cs` in this repo adds:
- Emulator detection
- Non-emulated API check (VirtualAllocExNuma)
- Ciphered cradle string

If Defender still flags the compiled exe, layer the process injection from
Mod 24.3.1 — inject into `spoolsv.exe` and let the shell fire from there.

### AppLocker and the PDF launcher

AppLocker's default rules block unsigned executables from `%TEMP%`. The PDF
vector's `exportDataObject` extracts to a temp path by default. Options:

1. **Set the extraction path** to a whitelisted directory:
   ```javascript
   this.exportDataObject({ cName: 'Q4_Invoice_Update.exe',
                           nLaunch: 1,
                           cPath: 'C:\\ProgramData\\Microsoft\\' });
   ```
   `C:\ProgramData` is not covered by AppLocker's default rules in most
   configurations.

2. **Reflective PE injection** — the launcher runs from a signed parent
   process via reflective loading. Requires the launcher to be a DLL rather
   than an exe, and a signed binary with a DLL-sideloading vulnerability.
   See PEN-300 Mod 6 (Client Side Attacks with File Containers).

3. **Use InstallUtil** — if the environment whitelists `installutil.exe`
   (which it often does, since it's a signed Microsoft binary), you can
   package the launcher as a .NET DLL with the payload in the Uninstall
   method. Mod 13.3.3 covers this.

### Network inspection (WdNisSvc)

Windows Defender inspects network traffic against signatures. The default
Meterpreter second stage is signatured. Mitigations:

- `EnableStageEncoding true` + `StageEncoder x64/zutto_dekiru` in the
  Metasploit handler (already in `shared/handler.rc`)
- If that still trips: use a custom C2 channel or a Cobalt Strike beacon
  with a malleable profile

### AMSI

The poller and `run.txt` both apply the context-corruption AMSI bypass.
That bypass defeats AMSI on the target PowerShell process. It does **not**
defeat Defender's real-time scanner reading the file from disk.

**That is why the strings are split.** A naive signature scanner looking for
`AmsiUtils` or `amsiContext` in the file will not find them — the runtime
string only exists after concatenation in memory.

If you want an additional layer, use the `amsiInitFailed` field approach
(Mod 12.3.2) instead of the context-corruption approach. Different signature,
different bypass path.

## Pre-deployment checklist for PEN-300 labs

Before you deliver either vector, run these checks against a lab replica:

- [ ] Compiled `payload.exe` does not trigger Defender on write
  ```
  # On the lab target, after copying payload.exe:
  Get-MpThreatDetection | Sort-Object InitialDetectionTime -Descending | Select -First 5
  ```
- [ ] `.docm` opens without Defender flagging the document itself
- [ ] `run.txt` downloads and executes without Defender catching the download
- [ ] Scheduled task runs the poller without triggering AMSI
- [ ] `/activate` fires a session within 5 minutes
- [ ] No `/activate` present means no session for 10 minutes (gate works)
- [ ] Reboot persistence works: reboot, log in, wait 5-10 min, verify
  poller is alive

If any step fails, iterate on that specific layer before delivery.

## What to change per engagement

Never reuse the same artifacts across engagements. Regenerate:

- The Caesar/XOR cipher key (both vectors)
- The base64-encoded cradle
- The `run.txt` shellcode (fresh msfvenom output)
- The Meterpreter SSL certificate
- The scheduled task name (`OneDriveUpdate` is a placeholder — use a name
  that matches the target's environment, like `WindowsSystemHealthUpdate`)
- The mutex/pipe names, file paths, and Registry value names

Signatures are written fast. What passes this week gets caught next month.
