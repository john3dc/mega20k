// SPDX-License-Identifier: GPL-3.0-or-later
// 8 MiB / 32-bit embedded SDRAM on GW2AR-18C: 4 banks, 2048 rows,
// 256 columns. 16-bit toggle request port, one outstanding transaction.
// Interface/address geometry reference: nand2mario's NESTang SDRAM controller
// Sipeed TangNano-20K-example, e23949a, nestang/src/sdram.v.
// Independent FSM: latched requests, defined reset and mandatory refresh.
// Timing fixed for <=54 MHz: CL2, tRCD>=1, tRP>=1, tRFC>=4 cycles.
// clk_sdram must have its rising edge half a cycle AFTER clk's rising edge.
// Host and controller reset together; host holds request/data until ack.
// Retain the complete 32-bit read word for repeated/adjacent 16-bit reads.
// Every accepted write invalidates it, including SD DMA and partial writes.
// Refresh keeps priority over hits as well as misses; command timing is unchanged.
module nano_sdram #(
    parameter FREQ_HZ=54000000,
    parameter INIT_CYCLES=FREQ_HZ/5000,       // >=200 us
    parameter REFRESH_CYCLES=FREQ_HZ/133334,  // ~7.5 us, ample 15.6 us margin
    parameter READ_BUFFER=1
)(
    input clk, clk_sdram, reset_n,
    input [22:1] addr,
    input addr_valid,
    input [15:0] wdata,
    input we,
    input [1:0] be,
    input req,
    output reg ack,
    output reg [15:0] rdata,
    output reg ready,
    output reg address_error,
    output O_sdram_clk, O_sdram_cke, O_sdram_cs_n,
    output reg O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n,
    output reg [10:0] O_sdram_addr,
    output reg [1:0] O_sdram_ba,
    output reg [3:0] O_sdram_dqm,
    inout [31:0] IO_sdram_dq
);
    localparam POWER=0, INIT_R1=1, INIT_R2=2, INIT_MODE=3,
               INIT_DONE=4, IDLE=5, COLUMN=6, ACCESS=7, REFRESH=8;
    reg [3:0] state;
    reg [$clog2(INIT_CYCLES+1)-1:0] power_count;
    reg [$clog2(REFRESH_CYCLES+1)-1:0] refresh_count;
    // Use the idle bus time after an acknowledged access for refresh.
    // If requests remain continuous, the absolute deadline still wins.
    localparam REFRESH_MARGIN = REFRESH_CYCLES > 64 ? 64 : REFRESH_CYCLES/4;
    reg just_completed;
    wire refresh_in_gap = just_completed && req == ack &&
                          refresh_count >= REFRESH_CYCLES - REFRESH_MARGIN;
    reg [2:0] wait_count;
    reg [8:0] column_half;
    reg [15:0] saved_data;
    reg [1:0] saved_be;
    reg saved_we, saved_req, dq_drive;
    reg read_valid;
    reg [22:2] read_tag;
    reg [31:0] read_word;
    assign O_sdram_clk = clk_sdram;
    assign O_sdram_cke = 1'b1;
    assign O_sdram_cs_n = 1'b0;
    assign IO_sdram_dq = dq_drive ? {saved_data,saved_data} : 32'bz;
    always @(posedge clk) begin
        // Commands and data are driven for the following SDRAM rising edge.
        {O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n} <= 3'b111;
        dq_drive <= 0;
        just_completed <= 0;
        if (refresh_count < REFRESH_CYCLES) refresh_count <= refresh_count+1'b1;
        if (wait_count != 0) wait_count <= wait_count-1'b1;
        if (!reset_n) begin
            state<=POWER; power_count<=0; refresh_count<=0; wait_count<=0;
            ready<=0; ack<=0; rdata<=0; address_error<=0;
            O_sdram_addr<=0; O_sdram_ba<=0; O_sdram_dqm<=0;
            column_half<=0; saved_data<=0; saved_be<=0; saved_we<=0; saved_req<=0;
            read_valid<=0;
        end else case(state)
            POWER: if (power_count==INIT_CYCLES-1) begin
                {O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n}<=3'b010; // precharge all
                O_sdram_addr<=11'h400;
                state<=INIT_R1;
            end else power_count<=power_count+1'b1;
            INIT_R1: begin
                {O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n}<=3'b001;
                wait_count<=3; state<=INIT_R2;
            end
            INIT_R2: if(wait_count==0) begin
                {O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n}<=3'b001;
                wait_count<=3; state<=INIT_MODE;
            end
            INIT_MODE: if(wait_count==0) begin
                {O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n}<=3'b000;
                O_sdram_addr<=11'h020; // sequential, BL1, CAS2
                O_sdram_ba<=0;
                wait_count<=1; state<=INIT_DONE;
            end
            INIT_DONE: if(wait_count==0) begin
                state<=IDLE; ready<=1; refresh_count<=0;
            end
            IDLE: if(refresh_count==REFRESH_CYCLES || refresh_in_gap) begin
                // Refresh wins over every request, including continuous load.
                {O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n}<=3'b001;
                refresh_count<=0; wait_count<=3; state<=REFRESH;
            end else if(req!=ack) begin
                if(!addr_valid) begin
                    ack<=req; rdata<=16'hffff; address_error<=1;
                end else if(READ_BUFFER && read_valid && !we && read_tag==addr[22:2]) begin
                    rdata<=addr[1] ? read_word[31:16] : read_word[15:0];
                    ack<=req; just_completed<=1;
                end else begin
                    // The single port observes every writer. Invalidate before
                    // issuing writes, so no byte mask can leave a stale hit.
                    read_valid<=0;
                    read_tag<=addr[22:2];
                    column_half<=addr[9:1]; saved_data<=wdata; saved_be<=be;
                    saved_we<=we; saved_req<=req;
                    O_sdram_ba<=addr[22:21]; O_sdram_addr<=addr[20:10];
                    {O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n}<=3'b011; // ACT
                    state<=COLUMN;
                end
            end
            COLUMN: begin
                {O_sdram_ras_n,O_sdram_cas_n,O_sdram_wen_n}<=saved_we ? 3'b100 : 3'b101;
                O_sdram_addr<={3'b100,column_half[8:1]}; // A10 auto-precharge
                O_sdram_dqm<=saved_we ? (column_half[0] ? {~saved_be,2'b11} : {2'b11,~saved_be}) : 4'b0;
                dq_drive<=saved_we;
                wait_count<=2; state<=ACCESS;
            end
            ACCESS: if(wait_count==0) begin
                // CL2 data arrives after the intervening SDRAM edge.
                // Writes have tWR+tRP=3 cycles before another command.
                if(!saved_we) begin
                    rdata<=column_half[0] ? IO_sdram_dq[31:16] : IO_sdram_dq[15:0];
                    read_word<=IO_sdram_dq;
                    read_valid<=READ_BUFFER;
                end
                ack<=saved_req; just_completed<=1; state<=IDLE;
            end
            REFRESH: if(wait_count==0) state<=IDLE;
            default: state<=POWER;
        endcase
    end
endmodule
