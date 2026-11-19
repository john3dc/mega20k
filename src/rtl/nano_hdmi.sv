// SPDX-License-Identifier: GPL-3.0-or-later
module nano_hdmi(input clk_pixel,clk_pixel_x5,reset,pal,frame_reset,
    input [9:0] line_width,frame_y,input [23:0] rgb,input audio_tick,input [15:0] audio_l,audio_r,
    output [9:0] cx,cy,output [2:0] tmds,output tmds_clock);
    wire [15:0] samples[1:0];
    assign samples[0]=audio_l;assign samples[1]=audio_r;
    hdmi #(.VIDEO_ID_CODE(0),.AUDIO_RATE(48000),.VENDOR_NAME("NanoMD  "),
        .PRODUCT_DESCRIPTION("Mega Drive      "),.SOURCE_DEVICE_INFORMATION(8'h08)) hdmi(
        .clk_pixel(clk_pixel),.clk_pixel_x5(clk_pixel_x5),.clk_audio(audio_tick),.reset(reset),
        .pal(pal),.line_width(line_width),.frame_reset(frame_reset),.frame_y(frame_y),.rgb(rgb),.audio_sample_word(samples),
        .cx(cx),.cy(cy),.tmds(tmds),.tmds_clock(tmds_clock),.frame_width(),.frame_height(),.screen_width(),.screen_height());
endmodule
