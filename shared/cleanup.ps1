# cleanup.ps1 — run on target before engagement close.
# Removes artifacts created by the DOC and PDF vectors.

Remove-Item "$env:APPDATA\Microsoft\OneDrive\update.ps1" `
    -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\OneDrive Sync.lnk" `
    -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name OneDriveSync -ErrorAction SilentlyContinue
schtasks /delete /tn OneDriveUpdate /f 2>$null

# ── Artifact review (forensic) ──────────────────────────────────────────────
# These are not removed by the script; they are checked to make sure the
# engagement's footprint is fully understood before close:
#
#   - Prefetch:  WINWORD.EXE, powershell.exe, schtasks.exe
#   - RecentDocs registry key — contains the .docm filename
#   - AmCache / ShimCache — records execution of payload.exe
#   - Sysmon Event ID 1 — process creation, shows schtasks spawn
#   - Windows Event Log — schtasks creation entry
#   - $MFT / $UsnJrnl — the on-disk update.ps1 and payload.exe
#   - Web server access log on the mail side — the phishing email itself
#
# On a real engagement, this list should be documented before the engagement
# starts and verified clean after cleanup runs.
