#!/usr/bin/env bash
# build_dll.sh — compile shared/bypass_dll.cs into Update.dll.
# Locates System.Management.Automation.dll across Windows versions and
# GAC paths.
#
# Usage:
#   bash tools/build_dll.sh
#
# Output: shared/Update.dll (gitignored)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$ROOT/shared/bypass_dll.cs"
OUT="$ROOT/shared/Update.dll"

if [ ! -f "$SRC" ]; then
    echo "[!] $SRC not found"
    exit 1
fi

# Find csc
CSC=""
for candidate in csc.exe mcs csc; do
    if command -v "$candidate" >/dev/null 2>&1; then
        CSC="$candidate"
        break
    fi
done
if [ -z "$CSC" ]; then
    echo "[!] No C# compiler found (csc, mcs, or csc.exe)"
    exit 1
fi

# Find System.Management.Automation.dll
SMA=""
for candidate in \
    "/c/Windows/Microsoft.NET/assembly/GAC_MSIL/System.Management.Automation/v4.0_3.0.0.0__31bf3856ad364e35/System.Management.Automation.dll" \
    "/c/Windows/Microsoft.NET/assembly/GAC_MSIL/System.Management.Automation/v4.0_3.0.0.0__31bf3856ad364e35/System.Management.Automation.dll" \
    "/c/Windows/assembly/GAC_MSIL/System.Management.Automation/1.0.0.0__31bf3856ad364e35/System.Management.Automation.dll" \
    "/usr/lib/mono/4.5/System.Management.Automation.dll"; do
    if [ -f "$candidate" ]; then
        SMA="$candidate"
        break
    fi
done

if [ -z "$SMA" ]; then
    echo "[!] System.Management.Automation.dll not found."
    echo "    On Windows, it lives in:"
    echo "    C:\\Windows\\Microsoft.NET\\assembly\\GAC_MSIL\\System.Management.Automation\\"
    echo "    On Linux, install mono-devel."
    exit 1
fi

echo "[*] Compiler: $CSC"
echo "[*] System.Management.Automation: $SMA"
echo "[*] Output: $OUT"

# csc and mcs take different flags
case "$CSC" in
    mcs)
        mcs -target:library -out:"$OUT" \
            -r:System.Configuration.Install.dll \
            -r:"$SMA" \
            "$SRC"
        ;;
    *)
        "$CSC" /target:library /out:"$OUT" \
            /r:System.Configuration.Install.dll \
            /r:"$SMA" \
            "$SRC"
        ;;
esac

echo "[+] Built $OUT"
