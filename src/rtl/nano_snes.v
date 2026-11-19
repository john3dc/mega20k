// SPDX-License-Identifier: GPL-3.0-or-later
// NESTang SNES bit order. Conservative 12 us clock halves give the physical
// data line additional settling time. Poll every 4 ms by default.
module nano_snes #(parameter FREQ_HZ=54000000, parameter HALF_US=12,
                   parameter POLL_US=4000, parameter FILTER_INPUT=0)(
    input clk, reset_n, data1, data2,
    output reg latch, clock,
    output reg [11:0] buttons1, buttons2,
    output [11:0] joy1, joy2
);
    function integer gcd(input integer a, input integer b);
        integer t;
        begin
            while(b!=0) begin t=a%b;a=b;b=t;end
            gcd=a;
        end
    endfunction
    localparam TICK_GCD=gcd(FREQ_HZ,1000000);
    localparam TICK_DEN=FREQ_HZ/TICK_GCD, TICK_INC=1000000/TICK_GCD;
    reg [1:0] sync1,sync2;
    // Fractional divider also gives correct microseconds at 21.6 MHz (SNES).
    reg [$clog2(TICK_DEN+TICK_INC)-1:0] us_accum;
    reg [$clog2(POLL_US)-1:0] us;
    reg [15:0] shift1,shift2;
    reg [11:0] previous1,previous2;
    // Ordinary SNES pads send four released bits after their 12 buttons.
    // A missed latch/stuck-low line must not become an all-buttons chord.
    wire [11:0] sample1=shift1[15:12]==0 ? shift1[11:0] : 12'b0;
    wire [11:0] sample2=shift2[15:12]==0 ? shift2[11:0] : 12'b0;
    reg [4:0] bitno;
    reg [$clog2(2*HALF_US)-1:0] phase;
    always @(posedge clk) begin
        sync1<={sync1[0],data1}; sync2<={sync2[0],data2};
        if(!reset_n) begin
            sync1<=3;sync2<=3;us_accum<=0;us<=0;latch<=0;clock<=1;
            buttons1<=0;buttons2<=0;shift1<=0;shift2<=0;bitno<=0;phase<=0;
            previous1<=0;previous2<=0;
        end else if(us_accum>=TICK_DEN-TICK_INC) begin
            us_accum<=us_accum+TICK_INC-TICK_DEN;
            us<=us==POLL_US-1?0:us+1'b1;
            if(us==0) begin latch<=1;clock<=1;bitno<=0;phase<=0;end
            if(us==2*HALF_US) begin latch<=0;phase<=0;end
            if(us>2*HALF_US && bitno<16) begin
                if(phase==HALF_US-1) begin
                    // Sample on the falling edge; the pad shifts on rising.
                    shift1[bitno]<=~sync1[1];shift2[bitno]<=~sync2[1];clock<=0;
                end
                if(phase==2*HALF_US-1) begin clock<=1;phase<=0;bitno<=bitno+1'b1;end
                else phase<=phase+1'b1;
            end
            if(us==34*HALF_US+2) begin
                // Confirm each press in two consecutive valid polls (4 ms
                // apart by default); release immediately. This also rejects
                // a one-poll false reset chord with an otherwise valid tail.
                previous1<=sample1;previous2<=sample2;
                buttons1<=FILTER_INPUT ? sample1 & previous1 : shift1[11:0];
                buttons2<=FILTER_INPUT ? sample2 & previous2 : shift2[11:0];
            end
        end else us_accum<=us_accum+TICK_INC;
    end
    // MD bits: Z Y X Mode Start C B A Up Down Left Right.
    // Familiar NESTang/MDTang face mapping: SNES Y/B/A -> MD A/B/C.
    assign joy1={buttons1[11],buttons1[10],buttons1[9],buttons1[2],buttons1[3],
                 buttons1[8],buttons1[0],buttons1[1],buttons1[4],buttons1[5],buttons1[6],buttons1[7]};
    assign joy2={buttons2[11],buttons2[10],buttons2[9],buttons2[2],buttons2[3],
                 buttons2[8],buttons2[0],buttons2[1],buttons2[4],buttons2[5],buttons2[6],buttons2[7]};
    // synthesis translate_off
    initial begin
        if(FREQ_HZ<1000000 || HALF_US<1 || POLL_US<=34*HALF_US+3)
            $fatal(1,"Invalid nano_snes timing parameters");
    end
    // synthesis translate_on
endmodule
