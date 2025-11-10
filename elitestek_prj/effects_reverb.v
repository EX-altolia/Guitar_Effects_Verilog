`timescale 1ns / 1ps

module effects_reverb #(
    parameter AUDIO_WIDTH = 'd32,// 输入音频数据宽度
    parameter SAMPLE_SPEED = 'd48000// 采样率
)(
    input wire                  sys_clk,
    input wire                  sys_rst_n,

    input wire                  configure_en,
    input wire signed [15:0]    reverb_param,// 配置数据,权重移位（乘以weight后>>>16),tap点直接传原地址
    //input wire signed [15:0]    reverb_weight,
    input wire                  configure_signal,
    output reg                  reverb_ready,

    // 输入音频数据接口
    input wire signed [AUDIO_WIDTH-1:0]   audio_in,
    input wire          audio_in_signal,
    input wire          audio_in_en,
    // 输出音频数据接口
    output reg signed [AUDIO_WIDTH-1:0]   audio_out,
    output reg          audio_out_signal,
    output reg          audio_out_en
);

reg   [15:0]    reverb_tap_reg[0:15];
reg  signed [16:0]    reverb_weight_reg[0:15];

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
reg [9:0] config_state_cnt;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        config_state <= CONFIG_IDLE;
        config_state_cnt <= 0;
        reverb_tap_reg[0] <= 0;reverb_tap_reg[1] <= 0;reverb_tap_reg[2] <= 0;reverb_tap_reg[3] <= 0;reverb_tap_reg[4] <= 0;
        reverb_tap_reg[5] <= 0;reverb_tap_reg[6] <= 0;reverb_tap_reg[7] <= 0;reverb_tap_reg[8] <= 0;reverb_tap_reg[9] <= 0;
        reverb_tap_reg[10] <= 0;reverb_tap_reg[11] <= 0;reverb_tap_reg[12] <= 0;reverb_tap_reg[13] <= 0;reverb_tap_reg[14] <= 0;
        reverb_tap_reg[15] <= 0;
        reverb_weight_reg[0] <= 0;reverb_weight_reg[1] <= 0;reverb_weight_reg[2] <= 0;reverb_weight_reg[3] <= 0;reverb_weight_reg[4] <= 0;
        reverb_weight_reg[5] <= 0;reverb_weight_reg[6] <= 0;reverb_weight_reg[7] <= 0;reverb_weight_reg[8] <= 0;reverb_weight_reg[9] <= 0;
        reverb_weight_reg[10]<= 0;reverb_weight_reg[11] <= 0;reverb_weight_reg[12] <= 0;reverb_weight_reg[13] <= 0;reverb_weight_reg[14] <= 0;
        reverb_weight_reg[15]<= 0;
        reverb_ready <= 0;
    end
    else begin
        case(config_state)
            CONFIG_IDLE: begin
                reverb_ready <= 'b0;
                config_state <= CONFIGURE;
                config_state_cnt <= 0;
                reverb_tap_reg[0] <= 0;reverb_tap_reg[1] <= 0;reverb_tap_reg[2] <= 0;reverb_tap_reg[3] <= 0;reverb_tap_reg[4] <= 0;
                reverb_tap_reg[5] <= 0;reverb_tap_reg[6] <= 0;reverb_tap_reg[7] <= 0;reverb_tap_reg[8] <= 0;reverb_tap_reg[9] <= 0;
                reverb_tap_reg[10] <= 0;reverb_tap_reg[11] <= 0;reverb_tap_reg[12] <= 0;reverb_tap_reg[13] <= 0;reverb_tap_reg[14] <= 0;
                reverb_tap_reg[15] <= 0;
                reverb_weight_reg[0] <= 0;reverb_weight_reg[1] <= 0;reverb_weight_reg[2] <= 0;reverb_weight_reg[3] <= 0;reverb_weight_reg[4] <= 0;
                reverb_weight_reg[5] <= 0;reverb_weight_reg[6] <= 0;reverb_weight_reg[7] <= 0;reverb_weight_reg[8] <= 0;reverb_weight_reg[9] <= 0;
                reverb_weight_reg[10]<= 0;reverb_weight_reg[11] <= 0;reverb_weight_reg[12] <= 0;reverb_weight_reg[13] <= 0;reverb_weight_reg[14] <= 0;
                reverb_weight_reg[15]<= 0;
            end 
            CONFIGURE: begin
                if(config_state_cnt == 0) begin
                    if(!configure_en_reg0 && configure_en) begin
                        config_state_cnt<= config_state_cnt + 1'b1;
                    end
                end
                else if(config_state_cnt <= 'd16 && config_state_cnt >= 1 && configure_signal) begin
                    reverb_tap_reg[config_state_cnt-1] <= reverb_param; 
                    config_state_cnt <= config_state_cnt + 1'b1;
                end
                else if(config_state_cnt < 'd32 && config_state_cnt > 'd16 && configure_signal) begin
                    reverb_weight_reg[config_state_cnt-16] <= {1'b0,reverb_param};
                    config_state_cnt <= config_state_cnt + 1'b1;
                end
                else if(config_state_cnt == 'd32) begin
                    reverb_ready <= 'b1;
                    if(!configure_en_reg0 && configure_en) begin
                        reverb_ready <= 0;
                        config_state_cnt <= 'd1;
                    end
                end
            end
            default: begin
                config_state <= CONFIG_IDLE;
            end
        endcase
    end
end

// 混响处理流程建议如下：
// 1. 接收输入音频数据 audio_in，并存入环形缓冲区（RAM），地址由 reverb_shift_cnt 控制。
// 2. 初始化 reverb_tap2addr 数组，使其存储每个 tap 的原始延迟地址（即 reverb_tap_reg[i]）。
// 3. 每次处理时，将 reverb_tap2addr[i] 加上当前偏移量 reverb_shift_cnt，得到本次混响需要读取的 RAM 地址。
// 4. 检查 reverb_tap2addr[i] 是否超出 RAM 深度（如 1024），若超出则减去 1024，实现地址循环（环形缓冲区）。
// 5. 依次从 RAM 读出各 tap 点的数据，与对应权重 reverb_weight_reg[i] 相乘后累加，完成混响合成。
// 6. 输出处理后的音频数据 audio_out。
// 7. 更新偏移量 reverb_shift_cnt，每次处理后加一，若溢出 1024 则归零，实现环形缓冲区的循环。
// 8. 继续等待下一个音频输入，重复上述流程。

localparam EFFECT_REVERB_IDLE = 'd0;
localparam EFFECT_REVERB_WORK = 'd1;
reg [4:0] reverb_cnt;
reg [4:0] ram_read_cnt;
reg [15:0] reverb_tap2addr[15:0];
reg [15:0] reverb_shift_cnt;
reg signed [31:0] reverb_data_reg;

reg         reverb_ram_wr_en;
reg [9:0]   reverb_ram_wr_addr;
reg signed [31:0] reverb_ram_wr_data;
reg         reverb_ram_rd_en;//也设置为高有效
reg [9:0]   reverb_ram_rd_addr;
wire signed [31:0] reverb_ram_rd_data;
reg  signed [31:0] audio_in_reg;
reg audio_in_signal_reg0;

blk_mem_gen_0 reverb_ram_inst1(
    .re     (reverb_ram_rd_en),
    .rdata_b(reverb_ram_rd_data),
    .raddr  (reverb_ram_rd_addr),

    .we     (reverb_ram_wr_en),
    .waddr  (reverb_ram_wr_addr),
    .wdata_a(reverb_ram_wr_data),
    
    .clk(sys_clk)
    );

always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        audio_in_signal_reg0 <= 1'b0;
    end else begin
        audio_in_signal_reg0 <= audio_in_signal;
    end
end


integer i;
reg [1:0] state;
reg [3:0] effect_state_cnt;
always@(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state <= EFFECT_REVERB_IDLE;
        effect_state_cnt <= 0;
        audio_out <= 0;
        audio_out_en <= 0;
        audio_out_signal <= 0;
        reverb_cnt <= 0;
        for (i = 0; i < 16; i = i + 1) begin
            reverb_tap2addr[i] <= 0;
        end
        reverb_ram_wr_en <= 0;
        reverb_ram_wr_addr <= 0;
        reverb_ram_wr_data <= 0;
        reverb_ram_rd_en <= 0;
        reverb_ram_rd_addr <= 0;
        reverb_shift_cnt <= 0;
        ram_read_cnt <= 0;
        reverb_data_reg <= 0;
    end
    else begin
        case(state)
            EFFECT_REVERB_IDLE: begin
                effect_state_cnt <= 0;
                audio_out <= 0;
                audio_out_en <= 0;
                audio_out_signal <= 0;
                reverb_cnt <= 0;
                for (i = 0; i < 16; i = i + 1) begin
                    reverb_tap2addr[i] <= 0;
                end
                reverb_ram_wr_en <= 0;
                reverb_ram_wr_addr <= 0;
                reverb_ram_wr_data <= 0;
                reverb_ram_rd_en <= 0;
                reverb_ram_rd_addr <= 0;
                reverb_shift_cnt <= 0;
                ram_read_cnt <= 0;
                reverb_data_reg <= 0;
                if (audio_in_en && reverb_ready) begin
                    state <= EFFECT_REVERB_WORK;
                end
            end
            EFFECT_REVERB_WORK: begin
                audio_out_en <= 'b1;
                if(effect_state_cnt == 0) begin// 寄存，触发处理
                    if(audio_in_signal != audio_in_signal_reg0) begin
                        audio_in_reg <= audio_in;
                        effect_state_cnt <= effect_state_cnt + 'b1;
                    end
                end
                else if(effect_state_cnt == 1) begin// 混响操作
                    if(reverb_cnt == 0) begin//存入当前点
                        reverb_ram_wr_en <= 1;
                        reverb_ram_wr_data <= audio_in_reg;
                        reverb_ram_wr_addr <= reverb_shift_cnt;
                        reverb_cnt <= reverb_cnt + 1;
                    end
                    else if(reverb_cnt == 1) begin
                        for (i = 0; i < 16; i = i + 1) begin
                            reverb_tap2addr[i] <= (reverb_tap_reg[i] + reverb_shift_cnt) % 1024;
                        end
                        reverb_cnt <= reverb_cnt + 1;
                    end
                    else if(reverb_cnt == 2) begin//合成混响音频
                        if(ram_read_cnt == 0) begin
                            reverb_ram_rd_en <= 1;
                            reverb_ram_rd_addr <= reverb_tap2addr[0];
                            reverb_data_reg <= 0;
                            ram_read_cnt <= ram_read_cnt + 1;
                        end
                        else if(ram_read_cnt < 'd16 && ram_read_cnt >= 1) begin
                            reverb_ram_rd_addr <= reverb_tap2addr[ram_read_cnt];
                            reverb_ram_rd_en <= 1;
                            if(reverb_ram_rd_data[31] == 0)
                                reverb_data_reg <= $signed(reverb_data_reg + (({reverb_ram_rd_data} * {15'b0,reverb_weight_reg[ram_read_cnt-1]})>>> 16));
                            else if(reverb_ram_rd_data[31] == 1)
                                reverb_data_reg <= $signed(reverb_data_reg - (({~reverb_ram_rd_data} * {15'b0,reverb_weight_reg[ram_read_cnt-1]})>>> 16));
                            ram_read_cnt <= ram_read_cnt + 1;
                        end
                        else if(ram_read_cnt == 'd16) begin
                            reverb_ram_rd_en <= 0;
                            if(reverb_ram_rd_data[31] == 0)
                                reverb_data_reg <= $signed(reverb_data_reg + (({reverb_ram_rd_data} * {15'b0,reverb_weight_reg[ram_read_cnt-1]})>>> 16));
                            else if(reverb_ram_rd_data[31] == 1)
                                reverb_data_reg <= $signed(reverb_data_reg - (({~reverb_ram_rd_data} * {15'b0,reverb_weight_reg[ram_read_cnt-1]})>>> 16));
                            ram_read_cnt <= 0;
                            reverb_cnt <= reverb_cnt + 1;
                        end
                    end
                    else if(reverb_cnt == 3) begin//处理偏移量地址，如果已经到达末尾，则+1操作应该回到原点
                        if(reverb_shift_cnt >= 'd1023) reverb_shift_cnt <= 0;//////////////////////////////////////////////偏移值为多少应该归零？
                        else reverb_shift_cnt <= reverb_shift_cnt + 1;
                        reverb_cnt <= reverb_cnt + 1;
                    end
                    else if(reverb_cnt == 4) begin// 跳出混响处理环节
                        reverb_cnt <= 0;
                        effect_state_cnt <= effect_state_cnt + 1;
                    end
                end
                else if(effect_state_cnt == 2) begin
                    audio_out <= reverb_data_reg;
                    audio_out_signal <= ~audio_out_signal;
                    effect_state_cnt <= 0;
                end
                
                //if(!reverb_ready) state <= EFFECT_REVERB_IDLE;
            end
        endcase
    end
end

endmodule
















