`timescale 1ns / 1ps
module effects_comp#(
    parameter AUDIO_WIDTH = 'd32,// 输入音频数据宽度
    parameter SAMPLE_SPEED = 'd48000// 采样率
)(
    input wire          sys_clk,
    input wire          sys_rst_n,

    input wire          configure_en,
    input wire [9:0]    comp_alpha, // 包络平滑参数 alpha = comp_alpha/1024
    input wire [31:0]   comp_threshold, // 压缩阈值 threshold
    input wire [9:0]   comp_ratio_turn, // 压缩比倒数*1024的结果，如4:1则传入256，x/ratio = x*256/1024
    input wire [9:0]    comp_attack, // 压缩响应速度 attack = comp_attack/1024
    input wire [9:0]    comp_release, // 压缩恢复速度 release = comp_release/1024
    input wire [11:0]   comp_gain, // 压缩后增益 gain = comp_gain/1024
    output reg          comp_ready,

    // 输入音频数据接口
    input wire signed [32-1:0]   audio_in,
    input wire          audio_in_signal,
    input wire          audio_in_en,
    // 输出音频数据接口
    output reg  [32-1:0]   audio_out,
    output reg          audio_out_signal,
    output reg          audio_out_en
);

//参数配置分支
localparam COMP_ALPHA_INIT = 'd800;
localparam COMP_THRESHOLD_INIT = 'd10737418;
localparam COMP_RATIO_TURN_INIT = 'd2048;
localparam COMP_ATTACK_INIT = 'd50;
localparam COMP_RELEASE_INIT = 'd200;
localparam COMP_GAIN_INIT = 'd1800;

reg     [9:0]   comp_alpha_reg;
reg     [31:0]  comp_threshold_reg;
reg     [11:0]  comp_ratio_turn_reg;
reg     [9:0]   comp_attack_reg;
reg     [9:0]   comp_release_reg;
reg     [11:0]  comp_gain_reg;

reg configure_en_reg0;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        configure_en_reg0 <= 1'b0;
    end else begin
        configure_en_reg0 <= configure_en;
    end
end

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
        comp_alpha_reg <= COMP_ALPHA_INIT;
        comp_threshold_reg <= COMP_THRESHOLD_INIT;
        comp_ratio_turn_reg <= COMP_RATIO_TURN_INIT;
        comp_attack_reg <= COMP_ATTACK_INIT;
        comp_release_reg <= COMP_RELEASE_INIT;
        comp_gain_reg <= COMP_GAIN_INIT;
        comp_ready <= 1'b0;
    end
    else begin
        case (config_state)
            CONFIG_IDLE: begin
                config_state <= CONFIGURE;
                config_state_cnt <= 2'd0;
                comp_alpha_reg <= COMP_ALPHA_INIT;
                comp_threshold_reg <= COMP_THRESHOLD_INIT;
                comp_ratio_turn_reg <= COMP_RATIO_TURN_INIT;
                comp_attack_reg <= COMP_ATTACK_INIT;
                comp_release_reg <= COMP_RELEASE_INIT;
                comp_gain_reg <= COMP_GAIN_INIT;
                comp_ready <= 1'b1;
            end
            CONFIGURE: begin
                if(config_state_cnt == 0) begin
                    if(configure_en && !configure_en_reg0) begin
                        config_state_cnt <= config_state_cnt + 1'b1;
                    end
                end
                else if(config_state_cnt == 1) begin
                    comp_alpha_reg <= comp_alpha;
                    comp_threshold_reg <= comp_threshold;
                    comp_ratio_turn_reg <= comp_ratio_turn;
                    comp_attack_reg <= comp_attack;
                    comp_release_reg <= comp_release;
                    comp_gain_reg <= comp_gain;
                    config_state_cnt <= config_state_cnt + 1'b1;
                end
                else if(config_state_cnt == 2) begin
                    comp_ready <= 1'b1;
                    if (configure_en_reg0 && !configure_en) begin
                        config_state    <= CONFIGURE;
                        config_state_cnt<= 2'd1;
                        comp_ready      <= 1'b0;
                    end
                end
            end
            default: begin
                config_state <= CONFIG_IDLE;
            end
        endcase
    end
end

//音频处理分支
//1. 获取输入的绝对值abs_audio_in
//2. 包络计算       e_prev_in = max(abs_audio_in, last_e_prev * alpha)
//3. 突发值计算     h_prev_in = min(e_prev_in, threshold+(e_prev_in-threshold)/ratio)
//4. 增益计算：     gs_prev_in = h_prev_in / e_prev_in
//5. 增益平滑：     ①如果gs_prev_in >= last_gs_prev, 则 
//                  gs_prev = （1-release）*gs_prev_in + release*last_gs_prev
//                 ②如果gs_prev_in < last_gs_prev, 则
//                  gs_prev = (1-attack)*gs_prev_in + attack*last_gs_prev
//6. 增益补偿与计算：mul_audio_in = audio_in * gs_prev * gain
//历史数据寄存：     last_e_prev <= e_prev_in; last_gs_prev <= gs_prev;

reg s_axis_dividend_tvalid;
reg [47:0] s_axis_dividend_tdata;// 48位，有效是32+10位，补齐
reg s_axis_divisor_tvalid;
reg [31:0] s_axis_divisor_tdata;// 32位
wire m_axis_dout_tvalid;
wire [79:0] m_axis_dout_tdata; //48+32位，恰好补齐

div_gen_0 comp_div_inst1(
    .numer      (s_axis_dividend_tdata),
    .denom      (s_axis_divisor_tdata),
    .clken      (s_axis_divisor_tvalid),
    .clk        (sys_clk),
    .reset      (~sys_rst_n),
    .quotient   (m_axis_dout_tdata[79:32]),
    .remain     (m_axis_dout_tdata[31:0] ),
    .rfd(m_axis_dout_tvalid)
);


reg [31:0] abs_audio_in; // 输入音频绝对值,后面大部分基于绝对值计算，因此直接用绝对值（无符号）
reg [31+10:0] last_e_prev_mul; // 上一包络乘法值 last_e_prev * alpha
reg [31:0] e_prev_in; // 当前包络值
reg [31+10:0] e_prev_in_change; // 当前包络值变更值threshold+(e_prev_in-threshold)/ratio
reg [31+10:0] h_prev_in; // 当前突发值
reg [31+10:0] gs_prev_in; // 当前增益值
reg [31+10:0] gs_prev_temp1;
reg [31+10:0] gs_prev_temp2;
reg [31+10:0] gs_prev; // 平滑后增益值
reg [31+10:0] mul_audio_out; // 增益补偿后音频值

reg [31:0] last_e_prev = 32'd65536; // 上一包络
reg [31:0] last_gs_prev = 32'd1024; // 上一增益平滑值


localparam EFFECT_COMP_IDLE = 'd0;
localparam EFFECT_COMP_WORK = 'd1;
reg [0:0] state;
reg [4:0] effect_state_cnt;

reg audio_in_signal_reg0;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        audio_in_signal_reg0 <= 1'b0;
    end else begin
        audio_in_signal_reg0 <= audio_in_signal;
    end
end

always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state <= EFFECT_COMP_IDLE;
        effect_state_cnt <= 4'd0;
        //中间变量清零
        abs_audio_in <= 'd0;
        last_e_prev_mul <= 'd0;
        e_prev_in <= 'd0;
        e_prev_in_change <= 'd0;
        h_prev_in <= 'd0;
        gs_prev_in <= 'd0;
        gs_prev_temp1 <= 'd0;
        gs_prev_temp2 <= 'd0;
        gs_prev <= 'd0;
        mul_audio_out <= 'd0;
        //除法器输入清零
        s_axis_dividend_tdata <= 'd0;
        s_axis_dividend_tvalid <= 1'b0;
        s_axis_divisor_tdata <= 'd0;
        s_axis_divisor_tvalid <= 1'b0;
        //历史数据清空
        last_e_prev <= 'd0;
        last_gs_prev <= 'd0;
        //输出清零
        audio_out <= 'd0;
        audio_out_signal <= 1'b0;
        audio_out_en <= 1'b0;
    end
    else begin
        case(state)
            EFFECT_COMP_IDLE: begin
                effect_state_cnt <= 4'd0;
                //中间变量清零
                abs_audio_in <= 'd0;
                last_e_prev_mul <= 'd0;
                e_prev_in <= 'd0;
                e_prev_in_change <= 'd0;
                h_prev_in <= 'd0;
                gs_prev_in <= 'd0;
                gs_prev_temp1 <= 'd0;
                gs_prev_temp2 <= 'd0;
                gs_prev <= 'd0;
                mul_audio_out <= 'd0;
                //除法器输入清零
                s_axis_dividend_tdata <= 'd0;
                s_axis_dividend_tvalid <= 1'b0;
                s_axis_divisor_tdata <= 'd0;
                s_axis_divisor_tvalid <= 1'b0;
                //历史数据寄存，不清空
                audio_out <= 'd0;
                audio_out_signal <= 1'b0;
                audio_out_en <= 1'b0;
                if (audio_in_en && comp_ready) begin
                    state <= EFFECT_COMP_WORK;
                end
            end
            EFFECT_COMP_WORK: begin
                audio_out_en <= 1'b1;
                if(effect_state_cnt == 0) begin
                    if(audio_in_signal != audio_in_signal_reg0) begin
                        effect_state_cnt <= effect_state_cnt + 1'b1;
                    end
                end
                else if(effect_state_cnt == 1) begin//获取绝对值 abs_audio_in
                    if(audio_in[31] == 1'b1) begin
                        abs_audio_in <= ~audio_in + 1;;
                    end
                    else begin
                        abs_audio_in <= audio_in;
                    end
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 2) begin//包络计算1 
                    last_e_prev_mul <= (last_e_prev * comp_alpha_reg) >> 10; // 等效除以1024
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 3) begin//包络计算2
                    if(abs_audio_in > last_e_prev_mul) begin
                        e_prev_in <= abs_audio_in;
                    end
                    else begin
                        e_prev_in <= last_e_prev_mul;
                    end
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 4) begin//突发值计算1 threshold+(e_prev_in-threshold)*ratio_turn/1024
                    e_prev_in_change <= (e_prev_in - comp_threshold_reg);
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 5) begin//突发值计算2
                    e_prev_in_change <= (e_prev_in_change * comp_ratio_turn) >> 10; // 等效除以1024
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 6) begin//突发值计算3
                    e_prev_in_change <= comp_threshold_reg + e_prev_in_change;
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 7) begin//突发值计算4 h_prev_in = min(e_prev_in, threshold+(e_prev_in-threshold)/ratio)
                    if(e_prev_in < e_prev_in_change) begin
                        h_prev_in <= e_prev_in;
                    end
                    else begin
                        h_prev_in <= e_prev_in_change;
                    end
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 8) begin// h_prev_in*1024 / e_prev_in
                    s_axis_dividend_tvalid <= 1'b1;
                    s_axis_dividend_tdata <= {16'd0,h_prev_in} <<10; // 等效乘以1024
                    s_axis_divisor_tvalid <= 1'b1;
                    s_axis_divisor_tdata <= e_prev_in;
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 9) begin// 等待除法器准备好
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 10) begin// 等待除法器计算完成
                    if(m_axis_dout_tvalid && !m_axis_dout_tdata[79]) begin
                        s_axis_divisor_tvalid <= 1'b0;
                        s_axis_dividend_tvalid <= 1'b0;
                        gs_prev_in <= m_axis_dout_tdata[79:32];
                        effect_state_cnt <= effect_state_cnt + 1'b1;
                    end
                    else if(m_axis_dout_tvalid && m_axis_dout_tdata[79]) begin
                        s_axis_divisor_tvalid <= 1'b0;
                        s_axis_dividend_tvalid <= 1'b0;
                        gs_prev_in <= 32'd1024; // 除法器初始上电时会全为f
                        effect_state_cnt <= effect_state_cnt + 1'b1;
                    end
                end
                else if(effect_state_cnt == 11) begin//增益平滑
                    if(gs_prev_in >= last_gs_prev) begin// gs_prev = （1-release）*gs_prev_in + release*last_gs_prev
                        gs_prev_temp1 <= (32'd1024 - comp_release_reg)*gs_prev_in;
                        gs_prev_temp2 <= comp_release_reg*last_gs_prev;
                        effect_state_cnt <= effect_state_cnt + 1'b1;
                    end
                    else begin// gs_prev = (1-attack)*gs_prev_in + attack*last_gs_prev
                        gs_prev_temp1 <= (32'd1024 - comp_attack_reg)*gs_prev_in;
                        gs_prev_temp2 <= comp_attack_reg*last_gs_prev;
                        effect_state_cnt <= effect_state_cnt + 1'b1;
                    end
                end
                else if(effect_state_cnt == 12) begin//增益平滑2
                    gs_prev <= (gs_prev_temp1 + gs_prev_temp2)>>10; // 等效除以1024
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 13) begin//增益补偿与计算1 mul_audio_out = audio_in * gs_prev * gain
                    mul_audio_out <= (abs_audio_in * gs_prev)>>10;
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 14) begin//增益补偿与计算2(数据更新可以简化到这里，但目前不动)
                    mul_audio_out <= (mul_audio_out * comp_gain_reg)>>10;
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 15) begin//输出结果,更新历史数据
                    if(audio_in[31] == 0)
                        audio_out <= {0, mul_audio_out[30:0]};
                    else if(audio_in[31] == 1)
                        audio_out <= {1,~mul_audio_out[30:0]};
                    last_e_prev <= e_prev_in;
                    last_gs_prev <= gs_prev;
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if(effect_state_cnt == 16) begin
                    audio_out_signal <= ~audio_out_signal;
                    effect_state_cnt <= 4'd0;
                end
                if (comp_ready == 1'b0) begin
                    state <= EFFECT_COMP_IDLE;
                end
            end
        endcase
    end
end

endmodule
