`timescale 1ns / 1ps

module pcm1808_in(
    input wire   sys_clk,
    input wire   sys_rst_n,
    input wire   audio_clk,
    input wire   audio_clk_locked,

    output reg   FMT,
    output reg   MD0,
    output reg   MD1,

    output wire  sclk,
    input  wire  bck,// sclk = 256*bck
    input  wire  lrck,//bck = 32*lrck
    input  wire  dout,

    output reg   audio_valid,
    output reg   audio_signal,
    output reg signed [31:0] audio_data
    );


//1.state_cnt == 0 配置阶段，先将MD0=1，MD1=1，FMT=0
//2.state_cnt == 1 等待阶段，等待一秒，等配置完毕
//3. state_cnt == 2 音频接收阶段，进行接收
localparam WAIT_TIME = 'd50_000_000;

assign sclk = audio_clk;


reg [7:0] state_cnt;
reg [63:0] config_wait_cnt;
reg [31:0] audio_data_buf;
reg [7:0]  audio_bit_cnt;//记录到哪个bit
reg [7:0]  audio_work_cnt;
reg i2s_delay;
reg lrck_reg0;
reg bck_reg0;
reg dout_reg0;
reg lrck_reg1;
reg bck_reg1;
reg dout_reg1;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        lrck_reg0 <= 0;
        bck_reg0 <= 0;
        dout_reg0 <= 0;
        lrck_reg1 <= 0;
        bck_reg1 <= 0;
        dout_reg1 <= 0;
    end else begin
        lrck_reg0 <= lrck;
        bck_reg0 <= bck;
        dout_reg0 <= dout;

        lrck_reg1 <= lrck_reg0;
        bck_reg1 <= bck_reg0;
        dout_reg1 <= dout_reg0;
    end
end



always@(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        FMT <= 0;
        MD0 <= 0;
        MD1 <= 0;
        audio_valid <= 0;
        audio_signal <= 0;
        state_cnt <= 0;
        config_wait_cnt <= 0;
        audio_data_buf <= 0;
        audio_bit_cnt <= 0;
        audio_work_cnt <= 0;
        i2s_delay <= 0;
    end else begin
        case(state_cnt) 
            0: begin
                FMT <= 0;
                MD0 <= 1;
                MD1 <= 1;
                state_cnt <= 1;
                audio_valid <= 0;
                audio_signal <= 0;
                config_wait_cnt <= 0;
                audio_data_buf <= 0;
                audio_bit_cnt <= 0;
                audio_work_cnt <= 0;
                i2s_delay <= 0;
            end
            1: begin
                if(config_wait_cnt <= WAIT_TIME) begin
                    config_wait_cnt <= config_wait_cnt + 1;
                end else if(config_wait_cnt > WAIT_TIME && audio_clk_locked) begin
                    state_cnt <= 2;
                    config_wait_cnt <= 0;
                end
            end
            2: begin  // 只接受左声道
                audio_valid <= 1;
                if((lrck_reg0 == 0) && (lrck_reg1 == 1) && (audio_bit_cnt == 0) && (audio_work_cnt == 0)) begin
                    audio_work_cnt <= 1;
                    i2s_delay <= 0; 
                    audio_data_buf <= 0;
                end else if(audio_work_cnt == 1) begin
                    if((bck_reg1 == 0) && (bck_reg0 == 1)) begin 
                        if(i2s_delay == 0) begin
                            i2s_delay <= 1; 
                        end else if(audio_bit_cnt < 'd23 && i2s_delay == 1) begin
                            audio_data_buf <= {audio_data_buf[22:0], dout_reg1}; 
                            audio_bit_cnt <= audio_bit_cnt + 1;
                        end else if(audio_bit_cnt >= 'd23 && i2s_delay == 1) begin
                            audio_data_buf <= {audio_data_buf[22:0], dout_reg1, audio_data_buf[22], audio_data_buf[22], audio_data_buf[22], audio_data_buf[22], 
                                                                                audio_data_buf[22], audio_data_buf[22], audio_data_buf[22], audio_data_buf[22]};
                            audio_bit_cnt <= 0;
                            audio_work_cnt <= 2;
                            i2s_delay <= 0;
                        end
                    end
                end else if(audio_work_cnt == 2) begin
                    audio_signal <= ~audio_signal;
                    audio_data <= audio_data_buf;
                    audio_work_cnt <= 0;
                end
            end
        endcase
    end
end



endmodule
