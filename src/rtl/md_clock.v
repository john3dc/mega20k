// 107.3863636 MHz reference. Make the console and the fixed HDMI raster
// complete exactly one field together without changing CPU or VDP divisors.
module md_clock(
    input clk_2x, locked, pal,
    output reg clk_md = 0,
    output inhibit
);
    reg pal_meta = 0, pal_sync = 0, region = 0;
    reg [20:0] phase = 0;
    reg extend_low = 0;
    // NTSC: 855 x 527 HDMI pixels per 3420 x 262 console clocks.
    // PAL:  872 x 623 HDMI pixels per 3420 x 313 console clocks.
    wire [20:0] increment = pal_sync ? 21'd21733 : 21'd1;
    wire [20:0] threshold = pal_sync ? 21'd1155773 : 21'd46111;
    assign inhibit = extend_low;
    always @(posedge clk_2x) begin
        pal_meta <= pal;
        pal_sync <= pal_meta;
    end
    always @(posedge clk_2x) begin
        if (!locked) begin
            phase <= 0;
            extend_low <= 0;
            clk_md <= 0;
            region <= 0;
        end else begin
            clk_md <= !clk_md && !extend_low;
            extend_low <= 0;
            region <= pal_sync;
            if (pal_sync != region) phase <= 0;
            else if (clk_md) begin
                if (phase >= threshold) begin
                    phase <= phase - threshold;
                    extend_low <= 1;
                end else phase <= phase + increment;
            end
        end
    end
endmodule
