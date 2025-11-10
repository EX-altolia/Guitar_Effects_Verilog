`timescale 1ns / 1ps

module effects_eq#(
    parameter AUDIO_WIDTH = 'd32,// 输入音频数据宽度
    parameter SAMPLE_SPEED = 'd48000// 采样率
)(
    input wire          sys_clk,
    input wire          sys_rst_n,

    input wire          configure_en,
    input wire signed [15:0]   eq_config_data,// 配置数据,
    input wire          configure_signal,
    output reg          eq_ready,

    // 输入音频数据接口
    input wire signed [AUDIO_WIDTH-1:0]   audio_in,
    input wire          audio_in_signal,
    input wire          audio_in_en,
    // 输出音频数据接口
    output reg signed [AUDIO_WIDTH-1:0]   audio_out,
    output reg          audio_out_signal,
    output reg          audio_out_en
);

// 三段三阶均衡器参数寄存器
reg signed [15:0] eq_params_reg [0:14];// b0,b1,b2,a1,a2 低中高
// 配置使能信号打拍
reg     configure_en_reg0;
reg     configure_signal_reg0;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        configure_en_reg0 <= 1'b0;
        configure_signal_reg0 <= 1'b0;
    end else begin
        configure_en_reg0 <= configure_en;
        configure_signal_reg0 <= configure_signal;
    end
end
// 参数配置状态机
localparam CONFIG_IDLE = 2'd0;
localparam CONFIGURE  = 2'd1;
reg [1:0] config_state;
reg [7:0] config_state_cnt;   
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        //状态机寄存器初始化
        config_state <= CONFIG_IDLE;
        config_state_cnt <= 0;
        //参数寄存器初始化
        eq_params_reg[0] <= 0;eq_params_reg[1] <= 0;eq_params_reg[2] <= 0;eq_params_reg[3] <= 0;eq_params_reg[4] <= 0;
        eq_params_reg[5] <= 0;eq_params_reg[6] <= 0;eq_params_reg[7] <= 0;eq_params_reg[8] <= 0;eq_params_reg[9] <= 0;
        eq_params_reg[10] <= 0;eq_params_reg[11] <= 0;eq_params_reg[12] <= 0;eq_params_reg[13] <= 0;eq_params_reg[14] <= 0;
        eq_ready <= 1'b0;
    end
    else begin
        case (config_state)
            CONFIG_IDLE: begin
                eq_ready <= 1'b0;
                config_state <= CONFIGURE;
                eq_params_reg[0] <= 0;eq_params_reg[1] <= 0;eq_params_reg[2] <= 0;eq_params_reg[3] <= 0;eq_params_reg[4] <= 0;
                eq_params_reg[5] <= 0;eq_params_reg[6] <= 0;eq_params_reg[7] <= 0;eq_params_reg[8] <= 0;eq_params_reg[9] <= 0;
                eq_params_reg[10] <= 0;eq_params_reg[11] <= 0;eq_params_reg[12] <= 0;eq_params_reg[13] <= 0;eq_params_reg[14] <= 0;
            end
            CONFIGURE: begin
                if (config_state_cnt == 0) begin
                    if(!configure_en_reg0 && configure_en) begin
                        config_state_cnt<= config_state_cnt + 1'b1;
                    end
                end
                else if(config_state_cnt < 'd16 && configure_signal && config_state_cnt >0) begin
                    eq_params_reg[config_state_cnt-1] <= eq_config_data;
                    config_state_cnt <= config_state_cnt + 1'b1;
                end
                else if(config_state_cnt == 'd16) begin
                    eq_ready <= 1'b1;
                    if(!configure_en_reg0 && configure_en) begin
                        config_state_cnt <= 'd1;
                        eq_ready <= 1'b0;
                    end
                end
            end
            default: begin
                config_state <= CONFIG_IDLE;
            end
        endcase
    end
end

// 音频处理分支
//  y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2]
//         - a1*y[n-1] - a2*y[n-2]
// 以n_1代替n-1, n_2代替n-2
reg signed [47:0] eq_perstage_out;
reg signed [47:0] eq_perstage_x_n_1[0:2];
reg signed [47:0] eq_perstage_x_n_2[0:2];
reg signed [47:0] eq_perstage_y_n_1[0:2];
reg signed [47:0] eq_perstage_y_n_2[0:2];
reg signed [47:0] eq_perbranch_reg[0:4];//每个分支的计算值
reg signed [47:0] eq_eq_perstage_out_reg;
reg signed [31:0] audio_in_reg;
reg [4:0] eq_perbranch_cnt;

reg audio_in_signal_reg0;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        audio_in_signal_reg0 <= 1'b0;
    end else begin
        audio_in_signal_reg0 <= audio_in_signal;
    end
end

localparam EFFECT_EQ_IDLE = 'd0;
localparam EFFECT_EQ_WORK = 'd1;
reg [1:0] state;
reg [3:0] effect_state_cnt;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state <= EFFECT_EQ_IDLE;
        effect_state_cnt <= 4'd0;
        audio_in_reg <= 0;
        audio_out <= 'd0;
        audio_out_en <= 1'b0;
        audio_out_signal <= 1'b0;
        eq_eq_perstage_out_reg <= 'd0;
        eq_perstage_out<= 'd0;
        eq_perbranch_cnt <= 0;
        eq_perstage_x_n_1[0] <= 'd0; eq_perstage_x_n_1[1] <= 'd0; eq_perstage_x_n_1[2] <= 'd0;
        eq_perstage_x_n_2[0] <= 'd0; eq_perstage_x_n_2[1] <= 'd0; eq_perstage_x_n_2[2] <= 'd0;
        eq_perstage_y_n_1[0] <= 'd0; eq_perstage_y_n_1[1] <= 'd0; eq_perstage_y_n_1[2] <= 'd0;
        eq_perstage_y_n_2[0] <= 'd0; eq_perstage_y_n_2[1] <= 'd0; eq_perstage_y_n_2[2] <= 'd0;
        eq_perbranch_reg[0] <= 'd0; eq_perbranch_reg[1] <= 'd0; eq_perbranch_reg[2] <= 'd0;
        eq_perbranch_reg[3] <= 'd0; eq_perbranch_reg[4] <= 'd0;
    end
    else begin
        case(state)
            EFFECT_EQ_IDLE: begin
                effect_state_cnt <= 4'd0;
                audio_out <= 'd0;
                audio_out_en <= 1'b0;
                audio_out_signal <= 1'b0;
                eq_eq_perstage_out_reg <= 'd0;
                eq_perstage_out <= 'd0;
                eq_perstage_x_n_1[0] <= 'd0; eq_perstage_x_n_1[1] <= 'd0; eq_perstage_x_n_1[2] <= 'd0;
                eq_perstage_x_n_2[0] <= 'd0; eq_perstage_x_n_2[1] <= 'd0; eq_perstage_x_n_2[2] <= 'd0;
                eq_perstage_y_n_1[0] <= 'd0; eq_perstage_y_n_1[1] <= 'd0; eq_perstage_y_n_1[2] <= 'd0;
                eq_perstage_y_n_2[0] <= 'd0; eq_perstage_y_n_2[1] <= 'd0; eq_perstage_y_n_2[2] <= 'd0;
                eq_perbranch_reg[0] <= 'd0; eq_perbranch_reg[1] <= 'd0; eq_perbranch_reg[2] <= 'd0;
                eq_perbranch_reg[3] <= 'd0; eq_perbranch_reg[4] <= 'd0;
                if (audio_in_en && eq_ready) begin
                    state <= EFFECT_EQ_WORK;
                end
            end
            EFFECT_EQ_WORK: begin
                audio_out_en <= 1'b1;
                if(effect_state_cnt == 0) begin
                    if(audio_in_signal != audio_in_signal_reg0) begin
                        audio_in_reg <= audio_in;
                        effect_state_cnt <= effect_state_cnt + 'b1;
                    end
                end
                else if(effect_state_cnt == 1) begin
                    //  y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2]
                    //         - a1*y[n-1] - a2*y[n-2]
                    //低频
                    if(eq_perbranch_cnt == 0) begin
                        eq_perbranch_reg[0] <= $signed(eq_params_reg[0] * audio_in_reg        );    
                        eq_perbranch_reg[1] <= $signed(eq_params_reg[1] * eq_perstage_x_n_1[0]);
                        eq_perbranch_reg[2] <= $signed(eq_params_reg[2] * eq_perstage_x_n_2[0]);
                        eq_perbranch_reg[3] <= $signed(eq_params_reg[3] * eq_perstage_y_n_1[0]);
                        eq_perbranch_reg[4] <= $signed(eq_params_reg[4] * eq_perstage_y_n_2[0]);
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;                        
                    end
                    else if(eq_perbranch_cnt == 1) begin
                        eq_perstage_out <= $signed(eq_perbranch_reg[0]+eq_perbranch_reg[1] +eq_perbranch_reg[2]);
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;    
                    end
                    else if(eq_perbranch_cnt == 2) begin
                        eq_perstage_out <= $signed(eq_perstage_out - eq_perbranch_reg[3] - eq_perbranch_reg[4])>>>'d13;
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;
                    end
                    else if(eq_perbranch_cnt == 3) begin
                        eq_perstage_x_n_2[0] <= eq_perstage_x_n_1[0];
                        eq_perstage_y_n_2[0] <= eq_perstage_y_n_1[0];
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;
                    end
                    else if(eq_perbranch_cnt == 4) begin
                        eq_perstage_x_n_1[0] <= {{16{audio_in_reg[31]}}, audio_in_reg[31:0]};
                        eq_perstage_y_n_1[0] <= eq_perstage_out;
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;
                    end
                    //中频
                    if(eq_perbranch_cnt == 5) begin
                        eq_eq_perstage_out_reg <= eq_perstage_out;
                        eq_perbranch_reg[0] <= $signed(eq_params_reg[0+5] * eq_perstage_out       );
                        eq_perbranch_reg[1] <= $signed(eq_params_reg[1+5] * eq_perstage_x_n_1[0+1]);
                        eq_perbranch_reg[2] <= $signed(eq_params_reg[2+5] * eq_perstage_x_n_2[0+1]);
                        eq_perbranch_reg[3] <= $signed(eq_params_reg[3+5] * eq_perstage_y_n_1[0+1]);
                        eq_perbranch_reg[4] <= $signed(eq_params_reg[4+5] * eq_perstage_y_n_2[0+1]);
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;                        
                    end
                    else if(eq_perbranch_cnt == 6) begin
                        eq_perstage_out <= $signed(eq_perbranch_reg[0]+eq_perbranch_reg[1] +eq_perbranch_reg[2]);
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;    
                    end
                    else if(eq_perbranch_cnt == 7) begin
                        eq_perstage_out <= $signed(eq_perstage_out - eq_perbranch_reg[3] - eq_perbranch_reg[4])>>>'d13;
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;
                    end
                    else if(eq_perbranch_cnt == 8) begin
                        eq_perstage_x_n_2[0+1] <= eq_perstage_x_n_1[0+1];
                        eq_perstage_y_n_2[0+1] <= eq_perstage_y_n_1[0+1];
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;
                    end
                    else if(eq_perbranch_cnt == 9) begin
                        eq_perstage_x_n_1[0+1] <= eq_eq_perstage_out_reg;
                        eq_perstage_y_n_1[0+1] <= eq_perstage_out;
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;
                    end
                    //高频
                    if(eq_perbranch_cnt == 10) begin
                        eq_eq_perstage_out_reg <= eq_perstage_out;
                        eq_perbranch_reg[0] <= $signed(eq_params_reg[0+5+5] * eq_perstage_out         );
                        eq_perbranch_reg[1] <= $signed(eq_params_reg[1+5+5] * eq_perstage_x_n_1[0+1+1]);
                        eq_perbranch_reg[2] <= $signed(eq_params_reg[2+5+5] * eq_perstage_x_n_2[0+1+1]);
                        eq_perbranch_reg[3] <= $signed(eq_params_reg[3+5+5] * eq_perstage_y_n_1[0+1+1]);
                        eq_perbranch_reg[4] <= $signed(eq_params_reg[4+5+5] * eq_perstage_y_n_2[0+1+1]);
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;                        
                    end
                    else if(eq_perbranch_cnt == 11) begin
                        eq_perstage_out <= $signed(eq_perbranch_reg[0]+eq_perbranch_reg[1] +eq_perbranch_reg[2]);
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;    
                    end
                    else if(eq_perbranch_cnt == 12) begin
                        eq_perstage_out <= $signed(eq_perstage_out - eq_perbranch_reg[3] - eq_perbranch_reg[4])>>>'d13;
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;
                    end
                    else if(eq_perbranch_cnt == 13) begin
                        eq_perstage_x_n_2[0+1+1] <= eq_perstage_x_n_1[0+1+1];
                        eq_perstage_y_n_2[0+1+1] <= eq_perstage_y_n_1[0+1+1];
                        eq_perbranch_cnt <= eq_perbranch_cnt + 'b1;
                    end
                    else if(eq_perbranch_cnt == 14) begin
                        eq_perstage_x_n_1[0+1+1] <= eq_eq_perstage_out_reg;
                        eq_perstage_y_n_1[0+1+1] <= eq_perstage_out;
                        eq_perbranch_cnt <= 'b0;
                        effect_state_cnt <= effect_state_cnt + 'b1;
                    end
                end
                else if(effect_state_cnt == 2) begin
                    audio_out <= {eq_perstage_out[47],eq_perstage_out[30:0]};
                    audio_out_signal <= ~audio_out_signal; 
                    effect_state_cnt <= 0;
                end

                //if(!eq_ready) state <= EFFECT_EQ_IDLE;
            end
        endcase
    end
end


endmodule
