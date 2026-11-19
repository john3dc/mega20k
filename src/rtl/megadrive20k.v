// SPDX-License-Identifier: GPL-3.0-or-later
module megadrive20k(
    input clk27,button,snes_data1,snes_data2,sd_miso,flash_miso,
    output snes_latch1,snes_clock1,snes_latch2,snes_clock2,
    output sd_clk,sd_mosi,sd_cs_n,led_n,
    output flash_clk,flash_mosi,flash_cs_n,flash_wp_n,flash_hold_n,reconfig_n,
    output [2:0] tmds_d_p,tmds_d_n,output tmds_clk_p,tmds_clk_n,
    output O_sdram_clk,O_sdram_cke,O_sdram_cs_n,O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n,
    output [10:0] O_sdram_addr,output [1:0] O_sdram_ba,output [3:0] O_sdram_dqm,inout [31:0] IO_sdram_dq
);
    wire clk_md,clk_sdram,locked;
    assign flash_wp_n=1'b1;
    assign flash_hold_n=1'b1;
    wire clk_pixel_x5,clk_pixel,video_locked;
    rPLL #(.FCLKIN("27"),.IDIV_SEL(0),.FBDIV_SEL(4),.ODIV_SEL(8),
        .DYN_DA_EN("false"),.CLKFB_SEL("internal"),.DEVICE("GW2AR-18C")) video_pll(
        .CLKIN(clk27),.RESET(1'b0),.RESET_P(1'b0),.CLKFB(1'b0),.FBDSEL(6'b0),.IDSEL(6'b0),.ODSEL(6'b0),
        .PSDA(4'b0),.DUTYDA(4'b0),.FDLY(4'b0),.CLKOUT(clk_pixel_x5),.CLKOUTP(),.LOCK(video_locked),.CLKOUTD(),.CLKOUTD3());
    CLKDIV #(.DIV_MODE("5")) pixel_div(.HCLKIN(clk_pixel_x5),.RESETN(video_locked),.CALIB(1'b0),.CLKOUT(clk_pixel));
    // Keep HDMI at 135/27 MHz; the second PLL supplies the console.
    // PFD = 135/44 MHz, VCO = 859.09 MHz. No PLL re-lock on region changes.
    wire clk_2x, clk_allowed, inhibit, pal;
    rPLL #(.FCLKIN("135"),.IDIV_SEL(43),.FBDIV_SEL(34),.ODIV_SEL(8),
        .CLKFB_SEL("internal"),.DEVICE("GW2AR-18C")) pll(
        .CLKIN(clk_pixel_x5),.RESET(!video_locked),.RESET_P(1'b0),.CLKFB(1'b0),
        .FBDSEL(6'b0),.IDSEL(6'b0),.ODSEL(6'b0),.PSDA(4'b0),.DUTYDA(4'b0),.FDLY(4'b0),
        .CLKOUT(clk_2x),.CLKOUTP(),.LOCK(locked),.CLKOUTD(),.CLKOUTD3());
    md_clock master(.clk_2x(clk_2x),.locked(locked),.pal(pal),.clk_md(),.inhibit(inhibit));
    // DHCEN suppresses complete reference pulses. The dedicated divider
    // feeds the global clock network and the SDRAM output DDR register.
    DHCEN gate_clk(.CLKIN(clk_2x),.CE(inhibit),.CLKOUT(clk_allowed));
    CLKDIV #(.DIV_MODE("2")) master_div(.HCLKIN(clk_allowed),.RESETN(locked),.CALIB(1'b0),.CLKOUT(clk_md));
    ODDR forward_clock(.CLK(clk_md),.D0(1'b0),.D1(1'b1),.TX(1'b0),.Q0(clk_sdram),.Q1());
    wire clk_z80=clk_md;
    reg [7:0] powerup=0;
    wire clocks_locked = locked && video_locked;
    always @(posedge clk_md or negedge clocks_locked)begin
        if(!clocks_locked)powerup<=0;
        else if(!(&powerup))powerup<=powerup+1'b1;
    end
    wire reset_n=&powerup;
    wire snes_latch,snes_clock;
    assign snes_latch1=snes_latch;assign snes_latch2=snes_latch;
    assign snes_clock1=snes_clock;assign snes_clock2=snes_clock;
    wire hs,vs,hblank,vblank,ce_pixel,interlace,field;
    wire [1:0] resolution;
    wire [3:0] red,green,blue;
    wire [15:0] audio_l,audio_r;
    megadrive20k_player #(.FREQ_HZ(53700000)) player(.menu_button(button),.*);
    wire [2:0] tmds;
    wire tmds_clock;
    nano_video video(.*);
    for(genvar i=0;i<3;i=i+1)begin:hdmi_data
        TLVDS_OBUF diff(.I(tmds[i]),.O(tmds_d_p[i]),.OB(tmds_d_n[i]));
    end
    TLVDS_OBUF clock_diff(.I(tmds_clock),.O(tmds_clk_p),.OB(tmds_clk_n));
endmodule
