`timescale 1ns / 1ps

module audio_ts_out(
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    input  wire        audio_clk,        // 12.288 MHz BCLK
    input  wire        pcm_work_enable,  // PCM 发送使能
    input  wire signed [31:0] pcm_data,  // 左声道 PCM 数据
    input  wire        pcm_data_signal,  // 数据更新标志

    output wire        DAC_SCK ,         
    output reg         DAC_BCLK,         // Bit Clock (12.288 MHz)
    output reg         DAC_LRCK,         // LR Clock (48 kHz, 50% 占空比)
    output reg         DAC_DIN           // Serial Data Out
);


assign DAC_SCK = audio_clk;

// =============== LRCK与bclk 产生 =================
//共32bit
reg [8:0] lrck_cnt;  // 0~255
reg [8:0] bck_cnt;//0~4
always @(posedge audio_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        lrck_cnt <= 0;
        bck_cnt <= 0;
        DAC_LRCK <= 0;
        DAC_BCLK <= 0;
    end else begin
        if(lrck_cnt == 'd255) begin
            DAC_LRCK <= ~DAC_LRCK;
            lrck_cnt <= 0;
        end else if(lrck_cnt < 'd255) begin
            lrck_cnt <= lrck_cnt + 1;
        end

        if(bck_cnt == 'd3) begin
            DAC_BCLK <= ~DAC_BCLK;
            bck_cnt <= 0;
        end else if(bck_cnt < 'd3) begin
            bck_cnt <= bck_cnt + 1;
        end
    end
end

reg DAC_LRCK_reg0;
reg DAC_BCLK_reg0;
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        DAC_LRCK_reg0 <= 0;
        DAC_BCLK_reg0 <= 0;
    end else begin
        DAC_LRCK_reg0 <= DAC_LRCK;
        DAC_BCLK_reg0 <= DAC_BCLK;
    end
end

wire lrck_negedge = DAC_LRCK_reg0 & ~DAC_LRCK; 
wire bclk_negedge = DAC_BCLK_reg0 & ~DAC_BCLK; 
//数据更新标志延长
reg pcm_data_signal_reg0;
reg pcm_data_signal_reg1;
reg pcm_data_signal_reg2;
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        pcm_data_signal_reg0 <= 0;
        pcm_data_signal_reg1 <= 0;
        pcm_data_signal_reg2 <= 0;
    end else begin
        pcm_data_signal_reg0 <= pcm_data_signal;
        pcm_data_signal_reg1 <= pcm_data_signal_reg0;
        pcm_data_signal_reg2 <= pcm_data_signal_reg1;
    end
end
wire pcm_data_signal_edge = pcm_data_signal_reg0 ^ pcm_data_signal_reg2;




// =============== 数据发送 ====================
reg signed [31:0] pcm_data_reg;
reg [31:0] shift_reg_left;
reg [5:0]  bit_cnt;
reg [7:0]  send_work_cnt;
reg        data_prepare_signal;
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        pcm_data_reg <= 0;
        shift_reg_left <= 0;
        DAC_DIN        <= 0;
        bit_cnt        <= 0;
        send_work_cnt  <= 0;
        data_prepare_signal <= 0;
    end else begin
        if((send_work_cnt == 0) && (data_prepare_signal == 0) && (pcm_data_signal_edge == 1)) begin
            DAC_DIN <= 0;
            pcm_data_reg <= pcm_data;
            send_work_cnt <= 1;
            data_prepare_signal <= 1;
        end
        else if((data_prepare_signal == 1) && (send_work_cnt == 1) && (lrck_negedge == 1)) begin
            DAC_DIN <= 0;
            send_work_cnt <= 2;
        end 
        else if((data_prepare_signal == 1) && (send_work_cnt == 2) && (bclk_negedge == 1)) begin
            if (bit_cnt < 31) begin
                DAC_DIN <= pcm_data_reg[31];  
                pcm_data_reg <= {pcm_data_reg[30:0], 1'b0};  
                bit_cnt <= bit_cnt + 1;
            end else if (bit_cnt == 31) begin
                DAC_DIN <= pcm_data_reg[31];  
                bit_cnt <= 0;
                send_work_cnt <= 3;
            end
        end
        else if((data_prepare_signal == 1) && (send_work_cnt == 3) && (bclk_negedge == 1)) begin
            DAC_DIN <= 0;
            data_prepare_signal <= 0;
            pcm_data_reg <= 0;
            send_work_cnt <= 0;
        end
    end
end

endmodule
