#!/usr/bin/env python3
"""Build a freestanding 68000 launcher and four VRAM initialization lanes."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--addon",action="store_true")
args=parser.parse_args()
work = ROOT / ("build/launcher-addon" if args.addon else "build/launcher")
work.mkdir(parents=True, exist_ok=True)
vendor = ROOT / "upstream/mdtang/firmware/fatfs"
for name in ("ff.c", "ff.h", "ffunicode.c", "ffconf.h", "diskio.h"):
    code = (vendor / name).read_text()
    if name == "ff.c":
        assert code.count('#include "../picorv32.h"') == 1
        code = code.replace('#include "../picorv32.h"', "")
    if name == "ffconf.h":
        for key, value in {
            "FF_FS_READONLY": 1,
            "FF_FS_MINIMIZE": 1,
            "FF_USE_CHMOD": 0,
            "FF_USE_STRFUNC": 0,
            "FF_FS_TINY": 1,
        }.items():
            code, n = re.subn(
                r"(#define " + key + r"\s+)\d+", lambda m: m[1] + str(value), code
            )
            assert n == 1, key
    (work / name).write_text(code)
gcc = shutil.which("m68k-elf-gcc")
assert gcc, "Install m68k-elf-gcc and add it to PATH"
sources = [
    ROOT / "firmware" / f
    for f in ("start.S", "main.c", "screen.c", "input.c", "sd.c", "libc.c", "core_format.c", "core_flash.c", "core_loader.c")
] + [work / "ff.c", work / "ffunicode.c"]
cmd = [
    gcc,
    "-m68000",
    "-Os",
    "-std=c99",
    "-ffreestanding",
    "-fno-builtin",
    "-flto",
    "-ffunction-sections",
    "-fdata-sections",
    "-Wall",
    "-Wextra",
    "-Wno-misleading-indentation",
    "-I" + str(ROOT / "firmware/include"),
    "-I" + str(work),
    "-nostdlib",
    "-Wl,--gc-sections",
    "-Wl,-Map=" + str(work / "launcher.map"),
    "-T" + str(ROOT / "firmware/launcher.ld"),
    *(["-DMEGADRIVE_ADDON"] if args.addon else []),
    *map(str, sources),
    "-lgcc",
    "-o",
    str(work / "launcher.elf"),
]
subprocess.run(cmd, check=True)
subprocess.run(
    [
        "m68k-elf-objcopy",
        "-O",
        "binary",
        str(work / "launcher.elf"),
        str(work / "launcher.bin"),
    ],
    check=True,
)
data = (work / "launcher.bin").read_bytes()
assert len(data) <= 65536
print("Launcher:", len(data), "bytes / 65536")
data = data.ljust(65536, b"\0")
for name, offset in [("u1", 0), ("l1", 1), ("u2", 2), ("l2", 3)]:
    (work / f"boot_{name}.hex").write_text(
        "".join(f"{v:02x}\n" for v in data[offset::4])
    )
report = {
    "rom_bytes": len((work / "launcher.bin").read_bytes()),
    "rom_sha256": hashlib.sha256(data).hexdigest(),
    "compiler": subprocess.check_output([gcc, "--version"], text=True).splitlines()[0],
    "source_sha256": {
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sources
        + [
            ROOT / "firmware/launcher.ld",
            ROOT / "firmware/platform.h",
            ROOT / "firmware/include/font8x8_basic.h",
        ]
    },
}
(work / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
