// SPDX-License-Identifier: GPL-3.0-or-later
// Area-oriented replacement for JT12's multi-stage reconstruction mixer.
// Deliberately NOT bit-equivalent: FM + PSG*8 saturates, then a one-pole
// low-pass runs at MCLK. At 53.693 MHz its -3 dB corner is about 8.35 kHz.
// Ten fractional bits retain quiet signals. No clock-rate conversion or RAM.
module jt12_genmix_small(
    input rst, clk,
    input signed [15:0] fm_left, fm_right,
    input signed [10:0] psg_snd,
    input fm_en, psg_en,
    output signed [15:0] snd_left, snd_right
);
    wire signed [16:0] psg = psg_en ? {{3{psg_snd[10]}}, psg_snd, 3'b0} : 17'sd0;
    wire signed [16:0] mix_l = (fm_en ? {fm_left[15],fm_left} : 17'sd0) + psg;
    wire signed [16:0] mix_r = (fm_en ? {fm_right[15],fm_right} : 17'sd0) + psg;
    function [15:0] saturate(input signed [16:0] x);
        saturate = x > 17'sd32767 ? 16'h7fff : x < -17'sd32768 ? 16'h8000 : x[15:0];
    endfunction
    wire signed [15:0] target_l = saturate(mix_l), target_r = saturate(mix_r);
    reg signed [25:0] acc_l, acc_r;
    wire signed [26:0] delta_l = $signed({target_l[15],target_l,10'b0}) - $signed({acc_l[25],acc_l});
    wire signed [26:0] delta_r = $signed({target_r[15],target_r,10'b0}) - $signed({acc_r[25],acc_r});
    always @(posedge clk) begin
        if (rst) begin acc_l <= 0; acc_r <= 0; end
        else begin
            acc_l <= acc_l + (delta_l >>> 10);
            acc_r <= acc_r + (delta_r >>> 10);
        end
    end
    assign snd_left = acc_l[25:10];
    assign snd_right = acc_r[25:10];
endmodule
