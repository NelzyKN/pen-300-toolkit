# OSEP / PEN-300 Phishing Payload Reference

Source-only reference material for the PEN-300 (OSEP) client-side attack
modules. No compiled payloads, no binaries. Documented study reference.

## What this is

Two phishing vectors sharing one C2 backend, built for hardened Windows
targets (Defender + AMSI + AppLocker + LSA protection).

| Vector | Extension | Mechanism | Pretext |
|--------|-----------|-----------|---------|
| DOC | `.docm` (password-protected `.zip`) | Office macro → WMI cradle OR InstallUtil DLL | Internal (HR / finance) |
| PDF | `.pdf` | `/OpenAction` JavaScript → embedded payload → cradle | External (vendor invoice) |

Both vectors install three persistence mechanisms (HKCU Run key, Startup
LNK, scheduled task) and share an on-demand callback gate controlled by the
`/activate` file on the C2.

## Getting started

- **End-to-end build:** [`BUILD.md`](BUILD.md)
- **Hardened lab coverage:** [`HARDENED.md`](HARDENED.md)

## Repo layout

```
doc/       Office macro vector — VBA source, body template
pdf/       PDF vector — C# launcher, PDF generator
shared/    C2 assets — poller, launcher, InstallUtil DLL, handler.rc, cleanup
tools/     Build helpers — blob encoders, cradle encoder, DLL builder
BUILD.md   Operator walkthrough
HARDENED.md  Lab coverage and gap analysis
```

## Design

**Evasion layers, both vectors:**

1. Emulator detection (Sleep + wall-clock delta)
2. Non-emulated API check (`VirtualAllocExNuma`)
3. De-chaining (PowerShell child of `WmiPrvSE.exe`, not Office)
4. AMSI bypass (context corruption, string-split)
5. Ciphered shellcode in `run.txt` (no static signature in the document)
6. Stage encoding on the C2 (defeats WdNisSvc network signatures)
7. Scheduled task uses `-EncodedCommand` (no plaintext `.ps1` on disk)

**AppLocker handling:**

- DOC vector auto-detects whether `powershell.exe` runs. If blocked, it
  drops to the InstallUtil path (Mod 13.3.3) — no PowerShell child process,
  no unsigned exe from `%TEMP%`.
- PDF vector supports `--cpath` redirect to escape `%TEMP%`.

## Course alignment

Mod 4, 6, 8, 11, 12, 13, 14, 17, 24.

## Legal / scope

Authorized testing and coursework only. See `LICENSE`.
