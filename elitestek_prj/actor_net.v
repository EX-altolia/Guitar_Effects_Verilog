`timescale 1ns / 1ps

module actor_net(
    input wire          sys_clk,
    input wire          sys_rst_n,

    input wire          feature_back_ready,
    input wire          feature_back_wren,
    input wire signed [7:0]    feature_back_data,
    //动作输出
    output reg          net_output_valid,
    output reg          net_output_wr_en,
    output reg signed [7:0]   net_output_data 
);

parameter FEATURE_NUM = 'd96;//输入特征数
parameter ACTION_NUM = 'd44;//输出动作数
parameter ACTION_GEN_NUM = 'd24;//动作所产生的参数数量

parameter INPUT_NET_HANG = 'd96;//输入层行数
parameter INPUT_NET_LIE = 'd128;//输入层列数
parameter HIDDEN_NET_HANG = 'd128;//隐藏层行数
parameter HIDDEN_NET_LIE = 'd128;//隐藏层列数
parameter OUTPUT_NET_HANG = 'd128;//输出层行数
parameter OUTPUT_NET_LIE = 'd11;//输出层列数

reg signed [7:0] feature_buf [0:FEATURE_NUM-1];//输入特征缓存
reg  [6:0] feature_back_cnt;//输入特征计数
reg        feature_back_wren_reg0;
reg signed [7:0] feature_back_data_reg0;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        feature_back_wren_reg0 <= 0;
        feature_back_data_reg0 <= 0;
    end else begin
        feature_back_wren_reg0 <= feature_back_wren;
        feature_back_data_reg0 <= feature_back_data;
    end
end

// 参数 ROM（并行度 4）
reg         [11:0]  params_weight_rom_addr;
reg                 params_weight_rom_rd_en;
reg  signed [7:0]   params_weight_rom_data [0:3];
reg         [7:0]   params_bias_rom_addr;
reg                 params_bias_rom_rd_en;
reg  signed [31:0]  params_bias_rom_data [0:3];
//各个rom：3层，每层4个并行，rom数量为24个，3*2*4
wire signed [7:0]   input_weight_rom_data [0:3];
wire signed [31:0]  input_bias_rom_data [0:3];

wire signed [7:0]   hidden_weight_rom_data [0:3];
wire signed [31:0]  hidden_bias_rom_data [0:3];

wire signed [7:0]   output_weight_rom_data [0:3];    
wire signed [31:0]  output_bias_rom_data [0:3];



always @(*) begin
    case (net_state)
        NET_STATE_INPUT_NET: begin
            params_weight_rom_data[0] = input_weight_rom_data[0];
            params_weight_rom_data[1] = input_weight_rom_data[1];
            params_weight_rom_data[2] = input_weight_rom_data[2];
            params_weight_rom_data[3] = input_weight_rom_data[3];

            params_bias_rom_data[0] = input_bias_rom_data[0];
            params_bias_rom_data[1] = input_bias_rom_data[1];
            params_bias_rom_data[2] = input_bias_rom_data[2];
            params_bias_rom_data[3] = input_bias_rom_data[3];
        end
        NET_STATE_HIDDEN_NET: begin
            params_weight_rom_data[0] = hidden_weight_rom_data[0];
            params_weight_rom_data[1] = hidden_weight_rom_data[1];
            params_weight_rom_data[2] = hidden_weight_rom_data[2];
            params_weight_rom_data[3] = hidden_weight_rom_data[3];

            params_bias_rom_data[0] = hidden_bias_rom_data[0];
            params_bias_rom_data[1] = hidden_bias_rom_data[1];
            params_bias_rom_data[2] = hidden_bias_rom_data[2];
            params_bias_rom_data[3] = hidden_bias_rom_data[3];
        end
        NET_STATE_OUTPUT_NET: begin
            params_weight_rom_data[0] = output_weight_rom_data[0];
            params_weight_rom_data[1] = output_weight_rom_data[1];
            params_weight_rom_data[2] = output_weight_rom_data[2];
            params_weight_rom_data[3] = output_weight_rom_data[3];

            params_bias_rom_data[0] = output_bias_rom_data[0];
            params_bias_rom_data[1] = output_bias_rom_data[1];
            params_bias_rom_data[2] = output_bias_rom_data[2];
            params_bias_rom_data[3] = output_bias_rom_data[3];
        end
        default: begin
            params_weight_rom_data[0] = 0;
            params_weight_rom_data[1] = 0;
            params_weight_rom_data[2] = 0;
            params_weight_rom_data[3] = 0;

            params_bias_rom_data[0] = 0;
            params_bias_rom_data[1] = 0;
            params_bias_rom_data[2] = 0;
            params_bias_rom_data[3] = 0;
        end
    endcase
end


// 行列计数
reg  [9:0]  net_hang_cnt;    //行计数（输入索引）
reg  [9:0]  net_lie_cnt;     //列计数（输出索引）

// 累加寄存器（列方向并行 4 路）
reg signed [31:0] net_channel_prereg [0:3];
reg signed [31:0] input_net_output[0:INPUT_NET_LIE-1];
reg signed [31:0] hidden_net_output [0:HIDDEN_NET_LIE-1];
reg signed [31:0] output_net_output [0:OUTPUT_NET_LIE-1];
// 网络状态机
localparam NET_STATE_IDLE         = 3'd0,
           NET_STATE_INPUT_NET    = 3'd1,
           NET_STATE_HIDDEN_NET   = 3'd2,
           NET_STATE_OUTPUT_NET   = 3'd3,
           NET_STATE_ACTION_OUT   = 3'd4;

reg   [2:0] net_state;
reg   [7:0] net_state_cnt;
reg   [7:0] action_cnt;    
reg   [7:0] output_num_cnt;
reg   [7:0] output_byte_cnt;
reg         wr_toggle; 

integer i;
integer remaining_cols;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        net_state <= NET_STATE_IDLE;
        net_state_cnt <= 0;
        feature_back_cnt <= 0;
        net_output_valid <= 0;
        net_output_wr_en <= 0;
        net_output_data <= 0;
        net_hang_cnt <= 0;
        net_lie_cnt <= 0;
        params_weight_rom_addr <= 0;
        params_weight_rom_rd_en <= 0;
        params_bias_rom_addr <= 0;
        params_bias_rom_rd_en <= 0;
        action_cnt <= 0;
        wr_toggle <= 0;
        output_num_cnt <= 0;
        output_byte_cnt <=0;
        for (i = 0; i < FEATURE_NUM; i = i + 1)
            feature_buf[i] <= 0;
        for (i = 0; i < 4; i = i + 1) begin
            net_channel_prereg[i]     <= 0;
        end
        for (i = 0; i < INPUT_NET_LIE; i = i + 1)
            input_net_output[i] <= 0;
        for (i = 0; i < HIDDEN_NET_LIE; i = i + 1)
            hidden_net_output[i] <= 0;
        for (i = 0; i < OUTPUT_NET_LIE; i = i + 1)
            output_net_output[i] <= 0;
    end else begin
        case(net_state)
        NET_STATE_IDLE: begin
            if(feature_back_ready) begin
                if(feature_back_wren_reg0 && (feature_back_cnt < FEATURE_NUM-1)) begin
                    feature_buf[feature_back_cnt] <= feature_back_data_reg0;
                    feature_back_cnt <= feature_back_cnt + 1;
                end 
                else if(feature_back_wren_reg0 && (feature_back_cnt == FEATURE_NUM-1)) begin
                    feature_buf[feature_back_cnt] <= feature_back_data_reg0;
                    feature_back_cnt <= 0;
                    net_state <= NET_STATE_INPUT_NET;
                    net_state_cnt <= 0;
                    net_hang_cnt <= 0;
                    net_lie_cnt <= 0;
                    // 清空累加寄存器
                    net_channel_prereg[0] <= 0;
                    net_channel_prereg[1] <= 0;
                    net_channel_prereg[2] <= 0;
                    net_channel_prereg[3] <= 0;

                end
            end
            end
        NET_STATE_INPUT_NET: begin
            if (net_lie_cnt < INPUT_NET_LIE/4) begin
                if (net_hang_cnt < INPUT_NET_HANG) begin
                    case(net_state_cnt)
                        0: begin
                            // 设置 ROM 地址（一次读取4列对应的权重）
                            // 行：net_hang_cnt，对应输入索引
                            // 列：net_lie_cnt ~ net_lie_cnt+3，对应4个输出节点
                            params_weight_rom_addr <= net_lie_cnt * INPUT_NET_HANG + net_hang_cnt;
                            params_weight_rom_rd_en <= 1;
                            // 只在一行开始时读取 bias
                            if (net_hang_cnt == 0) begin
                                params_bias_rom_addr <= net_lie_cnt;
                                params_bias_rom_rd_en <= 1;
                            end
                            net_state_cnt <= 1;
                        end
                        1: begin
                            params_weight_rom_rd_en <= 0;
                            params_bias_rom_rd_en   <= 0;
                            net_state_cnt <= 2;
                        end
                        2: begin
                            // 4列并行累加加权结果
                            net_channel_prereg[0] <= net_channel_prereg[0] + feature_buf[net_hang_cnt] * params_weight_rom_data[0];
                            net_channel_prereg[1] <= net_channel_prereg[1] + feature_buf[net_hang_cnt] * params_weight_rom_data[1];
                            net_channel_prereg[2] <= net_channel_prereg[2] + feature_buf[net_hang_cnt] * params_weight_rom_data[2];
                            net_channel_prereg[3] <= net_channel_prereg[3] + feature_buf[net_hang_cnt] * params_weight_rom_data[3];
                            // 行累加计数
                            if (net_hang_cnt == INPUT_NET_HANG - 1) begin
                                // 行末：加上 bias
                                input_net_output[net_lie_cnt + 0*INPUT_NET_LIE/4] <= net_channel_prereg[0] + params_bias_rom_data[0];
                                input_net_output[net_lie_cnt + 1*INPUT_NET_LIE/4] <= net_channel_prereg[1] + params_bias_rom_data[1];
                                input_net_output[net_lie_cnt + 2*INPUT_NET_LIE/4] <= net_channel_prereg[2] + params_bias_rom_data[2];
                                input_net_output[net_lie_cnt + 3*INPUT_NET_LIE/4] <= net_channel_prereg[3] + params_bias_rom_data[3];

                                // 清空累加器
                                net_channel_prereg[0] <= 0;
                                net_channel_prereg[1] <= 0;
                                net_channel_prereg[2] <= 0;
                                net_channel_prereg[3] <= 0;

                                // 判断是否完成所有输出列
                                if (net_lie_cnt >= INPUT_NET_LIE/4 - 1) begin
                                    net_lie_cnt <= 0;
                                    net_hang_cnt <= 0;
                                    net_state <= NET_STATE_HIDDEN_NET; // 跳转下一层
                                end else begin
                                    net_lie_cnt <= net_lie_cnt + 1;
                                    net_hang_cnt <= 0;
                                end
                                net_state_cnt <= 0;
                            end else begin
                                // 继续下一输入行
                                net_hang_cnt <= net_hang_cnt + 1;
                                net_state_cnt <= 0;
                            end
                        end
                    endcase
                end
            end
            end
        NET_STATE_HIDDEN_NET: begin
            if (net_lie_cnt < HIDDEN_NET_LIE/4) begin
                if (net_hang_cnt < HIDDEN_NET_HANG) begin
                    case(net_state_cnt)
                        0: begin
                            params_weight_rom_addr <= net_lie_cnt * HIDDEN_NET_HANG + net_hang_cnt;
                            params_weight_rom_rd_en <= 1;
                            if (net_hang_cnt == 0) begin
                                params_bias_rom_addr <= net_lie_cnt;
                                params_bias_rom_rd_en <= 1;
                            end
                            net_state_cnt <= 1;
                        end
                        1: begin
                            params_weight_rom_rd_en <= 0;
                            params_bias_rom_rd_en   <= 0;
                            net_state_cnt <= 2;
                        end
                        2: begin
                            // 4列并行累加加权结果
                            net_channel_prereg[0] <= net_channel_prereg[0] + input_net_output[net_hang_cnt] * params_weight_rom_data[0];
                            net_channel_prereg[1] <= net_channel_prereg[1] + input_net_output[net_hang_cnt] * params_weight_rom_data[1];
                            net_channel_prereg[2] <= net_channel_prereg[2] + input_net_output[net_hang_cnt] * params_weight_rom_data[2];
                            net_channel_prereg[3] <= net_channel_prereg[3] + input_net_output[net_hang_cnt] * params_weight_rom_data[3];
                            // 行累加计数
                            if (net_hang_cnt == HIDDEN_NET_HANG - 1) begin
                                // 行末：加上 bias
                                hidden_net_output[net_lie_cnt + 0*HIDDEN_NET_LIE/4] <= net_channel_prereg[0] + params_bias_rom_data[0];
                                hidden_net_output[net_lie_cnt + 1*HIDDEN_NET_LIE/4] <= net_channel_prereg[1] + params_bias_rom_data[1];
                                hidden_net_output[net_lie_cnt + 2*HIDDEN_NET_LIE/4] <= net_channel_prereg[2] + params_bias_rom_data[2];
                                hidden_net_output[net_lie_cnt + 3*HIDDEN_NET_LIE/4] <= net_channel_prereg[3] + params_bias_rom_data[3];

                                // 清空累加器
                                net_channel_prereg[0] <= 0;
                                net_channel_prereg[1] <= 0;
                                net_channel_prereg[2] <= 0;
                                net_channel_prereg[3] <= 0;

                                // 判断是否完成所有输出列
                                if (net_lie_cnt >= HIDDEN_NET_LIE/4 - 1) begin
                                    net_lie_cnt <= 0;
                                    net_hang_cnt <= 0;
                                    net_state <= NET_STATE_OUTPUT_NET; // 跳转下一层
                                end else begin
                                    net_lie_cnt <= net_lie_cnt + 1;
                                    net_hang_cnt <= 0;
                                end
                                net_state_cnt <= 0;
                            end else begin
                                // 继续下一输入行
                                net_hang_cnt <= net_hang_cnt + 1;
                                net_state_cnt <= 0;
                            end
                        end
                    endcase
                end
            end
            end
        NET_STATE_OUTPUT_NET: begin
            if (net_lie_cnt < (OUTPUT_NET_LIE + 3)/4) begin
                if (net_hang_cnt < OUTPUT_NET_HANG) begin
                    case(net_state_cnt)
                        0: begin
                            params_weight_rom_addr <= net_lie_cnt * OUTPUT_NET_HANG + net_hang_cnt;
                            params_weight_rom_rd_en <= 1;
                            if (net_hang_cnt == 0) begin
                                params_bias_rom_addr <= net_lie_cnt;
                                params_bias_rom_rd_en <= 1;
                            end
                            net_state_cnt <= 1;
                        end
                        1: begin
                            params_weight_rom_rd_en <= 0;
                            params_bias_rom_rd_en   <= 0;
                            net_state_cnt <= 2;
                        end
                        2: begin
                        remaining_cols = OUTPUT_NET_LIE - net_lie_cnt*4;

                        for (i = 0; i < 4; i = i + 1) begin
                            if (i < remaining_cols) begin
                                net_channel_prereg[i] <= net_channel_prereg[i] + hidden_net_output[net_hang_cnt] * params_weight_rom_data[i];
                            end
                        end

                        if (net_hang_cnt == OUTPUT_NET_HANG - 1) begin
                            for (i = 0; i < 4; i = i + 1) begin
                                if (i < remaining_cols) begin
                                    output_net_output[net_lie_cnt*4 + i] <= net_channel_prereg[i] + params_bias_rom_data[i];
                                    net_channel_prereg[i] <= 0; // 清空累加器
                                end
                            end

                            if (net_lie_cnt >= (OUTPUT_NET_LIE + 3)/4 - 1) begin
                                net_lie_cnt <= 0;
                                net_hang_cnt <= 0;
                                net_state <= NET_STATE_ACTION_OUT;
                            end else begin
                                net_lie_cnt <= net_lie_cnt + 1;
                                net_hang_cnt <= 0;
                            end
                            net_state_cnt <= 0;
                        end else begin
                            net_hang_cnt <= net_hang_cnt + 1;
                            net_state_cnt <= 0;
                        end
                    end
                    endcase
                end
            end
        end
        NET_STATE_ACTION_OUT: begin
            if (net_state_cnt == 0) begin
                action_cnt <= 0;
                net_output_valid <= 1;
                net_output_wr_en <= 0;
                net_state_cnt <= 1;  // 进入下一状态，开始计算索引
                output_num_cnt <= 0;
                output_byte_cnt <=0;
            end else if (net_state_cnt == 1) begin
                case(action_cnt)
                    0: begin//计算当前应该发送哪个字节，已经发送到第几个动作了（共十一个动作OUTPUT_NET_LIE = 'd11;reg signed [31:0] output_net_output [0:OUTPUT_NET_LIE-1];
                        if(output_num_cnt < OUTPUT_NET_LIE) begin
                            action_cnt <= 1;
                        end else if(output_num_cnt == OUTPUT_NET_LIE) begin
                            action_cnt <= 6;
                        end
                    end
                    1: begin//发送第一字节output_net_output[int32_index][7:0]
                        net_output_data <= output_net_output[output_num_cnt][7:0];
                        net_output_wr_en <= 1;
                        output_byte_cnt <= 2;
                        action_cnt <= 5;
                    end
                    2: begin//发送第二字节output_net_output[int32_index][15:8]
                        net_output_data <= output_net_output[output_num_cnt][15:8];
                        net_output_wr_en <= 1;
                        output_byte_cnt <= 3;
                        action_cnt <= 5;
                    end
                    3: begin//发送第三字节output_net_output[int32_index]...
                        net_output_data <= output_net_output[output_num_cnt][23:16];
                        net_output_wr_en <= 1;
                        output_byte_cnt <= 4;
                        action_cnt <= 5;
                    end
                    4: begin//发送第四字节output_net_output[int32_index]...
                        net_output_data <= output_net_output[output_num_cnt][31:24];
                        net_output_wr_en <= 1;
                        output_byte_cnt <= 0;
                        action_cnt <= 5;
                        output_num_cnt <= output_num_cnt + 1;
                    end
                    5: begin//空一拍
                        net_output_wr_en <= 0;
                        action_cnt <= output_byte_cnt;
                    end
                    6: begin//发送完所有的，令net_state_cnt == 2
                        net_output_data <= 0;
                        net_output_wr_en <= 0;
                        output_byte_cnt <= 0;
                        action_cnt <= 0;
                        net_state_cnt <= 2;
                    end
                endcase
                
            end else if (net_state_cnt == 2) begin
                    // 输出结束，恢复状态
                    net_output_wr_en <= 0;
                    net_output_valid <= 0;
                    net_state <= NET_STATE_IDLE;
                    net_state_cnt <= 0;
            end
        end
        default:;
        endcase
    end
end

// ==================== input_net ROM ====================
// bias
bias_rom_128x32b_40 input_bias_rom0( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(input_bias_rom_data[0])); 
bias_rom_128x32b_41 input_bias_rom1( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(input_bias_rom_data[1])); 
bias_rom_128x32b_42 input_bias_rom2( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(input_bias_rom_data[2])); 
bias_rom_128x32b_43 input_bias_rom3( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(input_bias_rom_data[3])); 
// weight
weight_rom_4096x8b_50 input_weight_rom0( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(input_weight_rom_data[0])); 
weight_rom_4096x8b_51 input_weight_rom1( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(input_weight_rom_data[1])); 
weight_rom_4096x8b_52 input_weight_rom2( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(input_weight_rom_data[2])); 
weight_rom_4096x8b_53 input_weight_rom3( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(input_weight_rom_data[3])); 

// ==================== hidden_net ROM ====================
// bias
bias_rom_128x32b_20 hidden_bias_rom0( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(hidden_bias_rom_data[0])); 
bias_rom_128x32b_21 hidden_bias_rom1( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(hidden_bias_rom_data[1])); 
bias_rom_128x32b_22 hidden_bias_rom2( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(hidden_bias_rom_data[2])); 
bias_rom_128x32b_23 hidden_bias_rom3( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(hidden_bias_rom_data[3])); 
// weight
weight_rom_4096x8b_30 hidden_weight_rom0( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(hidden_weight_rom_data[0])); 
weight_rom_4096x8b_31 hidden_weight_rom1( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(hidden_weight_rom_data[1])); 
weight_rom_4096x8b_32 hidden_weight_rom2( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(hidden_weight_rom_data[2])); 
weight_rom_4096x8b_33 hidden_weight_rom3( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(hidden_weight_rom_data[3])); 

// ==================== output_net ROM ====================
// bias
bias_rom_128x32b_00 output_bias_rom0( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(output_bias_rom_data[0])); 
bias_rom_128x32b_01 output_bias_rom1( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(output_bias_rom_data[1])); 
bias_rom_128x32b_02 output_bias_rom2( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(output_bias_rom_data[2])); 
bias_rom_128x32b_03 output_bias_rom3( .clk(sys_clk), .re(params_bias_rom_rd_en), .addr(params_bias_rom_addr), .rdata_a(output_bias_rom_data[3])); 
// weight
weight_rom_4096x8b_10 output_weight_rom0( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(output_weight_rom_data[0])); 
weight_rom_4096x8b_11 output_weight_rom1( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(output_weight_rom_data[1])); 
weight_rom_4096x8b_12 output_weight_rom2( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(output_weight_rom_data[2])); 
weight_rom_4096x8b_13 output_weight_rom3( .clk(sys_clk), .re(params_weight_rom_rd_en), .addr(params_weight_rom_addr), .rdata_a(output_weight_rom_data[3])); 


endmodule
    


