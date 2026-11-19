// SPDX-License-Identifier: GPL-3.0-or-later
// Optional Gowin storage implementation for JT12's single-output shift chain.
// Uninitialized data remains unspecified until the original chain would fill.
module jt12_sh_ring #(parameter width=5, stages=24, INITIALIZE=0, INIT_BIT=1'b0)(
    input clk, clk_en,
    input [width-1:0] din,
    output [width-1:0] drop
);
    generate if (stages < 3) begin : short_chain
        reg [width-1:0] data [0:stages-1];
        integer i;
        initial if (INITIALIZE)
            for (i=0; i<stages; i=i+1) data[i] = {width{INIT_BIT}};
        always @(posedge clk) if (clk_en) begin
            data[0] <= din;
            for (i=1; i<stages; i=i+1) data[i] <= data[i-1];
        end
        assign drop = data[stages-1];
    end else begin : ring
        localparam AW = $clog2(stages);
        (* ram_style = "distributed" *) reg [width-1:0] mem [0:stages-1];
        reg [AW-1:0] oldest = 0;
        integer i;
        initial if (INITIALIZE)
            for (i=0; i<stages; i=i+1) mem[i] = {width{INIT_BIT}};
        always @(posedge clk) if (clk_en) begin
            mem[oldest] <= din;
            oldest <= oldest == stages-1 ? 0 : oldest + 1'b1;
        end
        assign drop = mem[oldest];
    end endgenerate
endmodule

// The pinned MDTang jt12_sh_rst initializes storage but ignores its rst pin.
// Preserve that exact behavior; this wrapper must not be used unreviewed with
// a different JT12 revision whose reset pin resets the complete chain.
module jt12_sh_rst_ring #(parameter width=5, stages=32, rstval=1'b0)(
    input rst, clk, clk_en,
    input [width-1:0] din,
    output [width-1:0] drop
);
    jt12_sh_ring #(.width(width), .stages(stages), .INITIALIZE(1), .INIT_BIT(rstval))
        storage(.clk(clk), .clk_en(clk_en), .din(din), .drop(drop));
endmodule
