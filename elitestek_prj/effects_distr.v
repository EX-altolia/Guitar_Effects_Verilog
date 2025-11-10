`timescale 1ns / 1ps

module effects_distr#(
    parameter AUDIO_WIDTH = 'd32,// 输入音频数据宽度
    parameter SAMPLE_SPEED = 'd48000// 采样率
)(
    input wire                      sys_clk,
    input wire                      sys_rst_n,
    // 配置接口
    input wire                      configure_en,
    input wire          [11:0]      distort_gain, // 失真前增益
    input wire signed   [31:0]      distort_max, // 失真阈值
    output reg                      distort_ready,
    // 输入音频数据接口
    input wire signed   [32-1:0]    audio_in,
    input wire                      audio_in_signal,// 输入音频数据有效信号，翻转时数据更新
    input wire                      audio_in_en,// 输入音频数据使能，该信号拉高时准备接收
    // 输出音频数据接口
    output reg  [32-1:0]            audio_out,
    output reg                      audio_out_signal,
    output reg                      audio_out_en
    );


//参数配置分支
// 失真参数寄存
localparam DISTORT_DENO = 'd1024;
localparam DISTORT_GAIN_INIT = 'd2048;//失真前增益初始值
localparam DISTORT_MAX_INIT = 'd27;//失真阈值初始值,以次方数表示
reg [11:0] distort_pre_gain_reg;
reg signed [31:0] distort_max_reg;

reg configure_en_reg0;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        configure_en_reg0 <= 1'b0;
    end else begin
        configure_en_reg0 <= configure_en;
    end
end
// 参数配置状态机
localparam CONFIG_IDLE = 2'd0;
localparam CONFIGURE  = 2'd1;
reg [1:0] config_state;
reg [1:0] config_state_cnt;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        //状态机寄存器初始化
        config_state <= CONFIG_IDLE;
        config_state_cnt <= 0;
        //参数寄存器初始化
        distort_pre_gain_reg <= DISTORT_GAIN_INIT;
        distort_max_reg <= DISTORT_MAX_INIT;
        distort_ready <= 1'b0;
    end
    else begin
        case (config_state)
            CONFIG_IDLE: begin
                config_state <= CONFIGURE;
                config_state_cnt <= 2'd0;
                distort_pre_gain_reg <= DISTORT_GAIN_INIT;
                distort_max_reg <= DISTORT_MAX_INIT;
                distort_ready <= 1'b1;// 默认配置完成，这样不初始化也能工作
            end
            CONFIGURE: begin
                if(config_state_cnt == 0) begin
                    if(configure_en && !configure_en_reg0) begin
                        config_state_cnt <= config_state_cnt + 1'b1;
                    end
                end
                else if(config_state_cnt == 1) begin
                    distort_pre_gain_reg <= distort_gain;
                    distort_max_reg <= distort_max;
                    config_state_cnt <= config_state_cnt + 1'b1;
                end
                else if(config_state_cnt == 2) begin
                    distort_ready <= 1'b1;
                    if (configure_en_reg0 && !configure_en) begin
                        config_state    <= CONFIGURE;
                        config_state_cnt<= 2'd1;
                        distort_ready     <= 1'b0;
                    end
                end
            end
            default: begin
                config_state <= CONFIG_IDLE;
            end
        endcase
    end
end

//音频·处理分支
//output data = clip(input_data * distort_gain)
//1.temp_distort_data1 = input_data*distort_pre_gain
//2.temp_distort_data2 = temp_distort_data1/1024
//3.temp_distort_data3 = clip(temp_distort_data2,distort_max) 

reg [1:0] simdebug;

reg audio_in_signal_reg0;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        audio_in_signal_reg0 <= 1'b0;
    end else begin
        audio_in_signal_reg0 <= audio_in_signal;
    end
end

reg  signed [31:0] mul_audio_in;
reg  [11:0] mul_audio_in_sign;
wire signed [43:0] mul_audio_out;
reg  signed [33:0] mul_audio_out_pre;
mult_gen_0 distort_mult_inst1(
    .CLK(sys_clk),
    .A  (mul_audio_in),
    .B  (mul_audio_in_sign),
    .P  (mul_audio_out)
);

localparam EFFECT_DISTORT_IDLE = 'd0;
localparam EFFECT_DISTORT_WORK = 'd1;
reg [0:0] state;
reg [3:0] effect_state_cnt;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state <= EFFECT_DISTORT_IDLE;
        effect_state_cnt <= 4'd0;

        mul_audio_in <= 'd0;
        mul_audio_in_sign <= 'd0;

        audio_out <= 'd0;
        audio_out_signal <= 1'b0;
        audio_out_en <= 1'b0;
    end
    else begin
        case (state)
            EFFECT_DISTORT_IDLE: begin
                effect_state_cnt <= 4'd0;
                audio_out <= 'd0;
                audio_out_signal <= 1'b0;
                audio_out_en <= 1'b0;
                if(audio_in_en && distort_ready) begin
                    state <= EFFECT_DISTORT_WORK;
                end
            end
            EFFECT_DISTORT_WORK: begin
                audio_out_en <= 1'b1;
                if(effect_state_cnt == 0) begin
                    if(audio_in_signal != audio_in_signal_reg0) begin
                        effect_state_cnt <= effect_state_cnt + 1'b1;
                    end
                end
                else if(effect_state_cnt == 1) begin
                    mul_audio_in <= audio_in[32-1:0];
                    mul_audio_in_sign <= distort_pre_gain_reg;
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 2) begin
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 3) begin
                    mul_audio_out_pre <= $signed(mul_audio_out) >>> 10; // 等效除以 1024
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 4) begin
                    if(mul_audio_out_pre > distort_max_reg) begin
                        simdebug <= 2'd1;
                        audio_out <= distort_max_reg;
                    end
                    else if(mul_audio_out_pre < -distort_max_reg) begin
                        simdebug <= 2'd2;
                        audio_out <= -distort_max_reg;
                    end
                    else begin
                        simdebug <= 2'd0;
                        audio_out <= {mul_audio_out_pre[33],mul_audio_out_pre[30:0]};
                    end
                    mul_audio_in <= 0;
                    mul_audio_in_sign <= 0;
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 5) begin
                    audio_out_signal <= ~audio_out_signal;
                    effect_state_cnt <= 4'd0;
                end
                if(!distort_ready) begin
                    state <= EFFECT_DISTORT_IDLE;
                end
            end
        endcase
    end
end

endmodule


module mult_gen_0 (
    input  wire CLK,
    input  wire signed [31:0] A,      // 32-bit signed input
    input  wire [11:0] B,        // 12-bit unsigned input
    output reg  signed [43:0] P      // 44-bit signed output (result of multiplication)
);

always@(posedge CLK)
    P <= A * B;

endmodule

