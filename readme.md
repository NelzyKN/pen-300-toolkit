# OSEP / PEN-300 Phishing Payload Reference

Source-only reference material for the PEN-300 (OSEP) client-side attack
modules. No compiled payloads, no binaries, no ready-to-deliver documents.
This repo is a documented study reference for the techniques covered in the
course.

## What this is

Two independent phishing vectors that share a single C2 backend:

| Vector | Extension | Mechanism | Pretext |
|--------|-----------|-----------|---------|
| DOC | `.docm` (password-protected `.zip`) | Office macro → WMI → PowerShell cradle | Internal (HR / finance / IT policy) |
| PDF | `.pdf` | `/OpenAction` JavaScript → embedded exe → cradle | External (vendor invoice / shipping) |

Both vectors establish the same persistence (HKCU Run key, Startup folder LNK,
scheduled task) and share the same on-demand callback mechanism.

## Getting started

**If you just want to build and test a payload end-to-end, read
[`BUILD.md`](BUILD.md).** It walks from clone to armed, tested, deliverable
payloads and covers the Kali C2 setup, lab verification, and operator
workflow.

The subdirectory READMEs are component-level reference:

- [`doc/README.md`](doc/README.md) — DOC vector build
- [`pdf/README.md`](pdf/README.md) — PDF vector build
- [`shared/README.md`](shared/README.md) — C2-side assets

## Course alignment

- Mod 4 — Phishing with Microsoft Office
- Mod 8 — Reflective PowerShell
- Mod 11 — Introduction to Antivirus Evasion
- Mod 12 — Advanced Antivirus Evasion (AMSI)
- Mod 14 — Bypassing Network Filters
- Mod 24 — Combining the Pieces

## Repo layout

```
doc/       Office macro vector — VBA source and email body template
pdf/       PDF vector — C# launcher source and PDF generator script
shared/    C2-side assets — poller, Metasploit handler rc, cleanup, run.txt recipe
BUILD.md   End-to-end operator walkthrough
```

## Design notes

**DOC vector.** The macro contains no shellcode. It carries only a PowerShell
download cradle and the persistence setup. All shellcode lives in `run.txt`
on the operator-controlled C2, ciphered with a Caesar key and wrapped in a
reflective runner. This keeps the document's static signature profile
minimal and lets the shellcode be regenerated without re-delivering the
email.

**PDF vector.** The PDF embeds a small C# launcher executable. An
`/OpenAction` JavaScript entry fires on document open and calls
`exportDataObject` with `nLaunch: 1`, which prompts the user to open the
embedded file. A visible page attachment icon serves as a fallback for
readers with JS disabled.

**Shared C2.** Both vectors download `run.txt` from the same web root, gated
by an `/activate` file the operator creates and removes. That gate is the
on-demand switch: `touch` fires a shell within the scheduled poll interval;
`rm` silences the target.

**AV evasion.** Both vectors layer:

1. Emulator detection — Sleep + wall-clock delta check at VBA and PowerShell
2. De-chaining — PowerShell spawns as a child of `WmiPrvSE.exe`, not Office
3. AMSI bypass — context-structure corruption, applied before the cradle
4. Ciphered shellcode — no static shellcode signature in the document
5. Stage encoding on the Metasploit handler — defeats network-traffic
   signatures

## Operational notes

- Both vectors are delivered inside a password-protected ZIP to bypass Mark
  of the Web. The ZIP password goes in the phishing email body.
- Prefer internal-looking pretexts for the DOC vector and external-looking
  pretexts for the PDF vector.
- On-demand callback means the target is dormant between engagements. The
  scheduled task polls `/activate` every five minutes by default.
- Cleanup checklist in `shared/cleanup.ps1`. Run it before engagement close.

## Legal / scope

Reference material for authorized security testing and coursework only.
Nothing in this repo should be executed against systems you do not own or
have explicit written authorization to test. The techniques documented here
are the same ones taught in the OffSec PEN-300 course; use them within the
boundaries of your engagement letter and your lab.

## License

MIT — see `LICENSE`.
