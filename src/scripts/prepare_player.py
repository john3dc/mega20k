#!/usr/bin/env python3
"""Prepare the Nano player directly from pinned upstream and local sources."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MD = ROOT / "upstream/mdtang"
LOCAL_SOURCES = (
    "md_clock.v",
    "megadrive20k_core.v",
    "nano_sdram.v",
    "nano_snes.v",
    "nano_spi.v",
    "megadrive20k_player.v",
    "nano_video.v",
    "nano_hdmi.sv",
    "nano_serializer.sv",
    "megadrive20k.v",
)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(work, addon=False):
    """Return the ordered source list and HDMI compilation unit."""
    lock = json.loads((ROOT / "upstream.lock.json").read_text())
    # This release contains an offline snapshot of the pinned MDTang revision.
    snapshot = json.loads((ROOT / "upstream/mdtang.sha256.json").read_text())
    for name, expected in snapshot.items():
        if sha256(MD / name) != expected:
            raise RuntimeError(f"MDTang source differs from the release snapshot: {name}")

    work.mkdir(parents=True, exist_ok=True)
    names = []
    inputs = {}

    def copy(source, name=None):
        name = name or source.name
        if name in names:
            raise RuntimeError(f"Duplicate generated source: {name}")
        shutil.copy2(source, work / name)
        names.append(name)
        inputs[str(source.relative_to(ROOT))] = sha256(source)

    project = MD / "mdtang_m60k.gprj"
    inputs[str(project.relative_to(ROOT))] = sha256(project)
    for path in re.findall(
        r'<File path="([^"]+)" type="file.verilog"', project.read_text()
    ):
        if path != "src/system.sv" and path.split("/")[1] not in (
            "common",
            "fx68k",
            "t80",
            "jt12",
            "jt89",
            "peripherals",
            "vdp",
        ):
            continue
        source = MD / path
        if path.startswith("src/vdp/"):
            continue  # The console uses the MiST VDP below.
        if source.name == "jt12_sh_rst.v":
            continue  # Both storage wrappers are in jt12_sh_ring.v.
        if source.name == "jt12_sh.v":
            copy(ROOT / "rtl/jt12_sh_ring.v", source.name)
            code = (work / source.name).read_text()
            code = re.sub(r"\bjt12_sh_rst_ring\b", "jt12_sh_rst", code)
            code = re.sub(r"\bjt12_sh_ring\b", "jt12_sh", code)
            (work / source.name).write_text(code)
        elif source.name == "jt12_genmix.v":
            copy(ROOT / "rtl/jt12_genmix_small.v", source.name)
            code = (
                (work / source.name)
                .read_text()
                .replace("module jt12_genmix_small(", "module jt12_genmix(")
            )
            (work / source.name).write_text(code)
        else:
            copy(source)

    for name in LOCAL_SOURCES:
        copy(ROOT / "rtl" / name)
    hdmi = []
    for source in sorted((MD / "src/hdmi").glob("*.sv")):
        if source.name == "serializer.sv":
            continue
        copy(
            (
                ROOT / "rtl/nano_packet_picker.sv"
                if source.name == "packet_picker.sv"
                else source
            ),
            source.name,
        )
        hdmi.append(source.name)
    hdmi += ["nano_hdmi.sv", "nano_serializer.sv"]

    # Exact patches make every difference from MDTang reviewable. git apply
    # checks context and never edits the pinned upstream working tree.
    for patch in sorted((ROOT / "patches/mdtang").glob("*.patch")):
        command = [
            "git",
            "apply",
            "--no-index",
            "--whitespace=nowarn",
            "--directory=" + str(work.relative_to(ROOT)),
            str(patch),
        ]
        subprocess.run(command[:2] + ["--check"] + command[2:], cwd=ROOT, check=True)
        subprocess.run(command, cwd=ROOT, check=True)
        inputs[str(patch.relative_to(ROOT))] = sha256(patch)

    # Translate the pinned upstream VHDL directly. The Gowin object-cache
    # binding resolves against dpram32_block in both synthesis and simulation.
    mist = ROOT / "upstream/fpgagen"
    for filename, expected in lock["fpgagen"]["files"].items():
        source = mist / filename
        if sha256(source) != expected:
            raise RuntimeError(f"MiST source differs from upstream.lock.json: {filename}")
        inputs[str(source.relative_to(ROOT))] = expected
    cache = ROOT / "rtl/obj_cache.vhd"
    inputs[str(cache.relative_to(ROOT))] = sha256(cache)
    sprite_line = ROOT / "rtl/sprite_line.vhd"
    inputs[str(sprite_line.relative_to(ROOT))] = sha256(sprite_line)
    vdp = work / "vdp.vhd"
    vdp.write_text((mist / "src/vdp.vhd").read_text())
    for name in ("sprite-line.patch", "port-timing.patch"):
        patch = ROOT / "patches/fpgagen" / name
        inputs[str(patch.relative_to(ROOT))] = sha256(patch)
        subprocess.run(["git", "apply", "--no-index", "--directory=" + str(work.relative_to(ROOT)),
                        str(patch)], cwd=ROOT, check=True)
    cad = ROOT / ".tools/oss-cad-suite"
    ghdl = os.environ.get("GHDL") or cad / "bin/ghdl"
    env = os.environ.copy()
    if not os.environ.get("GHDL"):
        env["GHDL_PREFIX"] = str(cad / "lib/ghdl")
    sources = [mist / "src/vdp_common.vhd", mist / "src/DualPortRAM.vhd", cache, sprite_line, vdp]
    with (work / "mist_vdp.v").open("w") as out:
        subprocess.run([ghdl, "--synth", "--std=08", "-fsynopsys", "-frelaxed",
                        "--no-formal", "--out=verilog", *(s.relative_to(ROOT) for s in sources),
                        "-e", "vdp"], stdout=out, cwd=ROOT, env=env, check=True)
    names.append("mist_vdp.v")

    for name in ("microrom.mem", "nanorom.mem"):
        source = MD / "src/fx68k" / name
        shutil.copy2(source, work / name)
        inputs[str(source.relative_to(ROOT))] = sha256(source)
    for source in (ROOT / ("build/launcher-addon" if addon else "build/launcher")).glob("boot_*.hex"):
        shutil.copy2(source, work / source.name)

    firmware = json.loads((ROOT / ("build/launcher-addon/manifest.json" if addon else "build/launcher/manifest.json")).read_text())
    inputs.update(firmware["source_sha256"])
    for directory in (ROOT / "firmware", MD / "firmware/fatfs"):
        for source in directory.rglob("*"):
            if source.is_file():
                inputs[str(source.relative_to(ROOT))] = sha256(source)
    for source in (
        ROOT / "upstream.lock.json",
        Path(__file__),
        ROOT / "scripts/build_megadrive20k.py",
        ROOT / "scripts/build_launcher.py",
    ):
        inputs[str(source.relative_to(ROOT))] = sha256(source)

    (work / "sources.json").write_text(
        json.dumps({name: sha256(work / name) for name in names}, indent=2) + "\n"
    )
    (work / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    return names, hdmi
