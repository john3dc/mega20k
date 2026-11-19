// SPDX-License-Identifier: GPL-3.0-or-later
// Area-oriented scheduler around hdl-util's unchanged HDMI packet encoders.
// Three packet slots per 855-pixel line allow one stereo sample per packet.
// A four-entry LUTRAM FIFO covers the active-video interval; no sample blocks
// are copied between large register banks.
module packet_picker #(
    parameter int VIDEO_ID_CODE=0,parameter real VIDEO_RATE=27000000,
    parameter bit IT_CONTENT=1,parameter int AUDIO_BIT_WIDTH=16,AUDIO_RATE=48000,
    parameter bit [63:0] VENDOR_NAME=0,parameter bit [127:0] PRODUCT_DESCRIPTION=0,
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION=0
)(
    input clk_pixel,clk_audio,reset,video_field_end,packet_enable,
    input [4:0] packet_pixel_counter,
    input [AUDIO_BIT_WIDTH-1:0] audio_sample_word[1:0],
    output reg [23:0] header,output reg [55:0] sub[3:0]
);
    (* ram_style="distributed" *) reg [31:0] fifo[0:3];
    reg [2:0] wr=0,rd=0;
    reg audio_old=0;
    wire push=clk_audio&&!audio_old;
    wire full=(wr[2]!=rd[2])&&(wr[1:0]==rd[1:0]);
    wire empty=wr==rd;
    reg [31:0] sample;
    reg [7:0] frame_counter=0,packet_frame=0;
    reg [2:0] kind=0;
    reg [2:0] info_sent=0;
    wire acr_toggle;
    reg acr_seen=0;
    wire pop=packet_enable && acr_seen==acr_toggle && !empty && !video_field_end && !reset;
    always @(posedge clk_pixel)begin
        audio_old<=clk_audio;
        if(push && !full)fifo[wr[1:0]]<={audio_sample_word[1],audio_sample_word[0]};
        if(reset)begin wr<=0;rd<=0;audio_old<=0;kind<=0;info_sent<=0;acr_seen<=acr_toggle;frame_counter<=0;packet_frame<=0;end
        else begin
            if(push && !full)wr<=wr+1'b1;
            if(pop)begin
                sample<=fifo[rd[1:0]];rd<=rd+1'b1;packet_frame<=frame_counter;
                frame_counter<=frame_counter==191?0:frame_counter+1'b1;
            end
            if(video_field_end)begin info_sent<=0;kind<=0;end
            else if(packet_enable)begin
                if(acr_seen!=acr_toggle)begin kind<=1;acr_seen<=acr_toggle;end
                else if(!empty)kind<=2;
                else if(!info_sent[0])begin kind<=3;info_sent[0]<=1;end
                else if(!info_sent[1])begin kind<=4;info_sent[1]<=1;end
                else if(!info_sent[2])begin kind<=5;info_sent[2]<=1;end
                else kind<=0;
            end
        end
`ifdef VERILATOR
        if(!reset && push && full)$fatal(1,"HDMI audio FIFO overflow");
`endif
    end
    wire [23:0] h_acr,h_audio,h_ai,h_avi,h_spd;
    wire [55:0] s_acr[3:0],s_audio[3:0],s_ai[3:0],s_avi[3:0],s_spd[3:0];
    audio_clock_regeneration_packet #(.VIDEO_RATE(VIDEO_RATE),.AUDIO_RATE(AUDIO_RATE)) acr(
        .clk_pixel(clk_pixel),.clk_audio(clk_audio),.clk_audio_counter_wrap(acr_toggle),.header(h_acr),.sub(s_acr));
    wire [23:0] pcm[3:0][1:0];
    assign pcm[0][0]={sample[15:0],8'b0};assign pcm[0][1]={sample[31:16],8'b0};
    for(genvar i=1;i<4;i++)begin:unused_samples
        assign pcm[i][0]=0;assign pcm[i][1]=0;
    end
    audio_sample_packet #(.SAMPLING_FREQUENCY(4'b0010),.WORD_LENGTH(4'b0010)) audio_packet(
        .frame_counter(packet_frame),.valid_bit('{0,0,0,0}),.user_data_bit('{0,0,0,0}),
        .audio_sample_word(pcm),.audio_sample_word_present(4'b0001),.header(h_audio),.sub(s_audio));
    audio_info_frame ai(.header(h_ai),.sub(s_ai));
    auxiliary_video_information_info_frame #(.VIDEO_ID_CODE(7'(VIDEO_ID_CODE)),.IT_CONTENT(IT_CONTENT)) avi(.header(h_avi),.sub(s_avi));
    source_product_description_info_frame #(.VENDOR_NAME(VENDOR_NAME),.PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
        .SOURCE_DEVICE_INFORMATION(SOURCE_DEVICE_INFORMATION)) spd(.header(h_spd),.sub(s_spd));
    always_comb begin
        header=0;sub='{0,0,0,0};
        case(kind)
            1:begin header=h_acr;sub=s_acr;end
            2:begin header=h_audio;sub=s_audio;end
            3:begin header=h_ai;sub=s_ai;end
            4:begin header=h_avi;sub=s_avi;end
            5:begin header=h_spd;sub=s_spd;end
        endcase
    end
endmodule
