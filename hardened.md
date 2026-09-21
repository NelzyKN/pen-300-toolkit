# HARDENED.md — PEN-300 Lab Considerations

The default files in this repo are written for a hardened Windows target:
Defender real-time scanning, AMSI, AppLocker, LSA protection, and network
inspection. This document explains what each layer does and where the
remaining gaps are.

## What PEN-300 labs enable

- Windows Defender with real-time + AMSI + network inspection (WdNisSvc)
- AppLocker with default rules (signed-only executables from non-whitelisted
  paths)
- LSA protection (RunAsPPL=1) on some targets
- Windows Firewall with restrictive egress rules on internal segments
- Domain-joined, so GPO-enforced policies apply

## What each vector already handles

### DOC vector

- Emulator detection (Sleep + wall-clock)
- De-chaining via WMI (`WmiPrvSE.exe`, not Office)
- No shellcode in the document itself
- Poller embedded as base64 in the scheduled task's `-EncodedCommand` — no
  plaintext `.ps1` on disk for Defender to read

### PDF vector

- Emulator detection (Sleep + wall-clock)
- Non-emulated API check (`VirtualAllocExNuma`)
- Ciphered cradle string — no static base64 signature in the binary
- Cradle executed via `powershell.exe -enc`, avoiding a plaintext download
  URL string in the exe

### Poller (`activate_poller.ps1`)

- Emulator detection
- Non-emulated API check
- AMSI bypass with split strings — a naive signature scan of the file
  contents does not match
- Runs entirely from `-EncodedCommand` — never touches disk as a `.ps1`

### `run.txt` (shellcode runner)

- Emulator detection
- Non-emulated API check
- Split-string AMSI bypass
- Caesar-ciphered shellcode, decrypted in memory
- Reflective execution — nothing written to disk

## Remaining gaps and mitigations

### 1. AppLocker blocks the PDF launcher from `%TEMP%`

`exportDataObject` extracts to a temp path by default. AppLocker's default
rules block unsigned executables from `%TEMP%`.

**Escape routes:**

a. **Redirect extraction to a non-blocked path:**
```javascript
this.exportDataObject({ cName: 'Q4_Invoice_Update.exe',
                        nLaunch: 1,
                        cPath: 'C:\\ProgramData\\Microsoft\\' });
```
`C:\ProgramData` is not covered by AppLocker's default rules in most
configurations. Use the `cPath` option in `pdf/build_pdf_payload.py`'s JS
block if your target blocks `%TEMP%`.

b. **Reflective PE injection via a signed parent** — the launcher runs from
a signed binary with a DLL-sideloading weakness (Mod 6).

c. **InstallUtil** — package the launcher as a .NET DLL with the payload in
the `Uninstall` method. `installutil.exe` is signed by Microsoft and is
often whitelisted by default (Mod 13.3.3).

### 2. WdNisSvc inspects the Meterpreter second stage

Windows Defender inspects network traffic against signatures. The default
staged Meterpreter second stage is signatured.

**Mitigations (in order of effectiveness):**

a. `EnableStageEncoding true` + `StageEncoder x64/zutto_dekiru` in the
handler (already configured in `shared/handler.rc`).

b. If that still trips: swap to `StageEncoder x64/xor_dynamic`.

c. If both trip: use a custom C2 channel (malleable profile in Cobalt
Strike, or a custom HTTPS beacon) with traffic shaped to look like normal
browsing.

### 3. Defender detects the AMSI-bypass pattern on disk

The poller runs from `-EncodedCommand`, so no plaintext `.ps1` ever sits on
disk. The `run.txt` script is downloaded into memory via `IEX`, so it also
never touches disk as a plaintext file.

**If Defender still flags `run.txt` on download:**

- Regenerate with a different cipher key (not 5)
- Regenerate with a different AMSI bypass (context-corruption vs
  `amsiInitFailed` field approach — Mod 12.3.2)
- Layer the non-emulated API check inside the shellcode runner itself
- Use reflective PE injection from a signed Microsoft binary with a
  sideloading weakness

### 4. LSA protection on target

Relevant only if your post-exploitation chain needs to dump LSASS. The
vector files in this repo do not touch LSASS, so this is not a gap for
initial delivery or persistence.

If a later stage of your engagement needs LSASS dumps, apply the mimidrv
technique from Mod 17.3.2: load `mimidrv.sys` (which Defender does not
signature), call `!processprotect /process:lsass.exe /remove`, then dump
via a custom `MiniDumpWriteDump` implementation.

## Pre-deployment checklist

Run these against a lab replica of your target **before** delivery.

### DOC vector

- [ ] `Q4_Invoice.docm` opens without Defender flagging the document
- [ ] "Enable Content" triggers the WMI-spawned PowerShell
- [ ] `run.txt` downloads and executes without Defender catching the
      download
- [ ] Scheduled task `OneDriveUpdate` is registered after macro executes
- [ ] No `.ps1` file exists at `%APPDATA%\Microsoft\OneDrive\update.ps1`
      (verifies the `-EncodedCommand` path is working)

### PDF vector

- [ ] `payload.exe` does not trigger Defender on write:
      ```powershell
      Get-MpThreatDetection |
          Sort-Object InitialDetectionTime -Descending |
          Select -First 5
      ```
- [ ] `Q4_Invoice.pdf` opens in Adobe Reader without a Defender alert
- [ ] "Open attachment?" prompt appears with the expected filename
- [ ] After user clicks Open, handler catches a session

### Persistence and callback

- [ ] Reboot target, log in, wait 5–10 min, verify poller alive
- [ ] `touch /var/www/html/activate` fires a session within 5 minutes
- [ ] `rm /var/www/html/activate` silences the target for 10+ minutes
- [ ] `shared/cleanup.ps1` removes all artifacts cleanly

If any step fails, iterate on that specific layer before delivery.

## What to change per engagement

Never reuse artifacts across engagements. Regenerate:

- The Caesar/XOR cipher key (both vectors)
- The base64-encoded cradle (both vectors)
- The `run.txt` shellcode (fresh msfvenom output)
- The Meterpreter SSL certificate
- The scheduled task name (`OneDriveUpdate` is a placeholder — use something
  matching the target's environment, e.g. `WindowsSystemHealthUpdate`)
- The Registry value name (`OneDriveSync` is a placeholder)
- The LNK filename (`OneDrive Sync.lnk` is a placeholder)
- The mutex/pipe names if you use those in later stages

Signatures are written fast. What passes this week gets caught next month.
