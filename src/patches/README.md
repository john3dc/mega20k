# Tang Nano 20K patches

The build checks the SHA-256 hashes of the bundled upstream sources, applies these patches to working copies and uses GHDL to translate the patched MiST video display processor (VDP) into Verilog.

| Patches | What they change |
| --- | --- |
| `dpram.v`, `dpram32_block.v` | Document device-specific RAM collisions and model the dual-port block RAM for simulation. Synthesis uses the original Gowin primitives. |
| `fx68k.sv`, `t80s.v` | Pack the 68000 structures for simulation, hold the nano-ROM address across a half cycle and tie off an unused Z80 register input. |
| `system.sv`, `system.vdp-mist` | Connect the MiST VDP, CPU bus arbitration and interrupts. Set up the Z80 clock, memory reset and menu memory map. |
| `system-read-start`, `system.wram-write`, `work-ram-and-cartridge-timing` | Start ROM and RAM reads when address strobe is asserted. Acknowledge work RAM writes after capture and account for refresh delays. |
| `vdp-cpu-ack`, `vdp-dma-read` | Forward acknowledged data to the CPU and VDP DMA reader while preserving FIFO waits and VDP-controlled DMA slots. |
| `audio_clock_regeneration_packet.sv`, `hdmi.sv` | Use the 27 MHz HDMI pixel clock for audio timing and synchronize the line buffers for PAL and NTSC. |
| `fpgagen/sprite-line.patch`, `fpgagen/port-timing.patch` | Adapt the sprite line buffer and VDP port timing to the board. |

The sprite cache uses two dual-port block RAMs. The sprite line buffer writes on the rising clock edge and reads on the falling edge to preserve pixel order. The 32 sprite descriptors occupy 18 LUT RAM cells.

The local JT12 ring buffers and mixer replace their upstream equivalents. The local HDMI packet scheduler handles audio packets. Both the menu and games use the 68000 clock divider of seven.

For CPU reads, the core returns DTACK and data together once `MEM_REQ == MEM_ACK`. For work RAM writes, it captures the address, data and byte enables before acknowledging the CPU, then holds the SDRAM port until the write completes. [M68000 User’s Manual, section 5.1](https://www.nxp.com/docs/en/reference-manual/MC68000UM.pdf)
