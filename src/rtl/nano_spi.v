// SPDX-License-Identifier: GPL-3.0-or-later
// Mode 0. At 54 MHz initialization runs at 397 kHz and data at 6.75 or 13.5 MHz.
module nano_spi #(parameter FAST_DATA = 1'b0)(input clk,reset_n,start,slow,input [7:0] tx,
                input miso,output reg sclk,mosi,busy,output reg [7:0] rx);
    reg [6:0] count;
    reg [3:0] edge_no;
    reg [7:0] shift;
    reg [1:0] miso_sync;
    localparam [6:0] DATA_RELOAD = FAST_DATA ? 7'd1 : 7'd3;
    wire [6:0] reload = slow ? 7'd67 : DATA_RELOAD;
    wire [7:0] shifted = {shift[6:0],miso_sync[1]};
    // At clk/4 the rising-edge MISO sample reaches the shifter on the
    // falling edge. Use that updated word for MOSI and final-byte readback.
    wire [7:0] falling_word = FAST_DATA ? shifted : shift;
    always @(posedge clk) begin
        miso_sync<={miso_sync[0],miso};
        if(!reset_n) begin sclk<=0;mosi<=1;busy<=0;rx<=255;count<=0;edge_no<=0;shift<=255;miso_sync<=3;end
        else if(!busy) begin
            sclk<=0;
            if(start)begin busy<=1;mosi<=tx[7];shift<=tx;count<=reload;edge_no<=0;end
        end else if(count==0)begin
            count<=reload;sclk<=~sclk;edge_no<=edge_no+1'b1;
            if(sclk==FAST_DATA)shift<=shifted;
            if(sclk)begin
                mosi<=falling_word[7];
                if(edge_no==15)begin busy<=0;rx<=falling_word;end
            end
        end else count<=count-1'b1;
    end
endmodule
