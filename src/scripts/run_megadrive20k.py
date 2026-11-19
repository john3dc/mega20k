#!/usr/bin/env python3
"""Verify the current build and program FPGA SRAM or persistent SPI flash."""

import argparse
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--flash", action="store_true", help="Write and verify persistent SPI flash")
parser.add_argument("--check-only", action="store_true", help="Verify the build without accessing the board")
parser.add_argument("--addon", action="store_true")
args = parser.parse_args()
work = ROOT / ("build/megadrive20k-addon" if args.addon else "build/megadrive20k")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


try:
    manifest = json.loads((work / "manifest.json").read_text())
    assert manifest["addon"] == args.addon, "Wrong core slot"
    assert {"clk_md", "clk_pixel", "clk_2x"} <= manifest["fmax_mhz"].keys(), "Missing clock timing"
    for clock, timing in manifest["fmax_mhz"].items():
        assert timing["achieved"] >= timing["constraint"], "Clock timing failed: " + clock
    patches = {str(p.relative_to(ROOT)) for p in (ROOT / "patches").glob("*/*.patch")}
    assert patches == {n for n in manifest["input_sha256"] if n.startswith("patches/")}, "Patch set changed"
    assert all(manifest["steps"].get(stage, {}).get("passed") for stage in ("synth", "pnr", "pack")), "Incomplete build"
    assert manifest["cst_sha256"] == digest(ROOT / "rtl/megadrive20k.cst"), "Pin constraints changed"
    assert manifest["packer_workaround_sha256"] == digest(ROOT / "scripts/pack_nano.py"), "Packer changed"
    assert len(manifest["io_port_fixes"]) == 6, "Both SNES ports must retain LVCMOS33"
    for name, expected in manifest["input_sha256"].items():
        assert digest(ROOT / name) == expected, "Source changed: " + name
    for name, expected in (manifest["source_sha256"] | manifest["asset_sha256"]).items():
        assert digest(work / name) == expected, "Build input changed: " + name
    bitstream = work / "megadrive20k.fs"
    sha = digest(bitstream)
    assert sha == manifest["megadrive20k.fs_sha256"], "Bitstream changed"
except (OSError, KeyError, ValueError, AssertionError) as error:
    target = "addon" if args.addon else "standalone"
    parser.exit(1, f"Build verification failed: {error}\nRun make {target} first.\n")

print("PASS sources, firmware, pin constraints and bitstream: " + sha, flush=True)
if args.check_only:
    raise SystemExit(0)
command = ["openFPGALoader", "-b", "tangnano20k"]
if args.flash:
    # Flash programming already reloads the FPGA. An additional reset would
    # follow the boot core's multiboot address into the addon slot.
    command += ["--write-flash", "--verify", "--offset", "0x100000" if args.addon else "0"]
else:
    command.append("--write-sram")
command.append(str(bitstream.relative_to(ROOT)))
result = subprocess.run(command, cwd=ROOT)
report = {
    "utc": datetime.now(timezone.utc).isoformat(),
    "loaded": result.returncode == 0,
    "programmed_memory": "SPI flash" if args.flash else "FPGA SRAM",
    "flash_write_verified": args.flash and result.returncode == 0,
    "bitstream": str(bitstream.relative_to(ROOT)),
    "bitstream_sha256": sha,
    "programmer_command": command,
}
(ROOT / "build/programmed.json").write_text(json.dumps(report, indent=2) + "\n")
raise SystemExit(result.returncode)
