`timescale 1ns / 1ps

module effects_adjust(
    input wire  sys_clk,
    input wire  sys_rst_n,
    input wire  audio_clk,
    //pcm1840侧
    output wire  FMT ,
    output wire  MD0 ,
    output wire  MD1 ,
    output wire  sclk,
    input  wire  bck ,
    input  wire  lrck,
    input  wire  dout,
    //pcm5102a侧
    (* syn_preserve = "true" *)output wire  DAC_SCK ,         
    output wire  DAC_BCLK,        
    output wire  DAC_LRCK,         
    output wire  DAC_DIN ,         
    //参数调节功能侧
    output wire        params_ram_clk, 
    output reg         params_ram_rd_en,
    input  wire [15:0] params_ram_rd_data,
    output reg  [9:0]  params_ram_rd_addr,
    input  wire        params_change_en,//参数修改要求
    input  wire [17:0] params_match_reg,
    output reg         params_change_finished,//完成参数配置
    //效果器音频输出
    input  wire        effects_work_enable,//效果器工作使能
    output wire        effects_audio_out_en,
    output wire        effects_audio_out_signal,
    output wire signed [31:0] effects_audio_out,
    //效果器原清音输出
    output wire signed [31:0] effects_clear_audio_out,
    output wire        effects_clear_audio_out_signal,
    output wire        effects_clear_audio_ready
    );

assign params_ram_clk = sys_clk;

                                     
//audio_ts_in  inout
wire                in_pcm_ready;
wire signed [31:0]  in_pcm_data;
wire                in_pcm_data_signal;
//audio_ts_out inout
reg                 out_pcm_work_enable;
wire signed [31:0]  out_pcm_data;
wire                out_pcm_data_signal;

//delay effect
wire signed [31:0]  delay_audio_in;
wire                delay_audio_in_signal;
wire                delay_audio_in_en;
wire signed [31:0]  delay_audio_out;
wire                delay_audio_out_signal;
wire                delay_audio_out_en;
reg                 delay_configure_en;
reg  [11:0]         delay_delay_length;
reg  [9:0]          delay_mix;
reg  [9:0]          delay_back_volume;
wire                delay_delay_ready;
//distr effect
wire signed [31:0]  distr_audio_in;
wire                distr_audio_in_signal;
wire                distr_audio_in_en;
wire signed [31:0]  distr_audio_out;
wire                distr_audio_out_signal;
wire                distr_audio_out_en;
reg                 distr_configure_en;
reg         [11:0]  distr_distort_gain;
reg  signed [31:0]  distr_distort_max;
wire                distr_distort_ready;
//eq effect
wire signed [31:0]  eq_audio_in;
wire                eq_audio_in_signal;
wire                eq_audio_in_en;
wire signed [31:0]  eq_audio_out;
wire                eq_audio_out_signal;
wire                eq_audio_out_en;
reg                 eq_configure_en;
reg  signed [15:0]  eq_eq_config_data;//非一次并行
reg                 eq_configure_signal;
wire                eq_eq_ready;
//comp effect
wire signed [31:0]  comp_audio_in;
wire                comp_audio_in_signal;
wire                comp_audio_in_en;
wire signed [31:0]  comp_audio_out;
wire                comp_audio_out_signal;
wire                comp_audio_out_en;
reg                 comp_configure_en;
reg  [9:0]          comp_comp_alpha;
reg  [31:0]         comp_comp_threshold; 
reg  [9:0]          comp_comp_ratio_turn;
reg  [9:0]          comp_comp_attack;
reg  [9:0]          comp_comp_release;
reg  [11:0]         comp_comp_gain;
wire                comp_comp_ready;
//reverb effect
wire signed [31:0]  reverb_audio_in;
wire                reverb_audio_in_signal;
wire                reverb_audio_in_en;
wire signed [31:0]  reverb_audio_out;
wire                reverb_audio_out_signal;
wire                reverb_audio_out_en;
reg                 reverb_configure_en;
reg  signed [15:0]  reverb_reverb_param;
reg                 reverb_configure_signal;
wire                reverb_reverb_ready;
//gate effect
wire signed [31:0]  gate_audio_in;
wire                gate_audio_in_signal;
wire                gate_audio_in_en;
wire signed [31:0]  gate_audio_out;
wire                gate_audio_out_signal;
wire                gate_audio_out_en;
reg                 gate_configure_en;
reg     [15:0]      gate_gate_threshold;
reg     [15:0]      gate_gate_attack;
reg     [15:0]      gate_gate_release;
wire                gate_gate_ready;

/********************************************************/
/*                   pcm编解码器模块使能                 */
/********************************************************/
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        out_pcm_work_enable <= 0;
    end
    else begin
        out_pcm_work_enable <= effects_work_enable;
    end
end

/********************************************************/
/*                   效果器参数修改                      */
/********************************************************/
// 0(idle) 1(gate) 2(reverb) 3(comp) 4(eq) 5(delay) 6(distr)
reg [3:0] effect_change_state_cnt; //记录修改进程，表示修改到哪个效果器了
reg       effect_change_done;
reg       effect_change_done_reg0;
reg       params_change_en_reg0;
reg [9:0] params_state_cnt;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        params_change_en_reg0 <= 0;
        effect_change_done_reg0 <= 0;
    end else begin
        params_change_en_reg0 <= params_change_en;
        effect_change_done_reg0 <= effect_change_done;
    end
end
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        effect_change_state_cnt <= 0;
        params_change_finished <= 0;
    end
    else begin
        params_change_finished <= 0;
        if(effect_change_state_cnt == 0 && !params_change_en_reg0 && params_change_en) begin
            effect_change_state_cnt <= 1;
        end else if(effect_change_state_cnt < 7 && effect_change_state_cnt > 0) begin
            if(effect_change_done && !effect_change_done_reg0)
                effect_change_state_cnt <= effect_change_state_cnt + 1;
        end else if(effect_change_state_cnt == 7) begin
            effect_change_state_cnt <= 0;
            params_change_finished <= 1;
        end

    
    end
end
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        effect_change_done <= 0;
        params_state_cnt <= 0;
        params_ram_rd_en <= 0;
        params_ram_rd_addr <= 0;
        //各效果器配置使能
        gate_configure_en <= 0;
        reverb_configure_en <= 0;
        comp_configure_en <= 0;
        eq_configure_en <= 0;
        delay_configure_en <= 0;
        distr_configure_en <= 0;
        // Gate 参数
        gate_gate_threshold <= 0;
        gate_gate_attack <= 0;
        gate_gate_release <= 0;
        // Reverb 参数
        reverb_reverb_param <= 0;
        reverb_configure_signal <= 0;
        // Comp 参数
        comp_comp_alpha <= 0;
        comp_comp_threshold <= 0;
        comp_comp_ratio_turn <= 0;
        comp_comp_attack <= 0;
        comp_comp_release <= 0;
        comp_comp_gain <= 0;
        // EQ 参数
        eq_eq_config_data <= 0;
        eq_configure_signal <= 0;
        // Delay 参数
        delay_delay_length <= 0;
        delay_mix <= 0;
        delay_back_volume <= 0;
        // Distr 参数
        distr_distort_gain <= 0;
        distr_distort_max <= 0;
    end
    else begin
        case(effect_change_state_cnt) 
            0: begin
                gate_configure_en <= 0;
                reverb_configure_en <= 0;
                comp_configure_en <= 0;
                eq_configure_en <= 0;
                delay_configure_en <= 0;
                distr_configure_en <= 0;
                effect_change_done <= 0;
                params_state_cnt <= 0;
                params_ram_rd_en <= 0;
                params_ram_rd_addr <= 0;
            end
            1: begin
                if(params_state_cnt == 0) begin
                    effect_change_done <= 0;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= 0 + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 1) begin
                    gate_gate_threshold <= params_ram_rd_data;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 2) begin
                    gate_gate_attack <= params_ram_rd_data;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;//读完最后一个也不归零，顺延
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 3) begin
                    gate_gate_release <= params_ram_rd_data;
                    params_ram_rd_en <= 0;
                    params_state_cnt <= params_state_cnt + 1;
                    gate_configure_en <= 1;
                end else if(params_state_cnt == 4) begin
                    if(gate_gate_ready) begin
                        effect_change_done <= 1;
                        params_state_cnt <= 0;
                        gate_configure_en <= 0;
                    end
                end end
            2: begin
                if(params_state_cnt == 0) begin
                    effect_change_done <= 0;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt < 'd32 && params_state_cnt > 0) begin
                    reverb_configure_en <= 1;
                    reverb_configure_signal <= 1;
                    reverb_reverb_param <= params_ram_rd_data;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 'd32) begin
                    reverb_configure_en <= 1;
                    reverb_configure_signal <= 1;
                    reverb_reverb_param <= params_ram_rd_data;
                    params_ram_rd_en <= 0;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 'd33) begin
                    reverb_configure_en <= 0;
                    reverb_configure_signal <= 0;
                    if(reverb_reverb_ready) begin
                        reverb_configure_signal <= 0;
                        reverb_configure_en <= 0;
                        effect_change_done <= 1;
                        params_state_cnt <= 0;
                    end
                end end
            3: begin
                if(params_state_cnt == 0) begin
                    effect_change_done <= 0;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 1) begin
                    comp_comp_alpha <= params_ram_rd_data[9:0];
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 2) begin
                    comp_comp_threshold[15:0] <= params_ram_rd_data;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 3) begin
                    comp_comp_threshold[31:16] <= params_ram_rd_data;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 4) begin
                    comp_comp_ratio_turn <= params_ram_rd_data[9:0];
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 5) begin
                    comp_comp_attack <= params_ram_rd_data[9:0];
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 6) begin
                    comp_comp_release <= params_ram_rd_data[9:0];
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 7) begin
                    comp_configure_en <= 1;
                    comp_comp_gain <= params_ram_rd_data[11:0];
                    params_ram_rd_en <= 0;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 8) begin
                    if(comp_comp_ready) begin
                        comp_configure_en <= 0;
                        effect_change_done <= 1;
                        params_state_cnt <= 0;
                    end
                end end
            4: begin
                if(params_state_cnt == 0) begin
                    effect_change_done <= 0;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt < 'd16 && params_state_cnt >0) begin
                    eq_configure_en <= 1;
                    eq_configure_signal <= 1;
                    eq_eq_config_data <= params_ram_rd_data;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 'd16) begin
                    eq_configure_en <= 1;
                    eq_configure_signal <= 1;
                    eq_eq_config_data <= params_ram_rd_data;
                    params_ram_rd_en <= 0;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 'd17) begin
                    eq_configure_en <= 0;
                    eq_configure_signal <= 0;
                    if(eq_eq_ready) begin
                        eq_configure_signal <= 0;
                        eq_configure_en <= 0;
                        effect_change_done <= 1;
                        params_state_cnt <= 0;
                    end
                end end
            5: begin 
                if(params_state_cnt == 0) begin
                    effect_change_done <= 0;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 1) begin
                    delay_delay_length <= params_ram_rd_data[11:0];
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 2) begin
                    delay_mix <= params_ram_rd_data[9:0];
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 3) begin
                    delay_back_volume <= params_ram_rd_data[9:0];
                    params_ram_rd_en <= 0;
                    params_state_cnt <= params_state_cnt + 1;
                    delay_configure_en <= 1;
                end else if(params_state_cnt == 4) begin
                    if(delay_delay_ready) begin
                        effect_change_done <= 1;
                        params_state_cnt <= 0;
                        delay_configure_en <= 0;
                    end
                end end
            6: begin
                if(params_state_cnt == 0) begin
                    effect_change_done <= 0;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 1) begin
                    distr_distort_gain <= params_ram_rd_data[11:0];
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;
                end else if(params_state_cnt == 2) begin
                    distr_distort_max[15:0] <= params_ram_rd_data;
                    params_ram_rd_en <= 1;
                    params_ram_rd_addr <= params_ram_rd_addr + 1;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 3) begin
                    distr_distort_max[31:16] <= params_ram_rd_data;
                    params_ram_rd_en <= 0;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 4) begin
                    distr_configure_en <= 1;
                    params_state_cnt <= params_state_cnt + 1;  
                end else if(params_state_cnt == 5) begin
                    if(distr_distort_ready) begin
                        distr_configure_en <= 0;
                        effect_change_done <= 1;
                        params_state_cnt <= 0;
                    end
                end
            end
            default:;
        endcase
    end
end




/********************************************************/
/*                   效果器流程匹配                        */
/********************************************************/
//一共六种效果，共六个环节，每个环节有六种选择+哪个都不选
// 0(不进行处理) 1(gate) 2(reverb) 3(comp) 4(eq) 5(delay) 6(distr)
//[17:0] 分为六个3bit，从低到高位表示先后（低位在接近音频输入的位置）
//每个效果器的输入取决于出现了他自己的代号的前一个效果（低位3bit）
reg     [17:0]      effects_match_reg;
wire signed [31:0]  stage_audio_in        [5:0];
wire                stage_audio_in_signal [5:0];
wire                stage_audio_in_en     [5:0];

always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        effects_match_reg <= 0;
    end
    else begin
        if(params_change_en && !params_change_en_reg0)
            effects_match_reg <= params_match_reg;
    end
end

assign stage_audio_in_en[0]     = in_pcm_ready;
assign stage_audio_in[0]        = in_pcm_data;
assign stage_audio_in_signal[0] = in_pcm_data_signal;

genvar i;
generate
    for (i = 1; i < 6; i = i + 1) begin : stage_route_gen
        // 获取前一环节（第 i 级）的效果器选择代码
        wire [2:0] prev_effect_code = effects_match_reg[3*(i-1) +: 3];
        assign stage_audio_in_en[i] = prev_effect_code == 3'd0 ? stage_audio_in_en[i-1] :
                                      prev_effect_code == 3'd1 ? gate_audio_out_en :
                                      prev_effect_code == 3'd2 ? reverb_audio_out_en :
                                      prev_effect_code == 3'd3 ? comp_audio_out_en :
                                      prev_effect_code == 3'd4 ? eq_audio_out_en :
                                      prev_effect_code == 3'd5 ? delay_audio_out_en :
                                      prev_effect_code == 3'd6 ? distr_audio_out_en :
                                      stage_audio_in_en[i-1];                       
        assign stage_audio_in[i] = prev_effect_code == 3'd0 ?  stage_audio_in[i-1] : 
                                   prev_effect_code == 3'd1 ? gate_audio_out :
                                   prev_effect_code == 3'd2 ? reverb_audio_out :
                                   prev_effect_code == 3'd3 ? comp_audio_out :
                                   prev_effect_code == 3'd4 ? eq_audio_out :
                                   prev_effect_code == 3'd5 ? delay_audio_out :
                                   prev_effect_code == 3'd6 ? distr_audio_out :
                                   stage_audio_in[i-1];
        assign stage_audio_in_signal[i] = prev_effect_code == 3'd0 ? stage_audio_in_signal[i-1] :
                                          prev_effect_code == 3'd1 ? gate_audio_out_signal :
                                          prev_effect_code == 3'd2 ? reverb_audio_out_signal :
                                          prev_effect_code == 3'd3 ? comp_audio_out_signal :
                                          prev_effect_code == 3'd4 ? eq_audio_out_signal :
                                          prev_effect_code == 3'd5 ? delay_audio_out_signal :
                                          prev_effect_code == 3'd6 ? distr_audio_out_signal :
                                          stage_audio_in_signal[i-1];
    end
endgenerate
//gate
assign gate_audio_in        = effects_match_reg[2:0]   == 3'd1 ? stage_audio_in[0] :
                              effects_match_reg[5:3]   == 3'd1 ? stage_audio_in[1] :
                              effects_match_reg[8:6]   == 3'd1 ? stage_audio_in[2] :
                              effects_match_reg[11:9]  == 3'd1 ? stage_audio_in[3] :
                              effects_match_reg[14:12] == 3'd1 ? stage_audio_in[4] :
                              effects_match_reg[17:15] == 3'd1 ? stage_audio_in[5] : 0;
assign gate_audio_in_signal = effects_match_reg[2:0]   == 3'd1 ? stage_audio_in_signal[0] :
                              effects_match_reg[5:3]   == 3'd1 ? stage_audio_in_signal[1] :
                              effects_match_reg[8:6]   == 3'd1 ? stage_audio_in_signal[2] :
                              effects_match_reg[11:9]  == 3'd1 ? stage_audio_in_signal[3] :
                              effects_match_reg[14:12] == 3'd1 ? stage_audio_in_signal[4] :
                              effects_match_reg[17:15] == 3'd1 ? stage_audio_in_signal[5] : 0;
assign gate_audio_in_en     = effects_match_reg[2:0]   == 3'd1 ? stage_audio_in_en[0] :
                              effects_match_reg[5:3]   == 3'd1 ? stage_audio_in_en[1] :
                              effects_match_reg[8:6]   == 3'd1 ? stage_audio_in_en[2] :
                              effects_match_reg[11:9]  == 3'd1 ? stage_audio_in_en[3] :
                              effects_match_reg[14:12] == 3'd1 ? stage_audio_in_en[4] :
                              effects_match_reg[17:15] == 3'd1 ? stage_audio_in_en[5] : 0;
//reverb
assign reverb_audio_in        = effects_match_reg[2:0]   == 3'd2 ? stage_audio_in[0] :
                                effects_match_reg[5:3]   == 3'd2 ? stage_audio_in[1] :
                                effects_match_reg[8:6]   == 3'd2 ? stage_audio_in[2] :
                                effects_match_reg[11:9]  == 3'd2 ? stage_audio_in[3] :
                                effects_match_reg[14:12] == 3'd2 ? stage_audio_in[4] :
                                effects_match_reg[17:15] == 3'd2 ? stage_audio_in[5] : 0;
assign reverb_audio_in_signal = effects_match_reg[2:0]   == 3'd2 ? stage_audio_in_signal[0] :
                                effects_match_reg[5:3]   == 3'd2 ? stage_audio_in_signal[1] :
                                effects_match_reg[8:6]   == 3'd2 ? stage_audio_in_signal[2] :
                                effects_match_reg[11:9]  == 3'd2 ? stage_audio_in_signal[3] :
                                effects_match_reg[14:12] == 3'd2 ? stage_audio_in_signal[4] :
                                effects_match_reg[17:15] == 3'd2 ? stage_audio_in_signal[5] : 0;
assign reverb_audio_in_en     = effects_match_reg[2:0]   == 3'd2 ? stage_audio_in_en[0] :
                                effects_match_reg[5:3]   == 3'd2 ? stage_audio_in_en[1] :
                                effects_match_reg[8:6]   == 3'd2 ? stage_audio_in_en[2] :
                                effects_match_reg[11:9]  == 3'd2 ? stage_audio_in_en[3] :
                                effects_match_reg[14:12] == 3'd2 ? stage_audio_in_en[4] :
                                effects_match_reg[17:15] == 3'd2 ? stage_audio_in_en[5] : 0;
//comp
assign comp_audio_in        = effects_match_reg[2:0]     == 3'd3 ? stage_audio_in[0] :
                                effects_match_reg[5:3]   == 3'd3 ? stage_audio_in[1] :
                                effects_match_reg[8:6]   == 3'd3 ? stage_audio_in[2] :
                                effects_match_reg[11:9]  == 3'd3 ? stage_audio_in[3] :
                                effects_match_reg[14:12] == 3'd3 ? stage_audio_in[4] :
                                effects_match_reg[17:15] == 3'd3 ? stage_audio_in[5] : 0;
assign comp_audio_in_signal = effects_match_reg[2:0]     == 3'd3 ? stage_audio_in_signal[0] :
                                effects_match_reg[5:3]   == 3'd3 ? stage_audio_in_signal[1] :
                                effects_match_reg[8:6]   == 3'd3 ? stage_audio_in_signal[2] :
                                effects_match_reg[11:9]  == 3'd3 ? stage_audio_in_signal[3] :
                                effects_match_reg[14:12] == 3'd3 ? stage_audio_in_signal[4] :
                                effects_match_reg[17:15] == 3'd3 ? stage_audio_in_signal[5] : 0;
assign comp_audio_in_en     = effects_match_reg[2:0]     == 3'd3 ? stage_audio_in_en[0] :
                                effects_match_reg[5:3]   == 3'd3 ? stage_audio_in_en[1] :
                                effects_match_reg[8:6]   == 3'd3 ? stage_audio_in_en[2] :
                                effects_match_reg[11:9]  == 3'd3 ? stage_audio_in_en[3] :
                                effects_match_reg[14:12] == 3'd3 ? stage_audio_in_en[4] :
                                effects_match_reg[17:15] == 3'd3 ? stage_audio_in_en[5] : 0;
//eq
assign eq_audio_in        = effects_match_reg[2:0]       == 3'd4 ? stage_audio_in[0]   :
                                effects_match_reg[5:3]   == 3'd4 ? stage_audio_in[1]   :
                                effects_match_reg[8:6]   == 3'd4 ? stage_audio_in[2]   :
                                effects_match_reg[11:9]  == 3'd4 ? stage_audio_in[3]  :
                                effects_match_reg[14:12] == 3'd4 ? stage_audio_in[4] :
                                effects_match_reg[17:15] == 3'd4 ? stage_audio_in[5] : 0;
assign eq_audio_in_signal = effects_match_reg[2:0]       == 3'd4 ? stage_audio_in_signal[0]   :
                                effects_match_reg[5:3]   == 3'd4 ? stage_audio_in_signal[1]   :
                                effects_match_reg[8:6]   == 3'd4 ? stage_audio_in_signal[2]   :
                                effects_match_reg[11:9]  == 3'd4 ? stage_audio_in_signal[3]  :
                                effects_match_reg[14:12] == 3'd4 ? stage_audio_in_signal[4] :
                                effects_match_reg[17:15] == 3'd4 ? stage_audio_in_signal[5] : 0;
assign eq_audio_in_en     = effects_match_reg[2:0]       == 3'd4 ? stage_audio_in_en[0]   :
                                effects_match_reg[5:3]   == 3'd4 ? stage_audio_in_en[1]   :
                                effects_match_reg[8:6]   == 3'd4 ? stage_audio_in_en[2]   :
                                effects_match_reg[11:9]  == 3'd4 ? stage_audio_in_en[3]  :
                                effects_match_reg[14:12] == 3'd4 ? stage_audio_in_en[4] :
                                effects_match_reg[17:15] == 3'd4 ? stage_audio_in_en[5] : 0;
//delay
assign delay_audio_in        = effects_match_reg[2:0]    == 3'd5 ? stage_audio_in[0]   :
                                effects_match_reg[5:3]   == 3'd5 ? stage_audio_in[1]   :
                                effects_match_reg[8:6]   == 3'd5 ? stage_audio_in[2]   :
                                effects_match_reg[11:9]  == 3'd5 ? stage_audio_in[3]  :
                                effects_match_reg[14:12] == 3'd5 ? stage_audio_in[4] :
                                effects_match_reg[17:15] == 3'd5 ? stage_audio_in[5] : 0;
assign delay_audio_in_signal = effects_match_reg[2:0]    == 3'd5 ? stage_audio_in_signal[0]   :
                                effects_match_reg[5:3]   == 3'd5 ? stage_audio_in_signal[1]   :
                                effects_match_reg[8:6]   == 3'd5 ? stage_audio_in_signal[2]   :
                                effects_match_reg[11:9]  == 3'd5 ? stage_audio_in_signal[3]  :
                                effects_match_reg[14:12] == 3'd5 ? stage_audio_in_signal[4] :
                                effects_match_reg[17:15] == 3'd5 ? stage_audio_in_signal[5] : 0;
assign delay_audio_in_en     = effects_match_reg[2:0]    == 3'd5 ? stage_audio_in_en[0]   :
                                effects_match_reg[5:3]   == 3'd5 ? stage_audio_in_en[1]   :
                                effects_match_reg[8:6]   == 3'd5 ? stage_audio_in_en[2]   :
                                effects_match_reg[11:9]  == 3'd5 ? stage_audio_in_en[3]  :
                                effects_match_reg[14:12] == 3'd5 ? stage_audio_in_en[4] :
                                effects_match_reg[17:15] == 3'd5 ? stage_audio_in_en[5] : 0;
//distr
assign distr_audio_in        = effects_match_reg[2:0]    == 3'd6 ? stage_audio_in[0]   :
                                effects_match_reg[5:3]   == 3'd6 ? stage_audio_in[1]   :
                                effects_match_reg[8:6]   == 3'd6 ? stage_audio_in[2]   :
                                effects_match_reg[11:9]  == 3'd6 ? stage_audio_in[3]  :
                                effects_match_reg[14:12] == 3'd6 ? stage_audio_in[4] :
                                effects_match_reg[17:15] == 3'd6 ? stage_audio_in[5] : 0;
assign distr_audio_in_signal = effects_match_reg[2:0]    == 3'd6 ? stage_audio_in_signal[0]   :
                                effects_match_reg[5:3]   == 3'd6 ? stage_audio_in_signal[1]   :
                                effects_match_reg[8:6]   == 3'd6 ? stage_audio_in_signal[2]   :
                                effects_match_reg[11:9]  == 3'd6 ? stage_audio_in_signal[3]  :
                                effects_match_reg[14:12] == 3'd6 ? stage_audio_in_signal[4] :
                                effects_match_reg[17:15] == 3'd6 ? stage_audio_in_signal[5] : 0;
assign distr_audio_in_en     = effects_match_reg[2:0]    == 3'd6 ? stage_audio_in_en[0]   :
                                effects_match_reg[5:3]   == 3'd6 ? stage_audio_in_en[1]   :
                                effects_match_reg[8:6]   == 3'd6 ? stage_audio_in_en[2]   :
                                effects_match_reg[11:9]  == 3'd6 ? stage_audio_in_en[3]  :
                                effects_match_reg[14:12] == 3'd6 ? stage_audio_in_en[4] :
                                effects_match_reg[17:15] == 3'd6 ? stage_audio_in_en[5] : 0;

assign out_pcm_data = effects_match_reg[17:15] == 3'd0 ? stage_audio_in[5] : 
                      effects_match_reg[17:15] == 3'd1 ? gate_audio_out    :
                      effects_match_reg[17:15] == 3'd2 ? reverb_audio_out  :
                      effects_match_reg[17:15] == 3'd3 ? comp_audio_out    :
                      effects_match_reg[17:15] == 3'd4 ? eq_audio_out      :
                      effects_match_reg[17:15] == 3'd5 ? delay_audio_out   :
                      effects_match_reg[17:15] == 3'd6 ? distr_audio_out   :in_pcm_data;
assign out_pcm_data_signal = effects_match_reg[17:15] == 3'd0 ? stage_audio_in_signal[5] : 
                             effects_match_reg[17:15] == 3'd1 ? gate_audio_out_signal    :
                             effects_match_reg[17:15] == 3'd2 ? reverb_audio_out_signal  :
                             effects_match_reg[17:15] == 3'd3 ? comp_audio_out_signal    :
                             effects_match_reg[17:15] == 3'd4 ? eq_audio_out_signal      :
                             effects_match_reg[17:15] == 3'd5 ? delay_audio_out_signal   :
                             effects_match_reg[17:15] == 3'd6 ? distr_audio_out_signal   : in_pcm_data_signal;


assign effects_audio_out_en     = out_pcm_work_enable;
assign effects_audio_out_signal = out_pcm_data_signal;
assign effects_audio_out = out_pcm_data;

/********************************************************/
/*                   实例化                             */
/********************************************************/
effects_gate effects_gate_effects_inst1(
    .sys_clk  (sys_clk  )  ,
    .sys_rst_n(sys_rst_n)  ,
    .configure_en  (gate_configure_en  ) ,
    .gate_threshold(gate_gate_threshold) ,
    .gate_attack   (gate_gate_attack   ) ,
    .gate_release  (gate_gate_release  ) ,
    .gate_ready    (gate_gate_ready    ) ,
    .audio_in        (gate_audio_in        ),
    .audio_in_signal (gate_audio_in_signal ),
    .audio_in_en     (gate_audio_in_en     ),
    .audio_out       (gate_audio_out       ),
    .audio_out_signal(gate_audio_out_signal),
    .audio_out_en    (gate_audio_out_en)
    );

effects_reverb effects_reverb_effects_inst1(
    .sys_clk  (sys_clk  ),
    .sys_rst_n(sys_rst_n),
    .configure_en    (reverb_configure_en    ),
    .reverb_param    (reverb_reverb_param),
    .configure_signal(reverb_configure_signal),
    .reverb_ready    (reverb_reverb_ready    ),
    .audio_in        (reverb_audio_in        ),
    .audio_in_signal (reverb_audio_in_signal ),
    .audio_in_en     (reverb_audio_in_en     ),
    .audio_out       (reverb_audio_out       ),
    .audio_out_signal(reverb_audio_out_signal),
    .audio_out_en    (reverb_audio_out_en)
    );

effects_comp effects_comp_effects_inst1(
    .sys_clk  (sys_clk  )  ,
    .sys_rst_n(sys_rst_n)  ,
    .configure_en   (comp_configure_en   ),
    .comp_alpha     (comp_comp_alpha     ),
    .comp_threshold (comp_comp_threshold ),
    .comp_ratio_turn(comp_comp_ratio_turn),
    .comp_attack    (comp_comp_attack    ),
    .comp_release   (comp_comp_release   ),
    .comp_gain      (comp_comp_gain      ),
    .comp_ready     (comp_comp_ready     ),
    .audio_in        (comp_audio_in        ),
    .audio_in_signal (comp_audio_in_signal ),
    .audio_in_en     (comp_audio_in_en     ),
    .audio_out       (comp_audio_out       ),
    .audio_out_signal(comp_audio_out_signal),
    .audio_out_en    (comp_audio_out_en)
    );

effects_eq effects_eq_effects_inst1(
    .sys_clk  (sys_clk  )  ,
    .sys_rst_n(sys_rst_n)  ,
    .configure_en    (eq_configure_en    ),
    .eq_config_data  (eq_eq_config_data  ),
    .configure_signal(eq_configure_signal),
    .eq_ready        (eq_eq_ready        ),
    .audio_in        (eq_audio_in        ),
    .audio_in_signal (eq_audio_in_signal ),
    .audio_in_en     (eq_audio_in_en     ),
    .audio_out       (eq_audio_out       ),
    .audio_out_signal(eq_audio_out_signal),
    .audio_out_en(eq_audio_out_en)
    );

effects_delay effects_delay_effects_inst1(
    .sys_clk  (sys_clk  ),
    .sys_rst_n(sys_rst_n),
    .configure_en(delay_configure_en),
    .delay_length(delay_delay_length), 
    .mix         (delay_mix         ), 
    .back_volume (delay_back_volume ), 
    .delay_ready (delay_delay_ready ),
    .audio_in       (delay_audio_in       ),
    .audio_in_signal(delay_audio_in_signal),
    .audio_in_en    (delay_audio_in_en    ),
    .audio_out       (delay_audio_out       )   ,
    .audio_out_signal(delay_audio_out_signal)   ,
    .audio_out_en    (delay_audio_out_en)
    );

effects_distr effects_distr_effects_inst1(
    .sys_clk  (sys_clk  )  ,
    .sys_rst_n(sys_rst_n)  ,
    .configure_en (distr_configure_en ),
    .distort_gain (distr_distort_gain ), // 失真前增益
    .distort_max  (distr_distort_max  ), // 失真阈值
    .distort_ready(distr_distort_ready),
    .audio_in        (distr_audio_in        ),
    .audio_in_signal (distr_audio_in_signal ),
    .audio_in_en     (distr_audio_in_en     ),
    .audio_out       (distr_audio_out       ),
    .audio_out_signal(distr_audio_out_signal),
    .audio_out_en    (distr_audio_out_en)
    );

pcm1808_in audio_ts_in_effects_inst(
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .audio_clk(audio_clk),
    .audio_clk_locked(sys_rst_n),
    .FMT(FMT),
    .MD0(MD0),
    .MD1(MD1),
    .sclk(sclk),
    .bck (bck),// sclk = 256*bck
    .lrck(lrck),//bck = 32*lrck
    .dout(dout),
    .audio_valid (in_pcm_ready)   ,
    .audio_signal(in_pcm_data_signal)   ,
    .audio_data(in_pcm_data)
    );
assign effects_clear_audio_ready = in_pcm_ready;
assign effects_clear_audio_out = in_pcm_data;
assign effects_clear_audio_out_signal = in_pcm_data_signal;

audio_ts_out audio_ts_out_effects_inst(
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .audio_clk(audio_clk),        
    .pcm_work_enable(out_pcm_work_enable), 
    .pcm_data(out_pcm_data),  
    .pcm_data_signal(out_pcm_data_signal),  
    .DAC_SCK (DAC_SCK ),         
    .DAC_BCLK(DAC_BCLK),         
    .DAC_LRCK(DAC_LRCK),        
    .DAC_DIN (DAC_DIN )         
);
endmodule
