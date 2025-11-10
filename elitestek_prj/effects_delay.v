`timescale 1ns / 1ps


module effects_delay#(
    parameter AUDIO_WIDTH = 'd32,// 输入音频数据宽度
    parameter REFERENCE_WIDTH = 'd10,// 2^10 = 1024 移位参考位宽
    parameter SAMPLE_SPEED = 'd48000// 采样率
)(
    input wire          sys_clk,
    input wire          sys_rst_n,
    // 配置接口
    input wire          configure_en,
    input wire [11:0]   delay_length, // 延迟长度
    input wire [9:0]    mix, // 干声比例
    input wire [9:0]    back_volume, // 反馈音量
    output reg          delay_ready,
    // 输入音频数据接口
    input wire signed [AUDIO_WIDTH-1:0]   audio_in,
    input wire          audio_in_signal,// 输入音频数据有效信号，翻转时数据更新
    input wire          audio_in_en,// 输入音频数据使能，该信号拉高时准备接收
    // 输出音频数据接口
    output reg signed [AUDIO_WIDTH-1:0]   audio_out,
    output reg          audio_out_signal,
    output reg          audio_out_en
    );

//delay_mixing_ratio = mix/MIX_SHIFT 使用先乘后移位以替代除法
// output_data = (1 - delay_mixing_ratio) * 
//               input_data + delay_mixing_ratio * delay_data
// delay_data = back_volume * output_data / BACK_SHIFT
//fifo:16384*32

//参数配置分支
localparam MIX_INIT = 1<<REFERENCE_WIDTH / 2; // 默认值 512
localparam BACK_INIT = 1<<REFERENCE_WIDTH / 2; // 默认值 512
localparam DELAY_LENGTH_INIT = SAMPLE_SPEED / 8; // 默认值 6000
reg  [REFERENCE_WIDTH:0]  mix_reg = MIX_INIT; 
reg  [REFERENCE_WIDTH:0]  back_volume_reg = BACK_INIT; 
reg  [11:0] delay_length_reg = DELAY_LENGTH_INIT; 
// 配置使能信号打拍
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
        //状态机寄存器初始化
        config_state <= CONFIG_IDLE;
        config_state_cnt <= 0;
        //参数寄存器初始化
        delay_length_reg <= DELAY_LENGTH_INIT;
        mix_reg <= MIX_INIT;
        back_volume_reg <= BACK_INIT;
        delay_ready <= 0;
    end
    else begin
        case (config_state)
            CONFIG_IDLE: begin
                //上电直接进入配置状态
                config_state <= CONFIGURE;
                config_state_cnt <= 0;
                //参数寄存器初始化
                delay_length_reg <= DELAY_LENGTH_INIT;
                mix_reg <= MIX_INIT;
                back_volume_reg <= BACK_INIT;
                delay_ready <= 0;
            end
            CONFIGURE: begin
                if (config_state_cnt == 2'd0) begin
                    if(!configure_en_reg0 && configure_en) begin
                        config_state_cnt<= config_state_cnt + 1'b1;
                    end
                end 
                else if (config_state_cnt == 2'd1) begin
                    delay_length_reg<= delay_length;
                    mix_reg         <= {1'b0,mix};
                    back_volume_reg <= {1'b0,back_volume};
                    config_state_cnt<= config_state_cnt + 1'b1;
                end 
                else if (config_state_cnt == 2'd2) begin
                    delay_ready     <= 1'b1;
                    if (!configure_en_reg0 && configure_en) begin
                        config_state_cnt<= 2'd1;
                        delay_ready     <= 1'b0;
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
// FIFO 控制信号
reg  [15:0] fifo_cnt; // FIFO 读写计数器
reg         fifo_wr_en;// FIFO 写使能
reg         fifo_rd_en;// FIFO 读使能
//wire        fifo_full;// FIFO 满标志
reg         fifo_rst_n;// FIFO 复位信号
wire [AUDIO_WIDTH-1:0] fifo_output_data;// FIFO输出的数据
reg  [AUDIO_WIDTH-1:0] fifo_input_data;// 输入FIFO的数据
fifo_generator_0 delay_fifo_inst1(
    .clk_i  (sys_clk),
    .wr_en_i(fifo_wr_en),
    .rd_en_i(fifo_rd_en),
    .wdata  (fifo_input_data),
    .rdata  (fifo_output_data),
    .a_rst_i(~fifo_rst_n)
);

localparam MIX_SHIFT = 1024;;// 2^10 = 1024,对应mix的取值范围0~1024,1<<REFERENCE_WIDTH
localparam BACK_SHIFT = 1024;// 2^10 = 1024,对应back_volume的取值范围0~1024
// 计算过程变量寄存
reg  signed [AUDIO_WIDTH-1:0]    audio_in_reg; // 输入音频数据寄存
reg  signed [AUDIO_WIDTH+REFERENCE_WIDTH-1:0] temp_mix_data1; // 计算混音的临时变量1
reg  signed [AUDIO_WIDTH+REFERENCE_WIDTH-1:0] temp_mix_data2; // 计算混音的临时变量2
reg  signed [AUDIO_WIDTH+REFERENCE_WIDTH-1+1:0] temp_mix_data; // 计算混音的临时变量
reg  signed [AUDIO_WIDTH-1:0]    output_data; // 输出数据寄存
reg  signed [AUDIO_WIDTH+REFERENCE_WIDTH-1:0] temp_back_data; // 计算反馈音量的临时变量
reg  signed [AUDIO_WIDTH-1:0]    delay_data; // 延迟数据寄存
// 输入音频数据打拍
reg audio_in_signal_reg0;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        audio_in_signal_reg0 <= 1'b0;
    end else begin
        audio_in_signal_reg0 <= audio_in_signal;
    end
end
// 音频处理状态机
localparam EFFECT_DELAY_IDLE    = 'd0;
localparam EFFECT_DELAY_WORK    = 'd1;
reg [0:0] state;
reg [3:0] effect_state_cnt;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        //状态机寄存器初始化
        state <= EFFECT_DELAY_IDLE;
        effect_state_cnt <= 0;
        // fifo 控制信号初始化
        fifo_rst_n <= 1;
        fifo_wr_en <= 0;
        fifo_rd_en <= 0;
        fifo_input_data <= 0;
        fifo_cnt <= 0;
        // 计算过程变量寄存初始化
        audio_in_reg <= 0;
        temp_mix_data <= 0;
        temp_mix_data1 <= 0;
        temp_mix_data2 <= 0;
        output_data <= 0;
        delay_data <= 0;
        temp_back_data <= 0;
        // 模块输出信号初始化
        audio_out_signal <= 0;
        audio_out <= 0;
        audio_out_en <= 0;

    end else begin
        case (state)
            EFFECT_DELAY_IDLE: begin
                // 状态寄存器初始化
                effect_state_cnt <= 0;
                // fifo 控制信号初始化
                fifo_rst_n <= 1; // Release Reset FIFO
                fifo_wr_en <= 0;
                fifo_rd_en <= 0;
                fifo_input_data <= 0;
                fifo_cnt <= 0;
                // 计算过程变量寄存初始化
                temp_mix_data <= 0;
                temp_mix_data1 <= 0;
                temp_mix_data2 <= 0;
                output_data <= 0;
                delay_data <= 0;
                temp_back_data <= 0;
                // 模块输出信号初始化
                audio_out_signal <= 0;
                audio_out <= 0;
                audio_out_en <= 0;
                if (delay_ready && audio_in_en) begin
                    state <= EFFECT_DELAY_WORK;
                end
            end
            EFFECT_DELAY_WORK: begin
                // 拆分计算过程
                // 1. temp_mix_data1 = (MIX_SHIFT - mix) * input_data
                // 2. temp_mix_data2 = mix * delay_data
                // 3. temp_mix_data = temp_mix_data1 + temp_mix_data2
                // 4. output_data = temp_mix_data >> 10
                // 5. temp_back_data = back_volume * output_data
                // 6. delay_data = temp_back_data >> 10 
                audio_out_en <= 1'b1; // Enable audio output
                fifo_rst_n <= 1'b0;
                if (effect_state_cnt == 0) begin
                    if(audio_in_signal_reg0 != audio_in_signal) begin
                        if(fifo_cnt < delay_length_reg) begin
                            // FIFO未填满，直接写入当前音频数据
                            fifo_input_data <= audio_in;
                            fifo_wr_en <= 1'b1; 
                            audio_out <= audio_in;
                            audio_out_signal <= ~audio_out_signal; 
                            effect_state_cnt <= effect_state_cnt +1;                         
                        end else if(fifo_cnt >= delay_length_reg) begin
                            // FIFO已填满，开始延迟处理
                            effect_state_cnt <= effect_state_cnt + 1'b1;
                            fifo_rd_en <= 1'b1; // Read from FIFO
                            audio_in_reg <= audio_in;
                        end
                    end
                end
                else if(effect_state_cnt == 1) begin
                    if(fifo_cnt < delay_length_reg) begin
                        fifo_wr_en <= 1'b0; // Stop writing to FIFO
                        fifo_input_data <= 0;
                        fifo_cnt <= fifo_cnt + 1'b1;
                        effect_state_cnt <= 0; //返回到准备接收状态
                    end
                    else if(fifo_cnt >= delay_length_reg) begin
                        fifo_rd_en <= 0; // Stop reading from FIFO
                        temp_mix_data1 <= $signed(audio_in_reg * (MIX_SHIFT - mix_reg));
                        temp_mix_data2 <= $signed(fifo_output_data * mix_reg);
                        effect_state_cnt <= effect_state_cnt + 1'b1;
                    end
                end
                else if (effect_state_cnt == 2) begin
                    temp_mix_data <= temp_mix_data1 + temp_mix_data2;
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if (effect_state_cnt == 3) begin
                    output_data <= temp_mix_data >>> REFERENCE_WIDTH;
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if (effect_state_cnt == 4) begin
                    temp_back_data <= $signed(output_data * back_volume_reg);
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if (effect_state_cnt == 5) begin
                    delay_data <= $signed(temp_back_data >>> REFERENCE_WIDTH);
                    fifo_input_data <= delay_data;
                    fifo_wr_en <= 1'b1;
                    audio_out <= output_data;
                    audio_out_signal <= ~audio_out_signal; 
                    effect_state_cnt <= effect_state_cnt + 1'b1;
                end
                else if (effect_state_cnt == 6) begin
                    fifo_wr_en <= 1'b0;
                    fifo_input_data <= 0;
                    effect_state_cnt <= 0; // Reset state counter for next sample
                end    
                // 如果参数未配置完成，回到IDLE状态（audio_in_en可以不用理,没有audio_in_signal也不会进入工作状态）            
                //if (!delay_ready) state <= EFFECT_DELAY_IDLE;
                //else state <= EFFECT_DELAY_WORK;
            end
        endcase
        end
end

endmodule
