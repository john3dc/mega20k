// SPDX-License-Identifier: GPL-3.0-or-later
// Mega Drive console boundary for the Tang Nano 20K player.
// CPU work RAM and cartridge storage use the external MEM_* interface.
// The board supplies a common regional master clock for the console and Z80.
module megadrive20k_core(
    input clk_md, clk_z80, reset_n, loading, pal,
    input [11:0] joy,joy2,
    input loader_mode,boot_copy,
    input [13:0] boot_addr,
    output [31:0] boot_data,
    input [24:1] rom_size,
    output [24:1] mem_addr,
    input [15:0] mem_data,
    output [15:0] mem_wdata,
    output mem_we,
    output [1:0] mem_be,
    output mem_req,
    input mem_ack,
    output [3:0] red, green, blue,
    output hs, vs, hblank, vblank, ce_pixel, interlace, field,
    output [1:0] resolution,
    output [15:0] audio_l, audio_r
);
    wire [15:0] game_audio_l,game_audio_r;
    // FM register/ring state can survive reset. Always send silent PCM while
    // the launcher owns the console, including the complete reset/load path.
    wire audio_enabled=reset_n && !loading && !loader_mode;
    assign audio_l=audio_enabled?game_audio_l:16'b0;
    assign audio_r=audio_enabled?game_audio_r:16'b0;
    system console(
        .RESET_N(reset_n & ~loading), .MCLK(clk_md), .CLK_Z80(clk_z80),
        .LPF_MODE(2'd3), .ENABLE_FM(1'b1), .ENABLE_PSG(1'b1),
        .DAC_LDATA(game_audio_l), .DAC_RDATA(game_audio_r),
        .LOADING(loading), .LOADER_MODE(loader_mode), .BOOT_COPY(boot_copy), .BOOT_ADDR(boot_addr), .BOOT_DATA(boot_data), .PAL(pal), .EXPORT(1'b1), .FAST_FIFO(1'b0),
        .SRAM_QUIRK(1'b0), .SRAM00_QUIRK(1'b0), .EEPROM_QUIRK(1'b0),
        .NORAM_QUIRK(1'b0), .PIER_QUIRK(1'b0), .SVP_QUIRK(1'b0),
        .FMBUSY_QUIRK(1'b0), .SCHAN_QUIRK(1'b0), .TURBO(2'b00),
        .GG_RESET(1'b0), .GG_EN(1'b0), .GG_CODE(129'b0), .GG_AVAILABLE(),
        .BRAM_A(15'b0), .BRAM_DI(16'b0), .BRAM_DO(), .BRAM_WE(1'b0), .BRAM_CHANGE(),
        .RED(red), .GREEN(green), .BLUE(blue), .VS(vs), .HS(hs),
        .HBL(hblank), .VBL(vblank), .CE_PIX(ce_pixel), .BORDER(1'b0), .CRAM_DOTS(1'b1),
        .INTERLACE(interlace), .FIELD(field), .RESOLUTION(resolution),
        .J3BUT(1'b0), .JOY_1(joy), .JOY_2(joy2), .JOY_3(12'b0),
        .JOY_4(12'b0), .JOY_5(12'b0), .MULTITAP(3'b0),
        .MOUSE(25'b0), .MOUSE_OPT(3'b0), .GUN_OPT(1'b0), .GUN_TYPE(1'b0),
        .GUN_SENSOR(1'b0), .GUN_A(1'b0), .GUN_B(1'b0), .GUN_C(1'b0), .GUN_START(1'b0),
        .SERJOYSTICK_IN(8'hff), .SERJOYSTICK_OUT(), .SER_OPT(2'b0),
        .ROMSZ(rom_size), .MEM_ADDR(mem_addr), .MEM_DATA(mem_data),
        .MEM_WDATA(mem_wdata), .MEM_WE(mem_we), .MEM_BE(mem_be), .MEM_REQ(mem_req), .MEM_ACK(mem_ack),
        .EN_HIFI_PCM(1'b0), .LADDER(1'b1), .OBJ_LIMIT_HIGH(1'b0), .TRANSP_DETECT(),
        .PAUSE_EN(1'b0), .BGA_EN(1'b1), .BGB_EN(1'b1), .SPR_EN(1'b1)
    );
endmodule
