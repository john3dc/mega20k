#!/usr/bin/env python3
"""Prepare/build the SD/SNES/HDMI player; never pack a timing-failed design."""

import argparse
import hashlib
import json
import subprocess
import sys
from prepare_player import prepare
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--prepare-only", action="store_true")
p.add_argument("--synth-only", action="store_true")
p.add_argument("--addon",action="store_true")
a = p.parse_args()
work = ROOT / ("build/megadrive20k-addon" if a.addon else "build/megadrive20k")
work.mkdir(parents=True, exist_ok=True)
subprocess.run([sys.executable, str(ROOT / "scripts/build_launcher.py"),*(["--addon"] if a.addon else [])], check=True)
names, hdmi = prepare(work, addon=a.addon)
hashes = {n: hashlib.sha256((work / n).read_bytes()).hexdigest() for n in names}
(work / "sources.json").write_text(json.dumps(hashes, indent=2) + "\n")
fx = ["fx68k.sv", "fx68kAlu.sv", "uaddrPla.sv"]
script = "read_slang --single-unit --top fx68k " + " ".join(fx) + "\n"
script += "read_verilog -lib +/gowin/cells_sim.v\n"
script += "read_slang --single-unit --top nano_hdmi " + " ".join(hdmi) + "\n"
script += (
    "read_verilog -sv -D VERILATOR "
    + " ".join(n for n in names if n not in fx + hdmi)
    + "\n"
)
# The synchronous FM log-sine ROM occupies the last block RAM. Its clock
# enable and registered output are preserved by the Gowin memory mapping.
script += 'setattr -unset ramstyle\nsetattr -set ram_style "block" jt12_logsin/sinelut\n'
script += 'setattr -set ram_style "logic" jt12_exprom/explut_jt51\n'
# ABC &mfs aborts in Abc_LitIsCompl on this carry-box netlist with the
# pinned 20260906 toolchain. Keep its documented mapping flow through &if,
# without that final optimization. Do not rely on ABC's intermediate file.
# Routing has to meet every clock constraint before packing a bitstream.
script += 'scratchpad -set abc9.script "+&scorr;&sweep;&dc2;&dch,-f,-r;&ps;&if,-a,-F,4,-A,4,-W,500,-v"\n'
# Keep short sprite descriptors in distributed RAM. sprite_line.vhd separately
# requests distributed RAM for the falling-edge sprite composition read.
script += 'setattr -set ram_style "distributed" dualportram_Barch_5_35/ram\n'
gowin = "synth_gowin -top megadrive20k -family gw2a -nowidelut -nodsp "
script += (
    gowin
    + "-run begin:map_gates\ntechmap -map +/techmap.v t:$alu r:Y_WIDTH<=8 %i\n"
    + gowin
    + "-run map_gates:\ncheck -assert\ntee -o stats.json stat -json\nwrite_json player.json\n"
)
(work / "synth.ys").write_text(script)
(work / "clocks.py").write_text(
    'ctx.addClock("clk27",27)\nctx.addClock("clk_md",54)\nctx.addClock("clk_2x",107.387)\nctx.addClock("clk_pixel",27)\nctx.addClock("clk_pixel_x5",135)\n'
)
if a.prepare_only:
    print("Prepared", work)
    sys.exit(0)
tool = ROOT / ".tools/oss-cad-suite/bin"
commands = [("synth", [str(tool / "yosys"), "-T", "-s", "synth.ys"])]
if not a.synth_only:
    commands += [
        (
            "pnr",
            [
                str(tool / "nextpnr-himbaechel"),
                "--seed",
                "1",
                "--device",
                "GW2AR-LV18QN88C8/I7",
                "-o",
                "family=GW2A-18C",
                "-o",
                "cst=" + str(ROOT / "rtl/megadrive20k.cst"),
                "--json",
                "player.json",
                "--write",
                "routed.json",
                "--pre-pack",
                "clocks.py",
                "--report",
                "timing.json",
            ],
        ),
        (
            "pack",
            [
                str(tool / "tabbypy3"),
                str(ROOT / "scripts/pack_nano.py"),
                "-d",
                "GW2A-18C",
                "--mspi_as_gpio",
                "--multiboot_address", "0" if a.addon else "0x100000",
                "-o",
                "megadrive20k.fs",
                "routed.json",
            ],
        ),
    ]
for n in ("player.json", "routed.json", "timing.json", "megadrive20k.fs"):
    (work / n).unlink(missing_ok=True)
report = {
    "asset_sha256": {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in list(work.glob("boot_*.hex"))
        + [work / "microrom.mem", work / "nanorom.mem"]
    },
    "packer_workaround_sha256": hashlib.sha256(
        (ROOT / "scripts/pack_nano.py").read_bytes()
    ).hexdigest(),
    "source_sha256": hashes,
    "input_sha256": json.loads((work / "inputs.json").read_text()),
    "steps": {},
    "master_clock_hz": {"ntsc": 27e6 * 3420*262 / (855*527), "pal_average": 27e6 * 3420*313 / (872*623)},
    "pnr_seed": 1,
    "core_name": "megadrive20k",
    "addon": a.addon,
    "core_switch": {"base_address": 0, "slot_address": 0x100000, "slot_bytes": 0x100000, "reconfig_pin": 9},
    "cpu_boost_available": False,
    "cpu_clock": {"divider": 7, "menu_divider": 7, "vdp_fifo_throttle_preserved": True},
    "vdp_upstream": json.loads((ROOT / "upstream.lock.json").read_text())["fpgagen"]["commit"],
    "region": "auto",
    "rom_root": "/megadrive",
    "hidden_save_directory": "/megadrive/saves",
    "sd_save_persistence": False,
    "abc9_flow": "scorr; sweep; dc2; dch -f -r; if -a -F 4 -A 4 -W 500 -v; no crashing mfs pass",
    "sdram_read_buffer_bytes": 4,
    "sdram_refresh_priority": True,
    "cpu_memory_reads": "Start on AS; issue game reads directly to SDRAM; forward completed reads to CPU and VDP DMA; acknowledge buffered writes on capture",
    "hdmi_field_pixels": {"ntsc": [855, 527], "pal": [872, 623]},
    "regional_clock": "One complete HDMI field per progressive VDP field",
    "includes_hdmi_audio": True,
    "firmware_sha256": hashlib.sha256(
        (ROOT / ("build/launcher-addon/launcher.bin" if a.addon else "build/launcher/launcher.bin")).read_bytes()
    ).hexdigest(),
}
for step, cmd in commands:
    report["cst_sha256"] = hashlib.sha256(
        (ROOT / "rtl/megadrive20k.cst").read_bytes()
    ).hexdigest()
    log = work / f"{step}.log"
    with log.open("w") as out:
        r = subprocess.run(cmd, cwd=work, stdout=out, stderr=subprocess.STDOUT)
    # Some Yosys/ABC failures return Yosys success after loading a checkpoint.
    # Such an interrupted optimization must never authorize packing/flashing.
    tool_errors = [
        line for line in log.read_text().splitlines()
        if step == "synth" and ("failed: return code" in line or "Assertion failed:" in line)
    ]
    report["steps"][step] = {
        "passed": r.returncode == 0 and not tool_errors,
        "log": str(log.relative_to(ROOT)),
        "tool_errors": tool_errors,
    }
    if step == "synth" and report["steps"][step]["passed"]:
        cells = json.loads((work / "player.json").read_text())["modules"][
            "megadrive20k"
        ]["cells"]
        cache = Counter(c["type"] for n, c in cells.items() if ".obj_cache." in n)
        info = Counter(c["type"] for n, c in cells.items() if ".obj_spinfo." in n)
        sprite_line = Counter(c["type"] for n, c in cells.items() if ".obj_ci." in n)
        assert (
            cache["DPB"] == 2
        ), "Sprite cache must retain the two original DPB primitives"
        assert (
            info["RAM16SDP4"] == 18 and info["DFFE"] < 100
        ), "Sprite descriptors must map to LUT RAM, not a register bank"
        assert sprite_line["RAM16SDP4"] == 64 and sprite_line["DFFN"] == 7, (
            "Sprite composition must use distributed RAM and native falling-edge read registers"
        )
        report["sprite_memory"] = {
            "cache": "two original MDTang DPB primitives",
            "line_descriptors": "32 x 35 distributed RAM",
            "descriptor_lut_ram_cells": info["RAM16SDP4"],
            "composition_lut_ram_cells": sprite_line["RAM16SDP4"],
            "composition_read_registers": sprite_line["DFFN"],
        }
    if step == "pack" and r.returncode == 0:
        report["io_banks"] = json.loads((work / "io-banks.json").read_text())
        report["io_port_fixes"] = json.loads((work / "io-port-fixes.json").read_text())
    if step == "pnr" and (work / "routed.json").exists():
        c = Counter(
            cell["type"]
            for m in json.loads((work / "routed.json").read_text())["modules"].values()
            for cell in m["cells"].values()
        )
        report["routed_cells"] = dict(c)
        report["physical_lut_sites"] = (
            sum(c[t] for t in ("LUT1", "LUT2", "LUT3", "LUT4"))
            + c["ALU"]
            + 4 * c["RAM16SDP4"]
        )
        report["fmax_mhz"] = json.loads((work / "timing.json").read_text())["fmax"]
    for n in ("player.json", "routed.json", "megadrive20k.fs"):
        if (work / n).exists():
            report[n + "_sha256"] = hashlib.sha256((work / n).read_bytes()).hexdigest()
    (work / "manifest.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    if not report["steps"][step]["passed"]:
        print(log.read_text()[-4000:])
        if tool_errors:
            print("\n".join(tool_errors))
        sys.exit(r.returncode or 1)
    print(step, "passed", flush=True)
