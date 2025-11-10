`timescale 1ns / 1ps

module effects_gate#(
    parameter AUDIO_WIDTH = 'd32,// 输入音频数据宽度
    parameter SAMPLE_SPEED = 'd48000// 采样率
)(
    input wire                  sys_clk,
    input wire                  sys_rst_n,

    input wire                  configure_en,
    input wire    [15:0]        gate_threshold,
    input wire    [15:0]        gate_attack,
    input wire    [15:0]        gate_release,
    output reg                  gate_ready,

    // 输入音频数据接口
    input wire signed [AUDIO_WIDTH-1:0]   audio_in,
    input wire          audio_in_signal,
    input wire          audio_in_en,
    // 输出音频数据接口
    output reg signed [AUDIO_WIDTH-1:0]   audio_out,
    output reg          audio_out_signal,
    output reg          audio_out_en
);

reg    [15:0]        gate_threshold_reg;
reg    [15:0]        gate_attack_reg;
reg    [15:0]        gate_release_reg;

reg     configure_en_reg0;
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
        config_state <= CONFIG_IDLE;
        config_state_cnt <= 0;
        gate_threshold_reg <= 0;
        gate_attack_reg <= 0;
        gate_release_reg <= 0;
        gate_ready <= 0;
    end
    else begin
        case(config_state) 
            CONFIG_IDLE: begin
                config_state <= CONFIGURE;
                config_state_cnt <= 0;
                gate_threshold_reg <= 0;
                gate_attack_reg <= 0;
                gate_release_reg <= 0;
                gate_ready <= 0;
            end
            CONFIGURE: begin
                if (config_state_cnt == 2'd0) begin
                    if(!configure_en_reg0 && configure_en) begin
                        config_state_cnt<= config_state_cnt + 1'b1;
                    end
                end 
                else if(config_state_cnt == 1) begin
                    gate_threshold_reg <= gate_threshold;
                    gate_attack_reg <= gate_attack;
                    gate_release_reg <= gate_release;
                    config_state_cnt<= config_state_cnt + 1'b1;
                end
                else if(config_state_cnt == 2) begin
                    gate_ready <= 1;
                    if(!configure_en_reg0 && configure_en) begin
                        config_state_cnt <= 1;
                        gate_ready <= 0;
                    end
                end
            end
            default: config_state <= CONFIG_IDLE;
        endcase
    end
end

//1.获取输入信号绝对值
//2.将绝对值与门限比较
//3. ①强于门限者，令增益初始值为1；②弱于门限者，令增益初始值为0
//4.计算本次所用的真实增益，由历史增益值以及参数确定
//  ①强者：gate_gain = (1-attack)*1+attack*gate_gain(n-1)
//  ②弱者：gate_gain = (1-release)*1+release*gate_gain(n-1)
//5.应用增益，获取实际输出（要注意取32位可用数值）
// 音频处理分支
reg [15:0]  gate_last_gain = 0;
reg [15:0]  gate_gain_temp1;
reg [15:0]  gate_gain_temp2;
reg signed [47:0] audio_in_reg;
reg signed [47:0] audio_out_reg;
reg [3:0]   gate_work_cnt;
localparam MAX_GAIN = 'd1024;//以1024作为“1”
reg audio_in_signal_reg0;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        audio_in_signal_reg0 <= 1'b0;
    end else begin
        audio_in_signal_reg0 <= audio_in_signal;
    end
end
localparam EFFECT_GATE_IDLE = 0;
localparam EFFECT_GATE_WORK = 1;
reg [0:0] state;
reg [3:0] effect_state_cnt;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state <= EFFECT_GATE_IDLE;
        effect_state_cnt <= 0;

        gate_last_gain <= 0;
        gate_gain_temp1 <= 0;
        gate_gain_temp2 <= 0;
        audio_in_reg <= 0;
        gate_work_cnt <= 0;
        audio_out_reg <= 0;

        audio_out_signal <= 0;
        audio_out <= 0;
        audio_out_en <= 0;
    end
    else begin
        case(state) 
            EFFECT_GATE_IDLE: begin
                effect_state_cnt <= 0;
                gate_last_gain <= 0;
                gate_gain_temp1 <= 0;
                gate_gain_temp2 <= 0;
                audio_in_reg <= 0;
                audio_out_reg <= 0;
                gate_work_cnt <= 0;
                audio_out_signal <= 0;
                audio_out <= 0;
                audio_out_en <= 0;
                if(gate_ready && audio_in_en) begin
                    state <= EFFECT_GATE_WORK;
                end
            end
            EFFECT_GATE_WORK: begin
                audio_out_en <= 1;
                if(effect_state_cnt == 0) begin
                    if(audio_in_signal_reg0 != audio_in_signal) begin
                    audio_in_reg <= {{16{audio_in[31]}}, audio_in};
                    effect_state_cnt <= effect_state_cnt + 1;
                    end
                end
                else if(effect_state_cnt == 1) begin
                    if(gate_work_cnt == 0) begin
                        gate_work_cnt <= gate_work_cnt + 1;
                        if(audio_in_reg > $signed(gate_threshold_reg) || audio_in_reg <= $signed(-gate_threshold_reg)) begin
                            gate_gain_temp1[14:0] <= MAX_GAIN - gate_attack_reg;
                            gate_gain_temp2[14:0] <= gate_attack_reg * gate_last_gain >>> 10;
                        end
                        else if(audio_in_reg <= $signed(gate_threshold_reg) && audio_in_reg >= $signed(-gate_threshold_reg)) begin
                            gate_gain_temp1[14:0] <= MAX_GAIN - gate_release_reg;
                            gate_gain_temp2[14:0] <= gate_release_reg * gate_last_gain >>> 10;
                        end
                    end
                    else if(gate_work_cnt == 1) begin
                        audio_out_reg <= audio_in_reg *$signed(gate_gain_temp2 + gate_gain_temp1);
                        gate_last_gain <= (gate_gain_temp2 + gate_gain_temp1);
                        gate_work_cnt <= gate_work_cnt + 1;
                    end
                    else if(gate_work_cnt == 2) begin
                        audio_out_reg <= audio_out_reg >>> 10;
                        gate_work_cnt <= 0;
                        effect_state_cnt <= effect_state_cnt + 1;
                    end
                end
                else if(effect_state_cnt == 2) begin
                    audio_out <=  {audio_out_reg[47],audio_out_reg[30:0]};
                    audio_out_signal <= ~audio_out_signal;
                    effect_state_cnt <= 0;
                end
            end
            default: state <= EFFECT_GATE_IDLE;
        endcase
    end
end

endmodule
