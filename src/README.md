# Build mega20k

| Directory | Contents |
| --- | --- |
| [rtl/](rtl/) | Tang Nano 20K hardware design and pin assignments |
| [firmware/](firmware/) | 68000 menu, controller input and SD access |
| [upstream/](upstream/) | Original MDTang and MiST sources used by this build |
| [patches/](patches/) | Changes applied to the upstream sources |
| [scripts/](scripts/) | Firmware and FPGA build tools |

## Toolchain

Install Make, Git and Python 3.9 or later. Put `m68k-elf-gcc` and `m68k-elf-objcopy` on your PATH. The release uses GCC 16.2.0. Extract the September 6, 2026 OSS CAD Suite for your platform into `src/.tools/oss-cad-suite/` so that `bin/yosys` is inside that directory. [Download OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2026-09-06)

## Build and verify

Run these commands from `src/`.

| Command | Output |
| --- | --- |
| `make standalone` | `build/megadrive20k/megadrive20k.fs` for USB flashing |
| `make addon` | `build/sd/cores/megadrive20k.bin` for the Systems menu |

Both targets build the menu firmware and check FPGA clock timing. After building both, run `shasum -a 256 -c release.sha256` to compare the results with the distributed files. The standalone bitstream is distributed as `megadrive20k-standalone.fs`.

<details>
<summary>Apple Silicon workaround for the GHDL error <code>duplicate LC_RPATH</code></summary>

Use the Xcode Command Line Tools to fix a local copy of GHDL, then run the build in the same terminal.

```sh
cad="$PWD/.tools/oss-cad-suite"
export GHDL="$cad/libexec/ghdl-macos"
export GHDL_PREFIX="$cad/lib/ghdl"
cp "$cad/libexec/ghdl" "$GHDL"
while [ "$(otool -l "$GHDL" | grep -Fc 'path @executable_path/../lib/ (offset 12)')" -gt 1 ]; do
    install_name_tool -delete_rpath '@executable_path/../lib/' "$GHDL" || exit 1
done
codesign -f -s - "$GHDL"
```

</details>

## Controller wiring

| Controller port | Clock | Latch | Data |
| --- | ---: | ---: | ---: |
| 1 | 27 | 28 | 25 |
| 2 | 26 | 29 | 30 |

These are FPGA pin numbers. The controller signals use 3.3 V logic. [Full pin assignments](rtl/megadrive20k.cst)

## Licensing

Project-specific code is licensed under GPL-3.0-or-later. Third-party components retain their own notices. The GPLv2 text included in the original project is also provided in `licenses/GPL-2.0.txt`. [License](../LICENSE) · [Third-party notices](../THIRD-PARTY.txt)
