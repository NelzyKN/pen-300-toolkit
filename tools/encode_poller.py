#!/usr/bin/env python3
"""
encode_poller.py — base64-encode activate_poller.ps1 for embedding in VBA
or passing to powershell.exe -EncodedCommand.

Usage:
    python3 encode_poller.py shared/activate_poller.ps1

Output: a single-line base64 blob (UTF-16LE) to paste into the VBA
POLLER_B64 constant, or into any -enc argument.

Why UTF-16LE: PowerShell's -EncodedCommand expects the input decoded as
UTF-16LE. This matches what [Convert]::ToBase64String([Text.Encoding]::
Unicode.GetBytes(...)) produces on Windows.
"""

import argparse
import base64


def encode(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        body = f.read()
    return base64.b64encode(body.encode("utf-16-le")).decode("ascii")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="Path to the .ps1 file to encode")
    args = ap.parse_args()
    print(encode(args.path))


if __name__ == "__main__":
    main()
