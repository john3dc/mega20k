// SPDX-License-Identifier: GPL-3.0-or-later
// Single-CPU SD player. On cold boot VRAM contains the firmware; copy it
// into reserved SDRAM before VRAM is cleared. Warm menu return preserves it.
module megadrive20k_player #(parameter FREQ_HZ=54000000)(
    input clk_md,clk_sdram,clk_z80,reset_n,menu_button,
    input snes_data1,snes_data2,
    output snes_latch,snes_clock,
    input sd_miso,output sd_clk,sd_mosi,output reg sd_cs_n,
    input flash_miso,output flash_clk,flash_mosi,output reg flash_cs_n,
    output reg reconfig_n=1,
    output led_n,
    output reg pal,
    output [3:0] red,green,blue,
    output hs,vs,hblank,vblank,ce_pixel,interlace,field,
    output [1:0] resolution,
    output [15:0] audio_l,audio_r,
    output O_sdram_clk,O_sdram_cke,O_sdram_cs_n,O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n,
    output [10:0] O_sdram_addr,output [1:0] O_sdram_ba,output [3:0] O_sdram_dqm,
    inout [31:0] IO_sdram_dq
);
    wire [11:0] buttons1,buttons2,joy1,joy2;
    nano_snes #(.FREQ_HZ(FREQ_HZ)) pads(.clk(clk_md),.reset_n(reset_n),.data1(snes_data1),.data2(snes_data2),
        .latch(snes_latch),.clock(snes_clock),.buttons1(buttons1),.buttons2(buttons2),.joy1(joy1),.joy2(joy2));
    reg [15:0] ms,ms_div;
    reg button_meta,button_sync;
    // SNES Select (bit 2) + Down (bit 5), together on either controller.
    // Return as soon as a complete pad sample contains both buttons.
    wire warm_request=button_sync || (buttons1&12'h024)==12'h024 || (buttons2&12'h024)==12'h024;
    always @(posedge clk_md)begin
        button_meta<=menu_button;button_sync<=button_meta;
        if(!reset_n)begin ms<=0;ms_div<=0;button_meta<=0;button_sync<=0;end
        else if(ms_div==FREQ_HZ/1000-1)begin
            ms_div<=0;ms<=ms+1'b1;
        end else ms_div<=ms_div+1'b1;
    end
    wire [24:1] mem_addr;
    wire [15:0] mem_wdata;
    reg [15:0] mem_data;
    wire mem_we,mem_req;
    wire [1:0] mem_be;
    reg mem_ack;
    reg running,loading,loader_mode,cart_bank;
    reg [23:0] rom_bytes;
    wire [24:1] rom_size=loader_mode?24'h008000:{1'b0,rom_bytes[23:1]};
    reg [13:0] boot_addr;
    wire [31:0] boot_data;
    reg boot_copy;
    reg [22:1] ram_addr;
    reg [15:0] ram_wdata;
    wire [15:0] ram_rdata;
    reg ram_req,ram_we,ram_valid;
    reg [1:0] ram_be;
    wire ram_ack,ram_ready,address_error;
    localparam INIT=0,FETCH=1,FETCH_WAIT=2,COPY_LO=3,COPY_HI=4,CLEAR=5,RUN=6,
        MEMORY_WAIT=7,SPI_START=8,SPI_WAIT=9,ZERO_START=11,ZERO_WAIT=12,RELEASE=13,DMA_MEMORY=14;
    reg [3:0] state;
    // Present an ordinary game read to the SDRAM on the same edge the
    // player accepts it. The registered request then holds it through any
    // refresh or other wait. Device accesses and posted writes use the FSM.
    wire work_ram = !mem_addr[24] && mem_addr[23:16] == 8'h80;
    wire save_ram = !mem_addr[24] && mem_addr[23:17] == 7'h41;
    wire cartridge = mem_addr[24:20] < 7;
    wire [22:1] game_addr = work_ram ? {7'h7f,mem_addr[15:1]} :
                            save_ram ? {6'h3e,mem_addr[16:1]} : mem_addr[22:1];
    wire start_read = state == RUN && !loader_mode && !warm_request && !mem_we &&
                      mem_req != mem_ack && (work_ram || save_ram || cartridge);
    nano_sdram #(.FREQ_HZ(FREQ_HZ)) ram(.clk(clk_md),.clk_sdram(clk_sdram),.reset_n(reset_n),
        .addr(start_read ? game_addr : ram_addr),.addr_valid(start_read || ram_valid),
        .wdata(ram_wdata),.we(!start_read && ram_we),.be(ram_be),.req(start_read ? !ram_ack : ram_req),
        .ack(ram_ack),.rdata(ram_rdata),.ready(ram_ready),.address_error(address_error),
        .O_sdram_clk(O_sdram_clk),.O_sdram_cke(O_sdram_cke),.O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_ras_n(O_sdram_ras_n),.O_sdram_cas_n(O_sdram_cas_n),.O_sdram_wen_n(O_sdram_wen_n),
        .O_sdram_addr(O_sdram_addr),.O_sdram_ba(O_sdram_ba),.O_sdram_dqm(O_sdram_dqm),.IO_sdram_dq(IO_sdram_dq));
    reg spi_start,spi_slow;
    reg sector_dma;
    reg [8:0] sector_byte;
    reg [6:0] dma_page;
    reg [7:0] sector_high;
    reg [7:0] spi_tx;
    wire spi_busy;
    wire [7:0] spi_rx;
    wire spi_clk,spi_mosi;
    // Share the existing byte engine; each device gets clocks only while
    // selected. The SD driver still emits startup clocks with both CS high.
    wire flash_selected=!flash_cs_n;
    assign sd_clk=spi_clk && !flash_selected;
    assign flash_clk=spi_clk && flash_selected;
    assign sd_mosi=spi_mosi;
    assign flash_mosi=spi_mosi;
    nano_spi #(.FAST_DATA(1'b1)) spi(.clk(clk_md),.reset_n(reset_n),.start(spi_start),.slow(spi_slow),.tx(spi_tx),
        .miso(flash_selected?flash_miso:sd_miso),.sclk(spi_clk),.mosi(spi_mosi),.busy(spi_busy),.rx(spi_rx));
    assign led_n=~(running&&!loader_mode) | address_error;
    // A completed read can reach the console on this edge. On a write,
    // the request, byte enables and data are already retained in ram_*.
    // Keep the port occupied until the physical write has completed.
    wire read_complete = state == MEMORY_WAIT && !ram_we && ram_req == ram_ack;
    megadrive20k_core core(.clk_md(clk_md),.clk_z80(clk_z80),.reset_n(reset_n&&running),.loading(loading),.pal(pal),
        .joy(joy1),.joy2(joy2),.rom_size(rom_size),.loader_mode(loader_mode),
        .boot_copy(boot_copy),.boot_addr(boot_addr),.boot_data(boot_data),
        .mem_addr(mem_addr),.mem_wdata(mem_wdata),.mem_data(read_complete ? ram_rdata : mem_data),.mem_we(mem_we),.mem_be(mem_be),.mem_req(mem_req),.mem_ack(read_complete ? mem_req : mem_ack),
        .red(red),.green(green),.blue(blue),.hs(hs),.vs(vs),.hblank(hblank),.vblank(vblank),.ce_pixel(ce_pixel),
        .interlace(interlace),.field(field),.resolution(resolution),.audio_l(audio_l),.audio_r(audio_r));
    reg [31:0] copy_data;
    reg [14:0] clear_count;
    reg [1:0] zero_bank;
    always @(posedge clk_md)begin
        spi_start<=0;
        if(!reset_n)begin
            state<=INIT;running<=0;loading<=0;loader_mode<=1;cart_bank<=0;rom_bytes<=0;pal<=0;
            mem_ack<=0;mem_data<=0;ram_req<=0;ram_addr<=0;ram_wdata<=0;ram_we<=0;ram_valid<=1;ram_be<=3;
            boot_copy<=1;boot_addr<=0;copy_data<=0;clear_count<=0;sd_cs_n<=1;spi_slow<=1;spi_tx<=255;
            zero_bank<=0;
            flash_cs_n<=1;reconfig_n<=1;
            sector_dma<=0;sector_byte<=0;sector_high<=0;dma_page<=7'h7f;
        end else case(state)
            INIT: if(ram_ready)state<=FETCH;
            FETCH:state<=FETCH_WAIT;
            FETCH_WAIT:begin
                copy_data<=boot_data;ram_addr<={7'h7e,boot_addr,1'b0};ram_wdata<=boot_data[15:0];ram_we<=1;ram_be<=3;
                ram_req<=~ram_ack;state<=COPY_LO;
            end
            COPY_LO:if(ram_req==ram_ack)begin ram_addr<=ram_addr+1'b1;ram_wdata<=copy_data[31:16];ram_req<=~ram_ack;state<=COPY_HI;end
            COPY_HI:if(ram_req==ram_ack)begin
                if(&boot_addr)begin boot_copy<=0;loading<=1;clear_count<=0;state<=CLEAR;end
                else begin boot_addr<=boot_addr+1'b1;state<=FETCH;end
            end
            CLEAR:begin
                mem_ack<=mem_req;
                if(&clear_count[13:0])begin loading<=0;state<=RELEASE;end
                else clear_count<=clear_count+1'b1;
            end
            RELEASE:begin running<=1;state<=RUN;end
            RUN:if(warm_request && !loader_mode)begin
                running<=0;loading<=1;loader_mode<=1;pal<=0;clear_count<=0;state<=CLEAR;
            end else if(mem_req!=mem_ack)begin
                if(mem_addr[24] && mem_addr[23:8]==16'ha140)begin
                    mem_data<=0;mem_ack<=mem_req;
                    case(mem_addr[5:1])
                        0:if(mem_we)begin spi_tx<=mem_wdata[7:0];spi_start<=1;state<=SPI_START;mem_ack<=mem_ack;end
                          else mem_data<={8'b0,spi_rx};
                        1:if(mem_we)begin sd_cs_n<=mem_wdata[0];spi_slow<=mem_wdata[1];end
                        2:mem_data<={4'b0,buttons1};
                        3:mem_data<=ms;
                        12:mem_data<={4'b0,buttons2};
                        13:if(mem_we && loader_mode)begin flash_cs_n<=mem_wdata[0];sd_cs_n<=1;spi_slow<=0;end
                           else mem_data<={15'b0,flash_cs_n};
                        14:if(mem_we && loader_mode && flash_cs_n && sd_cs_n && mem_wdata==16'hc020)reconfig_n<=0;
                        4:if(mem_we)rom_bytes[23:16]<=mem_wdata[7:0];
                        5:if(mem_we)rom_bytes[15:0]<=mem_wdata;
                        6:if(mem_we)cart_bank<=mem_wdata[0];else mem_data<={15'b0,cart_bank};
                        7:if(mem_we && mem_wdata==16'h4d44)begin
                            running<=0;loading<=1;loader_mode<=0;clear_count<=0;zero_bank<=0;state<=ZERO_START;
                        end
                        9:if(mem_we)pal<=mem_wdata[0];
                        10:if(mem_we)begin
                            // Read one complete SD sector directly into SDRAM.
                            // Firmware selects work RAM or the cartridge page.
                            // The CPU's MMIO cycle waits until all 512 bytes land.
                            ram_addr<={dma_page,mem_wdata[15:1]};ram_valid<=1;ram_we<=1;ram_be<=3;
                            sector_dma<=1;sector_byte<=0;spi_tx<=255;spi_start<=1;
                            state<=SPI_START;mem_ack<=mem_ack;
                        end
                        11:if(mem_we)dma_page<=mem_wdata[6:0];
                        default:mem_data<=16'hffff;
                    endcase
                end else begin
                    ram_valid<=1;ram_we<=mem_we;ram_be<=mem_be;ram_wdata<=mem_wdata;
                    if(mem_addr[24] && mem_addr[23:20]==8)ram_addr<={3'b111,mem_addr[19:1]}; // index 700000-7BFFFF
                    else if(work_ram || save_ram)ram_addr<=game_addr;
                    else if(loader_mode && mem_addr[23:16]==0)ram_addr<={7'h7e,mem_addr[15:1]};
                    else if(loader_mode && mem_addr[23:22]==1)ram_addr<={cart_bank,mem_addr[21:1]};
                    else if(cartridge)ram_addr<=game_addr;
                    else begin ram_addr<=0;ram_valid<=0;end
                    if (mem_we) mem_ack<=mem_req;
                    ram_req<=~ram_ack;state<=MEMORY_WAIT;
                end
            end
            MEMORY_WAIT:if(ram_req==ram_ack)begin
                if (!ram_we) begin mem_data<=ram_rdata; mem_ack<=mem_req; end
                state<=RUN;
            end
            SPI_START:if(spi_busy)state<=SPI_WAIT;
            SPI_WAIT:if(!spi_busy)begin
                if(!sector_dma)begin mem_ack<=mem_req;state<=RUN;end
                else if(!sector_byte[0])begin
                    sector_high<=spi_rx;sector_byte<=sector_byte+1'b1;spi_start<=1;state<=SPI_START;
                end else begin ram_wdata<={sector_high,spi_rx};ram_req<=~ram_ack;state<=DMA_MEMORY;end
            end
            DMA_MEMORY:if(ram_req==ram_ack)begin
                if(&sector_byte)begin sector_dma<=0;mem_ack<=mem_req;state<=RUN;end
                else begin ram_addr<=ram_addr+1'b1;sector_byte<=sector_byte+1'b1;spi_start<=1;state<=SPI_START;end
            end
            ZERO_START:begin
                ram_addr<={zero_bank==2?7'h7f:zero_bank==1?7'h7d:7'h7c,clear_count};
                ram_we<=1;ram_be<=3;ram_wdata<=zero_bank==2?16'h0000:16'hffff;ram_req<=~ram_ack;state<=ZERO_WAIT;
            end
            ZERO_WAIT:if(ram_req==ram_ack)begin
                clear_count<=clear_count+1'b1;
                if(&clear_count)begin
                    if(zero_bank==2)begin clear_count<=0;state<=CLEAR;end
                    else begin zero_bank<=zero_bank+1'b1;state<=ZERO_START;end
                end else state<=ZERO_START;
            end
            default:state<=INIT;
        endcase
    end
endmodule
