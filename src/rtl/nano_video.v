// SPDX-License-Identifier: GPL-3.0-or-later
// Three complete 320 x 12 scanlines fit into one 1024 x 12 block RAM.
// HDMI reads each row twice at a constant pixel, line and field cadence.
module nano_video(
    input clk_md,clk_pixel,clk_pixel_x5,reset_n,pal,
    input [3:0] red,green,blue,
    input ce_pixel,hblank,vblank,input [1:0] resolution,
    input [15:0] audio_l,audio_r,
    output [2:0] tmds,output tmds_clock
);
    (* ram_style="block", no_rw_check *) reg [11:0] lines[0:1023];
    function [9:0] line_address(input [1:0] bank, input [8:0] x);
        // Each bank occupies five 64-pixel groups.
        reg [3:0] group_index;
        begin
            group_index = {bank,2'b00} + bank + x[8:6];
            line_address = {group_index,x[5:0]};
        end
    endfunction
    function [1:0] next_bank(input [1:0] bank);
        next_bank = bank == 2 ? 0 : bank+1'b1;
    endfunction
    reg [8:0] wx;
    reg [1:0] wb;
    reg active,frame_pending,frame_toggle,first_line,second_line;
    reg line_vblank=1;
    always @(posedge clk_md) if (!reset_n) line_vblank<=1;
        else if(ce_pixel && hblank) line_vblank<=vblank;
    wire [1:0] write_bank=frame_pending ? 2'd0 : wb;
    wire [8:0] write_x=active ? wx : 0;
    always @(posedge clk_md) begin
        if (ce_pixel && !hblank && !line_vblank && write_x<320)
            lines[line_address(write_bank,write_x)]<={red,green,blue};
        if (!reset_n) begin
            wx<=0; wb<=0; active<=0; frame_pending<=1; frame_toggle<=0;
            first_line<=0; second_line<=0;
        end else if (ce_pixel) begin
            if (line_vblank) frame_pending<=1;
            if (!hblank && !line_vblank) begin
                active<=1; wx<=write_x+1'b1;
                if (frame_pending) begin wb<=0; frame_pending<=0; first_line<=1; end
                // PAL scanout is slightly slower than the VDP line writer.
                if (pal && first_line && write_x==(resolution[0]?224:180))
                    frame_toggle<=~frame_toggle;
            end else if (active) begin
                active<=0; wx<=0; wb<=next_bank(wb);
                first_line<=0; second_line<=first_line;
                // NTSC scanout is slightly faster. Start with two rows available.
                if (!pal && second_line) frame_toggle<=~frame_toggle;
            end
        end
    end
    wire [9:0] cx,cy;
    reg [2:0] frame_sync;
    reg [2:0] mode_meta,mode_sync,video_mode;
    always @(posedge clk_pixel) begin
        mode_meta<={pal,resolution};
        mode_sync<=mode_meta;
    end
    wire pal_video=video_mode[2];
    wire [9:0] line_width=pal_video ? 10'd872 : 10'd855;
    wire [9:0] field_height=pal_video ? 10'd623 : 10'd527;
    wire line_end=cx==line_width-1'b1;
    wire [9:0] top=pal_video?(video_mode[1]?10'd48:10'd64):(video_mode[1]?10'd0:10'd16);
    wire [9:0] left=video_mode[0]?10'd40:10'd104;
    wire [9:0] width=video_mode[0]?10'd640:10'd512;
    wire [9:0] height=video_mode[1]?10'd480:10'd448;
    wire [9:0] before_top=top==0 ? field_height-1'b1 : top-1'b1;
    wire [9:0] two_before_top=before_top==0 ? field_height-1'b1 : before_top-1'b1;
    reg locked,pending;
    reg [1:0] rb;
    wire new_source_frame=frame_sync[2]!=frame_sync[1];
    // Permit synchronization uncertainty at a line edge. Once acquired,
    // the two exact field rates allow both HDMI counters to run freely.
    wire aligned=cy==before_top || cy==two_before_top || cy==top;
    wire frame_reset=pending && line_end;
    wire visible=locked && cx>=left && cx<left+width && cy>=top && cy<top+height;
    wire [8:0] rx=(cx-left)>>1;
    reg [11:0] pixel;
    always @(posedge clk_pixel) begin
        frame_sync<={frame_sync[1:0],frame_toggle};
        if (!reset_n) begin
            frame_sync<=0; pending<=0; locked<=0; rb<=0; pixel<=0; video_mode<=0;
        end else begin
            if (new_source_frame && (!locked || !aligned)) begin pending<=1; locked<=0; end
            if (frame_reset) begin pending<=0; locked<=1; end
            if (line_end && (mode_sync!=video_mode)) begin
                video_mode<=mode_sync; locked<=0; pending<=0;
            end
            if (frame_reset || (line_end && cy==before_top)) rb<=0;
            else if (line_end && cy>=top && cy<top+height && cy[0]) rb<=next_bank(rb);
            if (visible) pixel<=lines[line_address(rb,rx)];
            else pixel<=0;
        end
    end
    // Fractional 48 kHz pulse. Audio CTS measures the actual pixel clock.
    reg [10:0] audio_phase;
    reg audio_tick;
    reg [15:0] sample_l,sample_r;
    always @(posedge clk_pixel)begin
        audio_tick<=0;
        if(!reset_n)begin audio_phase<=0;sample_l<=0;sample_r<=0;end
        else if(audio_phase>=1125-2)begin
            audio_phase<=audio_phase-(1125-2);audio_tick<=1;sample_l<=audio_l;sample_r<=audio_r;
        end else audio_phase<=audio_phase+2;
    end
    // Packed wrapper keeps the board boundary compatible with Verilog tools.
    nano_hdmi encoder(.clk_pixel(clk_pixel),.clk_pixel_x5(clk_pixel_x5),.reset(!reset_n),.pal(pal_video),.line_width(line_width),
        .frame_reset(frame_reset),.frame_y(top),.rgb({pixel[11:8],pixel[11:8],pixel[7:4],pixel[7:4],pixel[3:0],pixel[3:0]}),
        .audio_tick(audio_tick),.audio_l(sample_l),.audio_r(sample_r),.cx(cx),.cy(cy),.tmds(tmds),.tmds_clock(tmds_clock));
endmodule
