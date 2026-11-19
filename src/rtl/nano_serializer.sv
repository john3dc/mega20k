// SPDX-License-Identifier: GPL-3.0-or-later
module serializer #(parameter NUM_CHANNELS=3,parameter real VIDEO_RATE=27000000)(
    input clk_pixel,clk_pixel_x5,reset,input [9:0] tmds_internal[NUM_CHANNELS-1:0],
    output [2:0] tmds,output tmds_clock);
    wire [9:0] symbols[2:0];
    assign symbols[0]=tmds_internal[0];assign symbols[1]=tmds_internal[1];assign symbols[2]=tmds_internal[2];
    wire [2:0] serial;
    assign tmds=serial;assign tmds_clock=clk_pixel;
    for(genvar i=0;i<3;i++)begin:lane
`ifdef VERILATOR
        reg [9:0] shift;
        reg [3:0] phase=0;
        always @(posedge clk_pixel_x5 or negedge clk_pixel_x5)begin
            if(reset)begin phase<=0;shift<=0;end
            else begin
                phase<=phase==9?0:phase+1'b1;
                if(phase==0)shift<=symbols[i];else shift<={1'b0,shift[9:1]};
            end
        end
        assign serial[i]=shift[0];
`else
        OSER10 ser(.PCLK(clk_pixel),.FCLK(clk_pixel_x5),.RESET(reset),.Q(serial[i]),
            .D0(symbols[i][0]),.D1(symbols[i][1]),.D2(symbols[i][2]),.D3(symbols[i][3]),.D4(symbols[i][4]),
            .D5(symbols[i][5]),.D6(symbols[i][6]),.D7(symbols[i][7]),.D8(symbols[i][8]),.D9(symbols[i][9]));
`endif
    end
endmodule
