module udp_work_ctrl(
    input   wire            sys_clk         ,
    input   wire            sys_rst_n       ,   //系统复位,低电平有效
    input   wire            sys_2xclk       ,
    //以太网接口
    input   wire            eth_clk         ,   //PHY芯片时钟信号
    input   wire            eth_rxdv_r      ,   //PHY芯片输入数据有效信号
    input   wire    [1:0]   eth_rx_data_r   ,   //PHY芯片输入数据
    output  wire            eth_tx_en_r     ,   //PHY芯片输出数据有效信号
    output  wire    [1:0]   eth_tx_data_r   ,   //PHY芯片输出数据
    //效果器参数存储ram接口
    output wire             params_ram_clk      , 
    output reg  [9:0]       params_ram_addr     ,
    output wire             params_ram_rw_en    ,//读写使能，高电平写，低电平读
    output reg  [7:0]       params_ram_wr_data  ,
    input  wire [7:0]       params_ram_rd_data  ,
    output reg  [17:0]      params_match_reg    ,
    output reg              params_change_en    ,//完成参数写入，一个高电平脉冲通知效果器模块
    //特征计算相关接口
    output reg              feature_get_enable  ,//网络模块发起要求
    input  wire             feature_wav_ready   ,//音频接口，与效果器模块一致（有效，翻转，数据）
    input  wire             feature_wav_signal  ,
    input  wire [31:0]      feature_wav_data    ,
    output reg              feature_wav_select  ,//选择干湿声
    output reg              feature_back_ready  ,
    output reg              feature_back_wren   ,//特征输出接口，与fifo模块一致
    output reg  [7:0]       feature_back_data   ,//假设量化为8位
    output reg              net_input_enable    ,//网络模块发起要求
    input  wire             net_input_valid     ,
    input  wire             net_input_wr_en     ,
    input  wire [7:0]       net_input_data
    );

parameter   BOARD_MAC   = 48'h12_34_56_78_9a_bc ;   //板卡MAC地址
parameter   BOARD_IP    = 32'hA9_FE_01_17       ;   //板卡IP地址
parameter   BOARD_PORT  = 16'd1234              ;   //板卡端口号
parameter   PC_MAC      = 48'hE0_D5_5E_4A_DB_2D ;   //PC机MAC地址
parameter   PC_IP       = 32'hC0_A8_00_F5       ;   //PC机IP地址
parameter   PC_PORT     = 16'd1234              ;   //PC机端口号

wire            rec_end         ;   //单包数据接收完成信号
wire            rec_en          ;   //接收数据使能信号
wire   [7:0]    rec_data        ;   //接收数据
wire   [15:0]   rec_byte_num    ;   //接收有效数据字节数
reg    [15:0]   tx_byte_num     ;
wire            send_end        ;   //发送完成信号
wire            read_data_req   ;   //读数据请求信号
reg             send_en         ;   //数据开始发送信号
wire   [7:0]    send_data       ;   //发送数据
wire            eth_rxdv        ;   //输入数据有效信号(mii)
wire   [3:0]    eth_rx_data     ;   //输入数据(mii)
reg             eth_tx_en       ;   //输出数据有效信号(mii)
wire   [3:0]    eth_tx_data     ;   //输出数据(mii)

//clk_25m:mii时钟 
reg clk_25m ; 
//mii时钟 
always@(negedge eth_clk or negedge sys_rst_n) 
    if(sys_rst_n == 1'b0) clk_25m <= 1'b0;
    else clk_25m <= ~clk_25m;



//输入mii转为gmii
reg             eth_rxdv_reg    ;   //数据有效信号打拍
reg     [3:0]   eth_rx_data_reg ;   //输入数据打拍
reg             data_sw_en      ;   //数据拼接使能信号
reg             gmii_rx_dv      ;   //拼接后的数据使能信号
reg     [7:0]   gmii_rxd        ;   //拼接后的数据

//eth_rxdv_reg:数据有效信号打拍
always@(negedge clk_25m or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        eth_rxdv_reg    <=  1'b0;
    else
        eth_rxdv_reg    <=  eth_rxdv;
//eth_rx_data_reg:输入数据打拍
always@(negedge clk_25m or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        eth_rx_data_reg <=  4'b0;
    else
        eth_rx_data_reg <=  eth_rx_data;
//data_sw_en:数据拼接使能
always@(negedge clk_25m or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        data_sw_en  <=  1'b0;
    else    if(eth_rxdv_reg == 1'b1)
        data_sw_en  <=  ~data_sw_en;
    else
        data_sw_en  <=  1'b0;
//gmii_rx_dv:拼接后的数据使能信号
always@(negedge clk_25m or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        gmii_rx_dv <=  1'b0;
    else
        gmii_rx_dv <=  data_sw_en;
//gmii_rxd:拼接后的数据
always@(posedge clk_25m or negedge sys_rst_n)
    if(sys_rst_n == 1'b0)
        gmii_rxd    <=  8'b0;
    else    if((eth_rxdv_reg == 1'b1) && (data_sw_en == 1'b0))
        gmii_rxd    <=  {eth_rx_data,eth_rx_data_reg};
    else
        gmii_rxd    <=  gmii_rxd;
// UDP模块的输出信号 (25MHz时钟域)
wire        gmii_tx_en      ;
wire [7:0]  gmii_txd        ; 
reg [1:0]   tx_state;    
reg         gmii_tx_en_reg;
reg [12:0] tx_byte_cnt;
always @(posedge clk_25m or negedge sys_rst_n) begin
    if (!sys_rst_n) 
        gmii_tx_en_reg <= 0;
    else 
        gmii_tx_en_reg <= gmii_tx_en;
end
fifo_1024x8b_2048x4b fifo_1024x8b_2048x4b_inst(//注意：这里后面修改成了2048x8b，因为包括协议内容不止这么点数据
    .clk_i(clk_25m),
    .a_rst_i(~sys_rst_n || send_end),
    .wr_en_i(gmii_tx_en),
    .wdata(gmii_txd),
    .rd_en_i(eth_tx_en),
    .rdata(eth_tx_data)
    );

always @(posedge clk_25m or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        eth_tx_en <= 0;
        tx_state <= 0;
        tx_byte_cnt <= 0;
    end
    else begin
        case(tx_state)
            0: begin
                tx_byte_cnt <= 0;
                if(gmii_tx_en == 1 && gmii_tx_en_reg == 0) begin 
                    tx_state <= 1;
                    tx_byte_cnt <= tx_byte_cnt + 1;
                end
            end
            1: begin
                if(gmii_tx_en == 1 && gmii_tx_en_reg == 1) begin
                    tx_byte_cnt <= tx_byte_cnt + 1;
                end
                else if(gmii_tx_en == 0 && gmii_tx_en_reg == 1) begin
                    tx_byte_cnt <= (tx_byte_cnt + 1) <<< 1;
                    tx_state <= 2;
                    eth_tx_en <= 1;
                end
            end
            2: begin
                if(tx_byte_cnt > 1) begin
                    eth_tx_en <= 1;
                    tx_byte_cnt <= tx_byte_cnt -1;
                end
                else if(tx_byte_cnt <= 1) begin
                    eth_tx_en <= 0;
                    tx_byte_cnt <= 0;
                    tx_state <= 0;
                end
            end
        endcase
    end
end 
/********************************************************************/
/********************************************************************/
/**********************      控制代码               ******************/
/********************************************************************/
/********************************************************************/
parameter PARAMS_NUM = 'd126;
parameter FEATURE_POINT_NUM  = 'd256;   // 每个UDP包包含的采样点数
parameter FEATURE_SEND_TIMES = 'd400;   // 每次特征采集需发送的UDP包数量
parameter FEATURE_BYTE_PER_SAMPLE = 'd4;// 每个采样点字节数(32bit)
parameter FEATURE_NUM_BACK = 'd96;      // 回传特征数量（8bit）
parameter ACTION_NUM = 'd44;        // 网络输出动作数量（8bit）

wire  [7:0]   rx_fifo_rd_data   ;	
reg           rx_fifo_rd_en     ;
reg   [7:0]   tx_fifo_wr_data   ;
reg           tx_fifo_wr_en     ;
reg           feature_wav_signal_reg0;
reg           net_input_wr_en_reg0; 
reg   [31:0]  feature_wav_reg;
reg   [10:0]  feature_write_cnt;   // 当前样本写入字节计数(0~3)
reg           feature_new_valid;   // 当前是否有新样本待写
reg   [7:0]   feature_back_cnt;           // 已接收回传特征数量
reg   [7:0]   net_action_cnt;            // 已接收网络输出动作数量
reg   [15:0]  feature_send_cnt;           // 已发送UDP包数量
reg   [15:0]  feature_point_cnt;          // 当前UDP包中点数计数
reg           feature_sending;            // 标记当前是否处于发送状态

reg   [15:0]  ram_addr_cnt; 
reg   [15:0]  rec_byte_num_reg;
reg           rec_en_reg0;
reg           rec_pkt_done_reg0;

// udp任务状态机
// 面向三个任务：电脑调整fpga效果器参数 EFFECTS_CHANGE
//              电脑要求发送音频样本后返回特征GET_FEATURE进行推理
//              电脑主动读取效果器参数READ_PARAMS
//              电脑主动要求进行推理
localparam UDP_STATE_IDLE  = 'd0;//完成任务或者初始化后的空闲态
localparam UDP_STATE_EFFECTS_CHANGE = 'd1;//电脑调整效果器参数
localparam UDP_STATE_GET_FEATURE = 'd2;//获取音频特征进行推理
localparam UDP_STATE_READ_PARAMS = 'd3;//读取效果器参数
reg [3:0] udp_work_state;
//udp_data_signals任务类型数据，是输入/输出的第一byte（电脑向fpga发送的要，反之不用）
// 'h11;  UDP_STATE_EFFECTS_CHANGE
// 'h22;  UDP_STATE_GET_FEATURE
// 'h33;  UDP_STATE_READ_PARAMS
reg [7:0] udp_data_signals; 
reg       udp_work_done;
reg [9:0] state_work_cnt;
reg       params_ram_rd_en;
reg       params_ram_wr_en;

assign params_ram_rw_en = params_ram_wr_en;
assign params_ram_clk = sys_clk;

//基本标志信号打拍
always@(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n) begin
		rec_en_reg0 <= 0;			
        feature_wav_signal_reg0 <= 0;
        net_input_wr_en_reg0 <= 0;
    end else begin
		rec_en_reg0 <= rec_en;
        feature_wav_signal_reg0 <= feature_wav_signal;
        net_input_wr_en_reg0 <= net_input_wr_en;
    end    
end

//状态机主体
always@(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)begin
        send_en <= 0;
        udp_work_done <= 0;
        state_work_cnt <= 0;
        udp_work_state <= UDP_STATE_IDLE;

        rx_fifo_rd_en <= 0;
        tx_fifo_wr_data <= 0;
        tx_fifo_wr_en <= 0;
        udp_data_signals <= 0;
        rec_byte_num_reg <= 0;
        ram_addr_cnt <= 0;
        
        params_ram_wr_en <= 0;
        params_ram_wr_data <= 0;
        params_ram_addr <= 0;
        params_ram_rd_en <= 0;
        params_change_en <= 0;
        feature_get_enable <= 0;
        feature_back_ready <= 0;
        feature_back_wren <= 0;
        feature_back_data <= 0;
        feature_point_cnt <= 0;
        feature_send_cnt <= 0;
        feature_sending <= 0;
        feature_write_cnt <= 0;
        feature_back_cnt <= 0;
        net_action_cnt <= 0;
        net_input_enable <= 0;
        feature_new_valid <= 0;
        feature_wav_reg <= 0;
    end
    else begin
        case(udp_work_state)
        UDP_STATE_IDLE: begin
            send_en <= 0;
            udp_work_done <= 0;
            tx_fifo_wr_data <= 0;
            tx_fifo_wr_en <= 0;
            ram_addr_cnt <= 0;
            params_ram_wr_en <= 0;
            params_ram_wr_data <= 0;
            params_ram_addr <= 0;
            params_ram_rd_en <= 0;
            feature_get_enable <= 0;
            feature_back_ready <= 0;
            feature_back_wren <= 0;
            feature_back_data <= 0;
            params_change_en <= 0;
            feature_send_cnt <= 0;
            if(state_work_cnt == 0 && !rec_en && rec_en_reg0 && !udp_work_done) begin
                rec_byte_num_reg <= rec_byte_num;
                state_work_cnt <= 1;
            end
            else if(state_work_cnt == 1) begin
                rx_fifo_rd_en <= 1;
                state_work_cnt <= 2;
            end
            else if(state_work_cnt == 2) begin
                rx_fifo_rd_en <= 0;
                state_work_cnt <= 3;
            end
            else if(state_work_cnt == 3) begin
                rx_fifo_rd_en <= 0;
                udp_data_signals <= 0;
                state_work_cnt <= 4;
            end
            else if(state_work_cnt == 4) begin
                rx_fifo_rd_en <= 0;
                udp_data_signals <= rx_fifo_rd_data;
                state_work_cnt <= 5;
            end
            else if(state_work_cnt == 5) begin
                if(udp_data_signals == 'h11) begin
                    udp_work_state <= UDP_STATE_EFFECTS_CHANGE;
                    udp_data_signals <= 0;
                end else if(udp_data_signals == 'h22) begin
                    udp_work_state <= UDP_STATE_GET_FEATURE;
                    udp_data_signals <= 0;
                end else if(udp_data_signals == 'h33) begin
                    udp_work_state <= UDP_STATE_READ_PARAMS;
                    udp_data_signals <= 0;
                end else begin
                    udp_work_state <= UDP_STATE_IDLE;
                    udp_data_signals <= 0;
                end
                state_work_cnt <= 0;
            end
            else if(state_work_cnt > 4) begin
                state_work_cnt <= 0;
            end
        end
        UDP_STATE_EFFECTS_CHANGE: begin
            case (state_work_cnt)
                0: begin
                    rx_fifo_rd_en   <= 1'b1;
                    params_ram_addr <= 0;
                    ram_addr_cnt    <= 0;
                    params_ram_wr_en <= 0;
                    state_work_cnt  <= 1;
                end
                1: begin
                    rx_fifo_rd_en   <= 1'b0;
                    state_work_cnt  <= 2;
                end
                2: begin
                    if (ram_addr_cnt < PARAMS_NUM) begin
                        params_ram_wr_data <= rx_fifo_rd_data;
                        params_ram_wr_en   <= 1'b1;
                        params_ram_addr    <= ram_addr_cnt;
                        ram_addr_cnt       <= ram_addr_cnt + 1;
                        rx_fifo_rd_en      <= 1'b1;
                        state_work_cnt     <= 3;
                    end else if (ram_addr_cnt == PARAMS_NUM) begin
                        params_ram_wr_en <= 1'b0;
                        rx_fifo_rd_en    <= 1'b0;
                        state_work_cnt   <= 10;
                    end
                end
                3: begin
                    rx_fifo_rd_en   <= 1'b0;
                    params_ram_wr_en <= 1'b0;
                    state_work_cnt  <= 4; 
                end
                4: begin  
                    state_work_cnt  <= 2;
                end
                10: begin
                    rx_fifo_rd_en   <= 1'b0;
                    params_match_reg[17:16] <= rx_fifo_rd_data[1:0];
                    state_work_cnt  <= 11;
                    rx_fifo_rd_en   <= 1'b0;
                end
                11: begin
                    rx_fifo_rd_en   <= 1'b1;
                    state_work_cnt  <= 12;
                end
                12: begin
                    rx_fifo_rd_en   <= 1'b0;
                    params_match_reg[15:8] <= rx_fifo_rd_data;
                    state_work_cnt  <= 13;
                end
                13: begin
                    rx_fifo_rd_en   <= 1'b1;
                    state_work_cnt  <= 14;
                end
                14: begin
                    rx_fifo_rd_en   <= 1'b0;
                    params_match_reg[7:0] <= rx_fifo_rd_data;
                    state_work_cnt  <= 15;
                end
                15: begin
                    rx_fifo_rd_en      <= 0;
                    params_ram_wr_en   <= 0;
                    params_change_en   <= 1'b1;
                    udp_work_done      <= 1'b1;
                    state_work_cnt     <= 0;
                    udp_work_state     <= UDP_STATE_IDLE;
                end
            endcase
        end
        UDP_STATE_GET_FEATURE: begin
            case (state_work_cnt)
            0: begin
                feature_get_enable <= 1'b1;
                send_en        <= 1'b0;
                tx_fifo_wr_en      <= 1'b0;
                feature_point_cnt  <= 0;
                feature_send_cnt   <= 0;
                feature_sending    <= 1'b0;
                feature_back_ready <= 1'b0;
                feature_back_wren  <= 1'b0;
                feature_back_data  <= 0;
                ram_addr_cnt       <= 0;
                state_work_cnt     <= 1;
            end
            1: begin
                if (feature_wav_ready && (feature_wav_signal != feature_wav_signal_reg0) && feature_new_valid == 0) begin
                    feature_wav_reg   <= feature_wav_data;
                    feature_write_cnt <= 0;
                    feature_new_valid <= 1'b1;
                end else if (feature_new_valid) begin
                    case (feature_write_cnt)
                        0: begin
                            tx_fifo_wr_data <= feature_wav_reg[7:0];
                            tx_fifo_wr_en   <= 1'b1;
                            feature_write_cnt <= 10; // 进入空一拍状态
                        end
                        10: begin
                            tx_fifo_wr_en   <= 1'b0;
                            feature_write_cnt <= 1;
                        end
                        1: begin
                            tx_fifo_wr_data <= feature_wav_reg[15:8];
                            tx_fifo_wr_en   <= 1'b1;
                            feature_write_cnt <= 11;
                        end
                        11: begin
                            tx_fifo_wr_en   <= 1'b0;
                            feature_write_cnt <= 2;
                        end
                        2: begin
                            tx_fifo_wr_data <= feature_wav_reg[23:16];
                            tx_fifo_wr_en   <= 1'b1;
                            feature_write_cnt <= 12;
                        end
                        12: begin
                            tx_fifo_wr_en   <= 1'b0;
                            feature_write_cnt <= 3;
                        end
                        3: begin
                            tx_fifo_wr_data <= feature_wav_reg[31:24];
                            tx_fifo_wr_en   <= 1'b1;
                            feature_write_cnt <= 13;
                        end
                        13: begin
                            tx_fifo_wr_en   <= 1'b0;
                            feature_write_cnt <= 0;
                            feature_point_cnt <= feature_point_cnt + 1;
                            feature_new_valid <= 1'b0;
                        end
                    endcase
                end else begin
                    tx_fifo_wr_en <= 1'b0;
                end

                if (feature_point_cnt >= FEATURE_POINT_NUM) begin
                    send_en       <= 1'b1;
                    tx_byte_num       <= FEATURE_POINT_NUM * FEATURE_BYTE_PER_SAMPLE;
                    feature_point_cnt <= 0;
                    feature_send_cnt  <= feature_send_cnt + 1;
                    feature_sending   <= 1'b1;
                end else if(feature_point_cnt == 1)begin
                    send_en <= 1'b0;
                end

                if(feature_send_cnt < FEATURE_SEND_TIMES/2) begin
                    feature_wav_select <= 1'b0;
                end else begin
                    feature_wav_select <= 1'b1;
                end

                if (feature_send_cnt >= FEATURE_SEND_TIMES) begin
                    feature_get_enable <= 1'b0;
                    feature_sending    <= 1'b0;
                    send_en        <= 1'b0;
                    tx_fifo_wr_en      <= 1'b0;
                    feature_point_cnt  <= 0;
                    state_work_cnt     <= 2;
                end
            end

            2: begin
                if (rec_en_reg0 == 1'b1 && rec_en == 1'b0) begin
                    rx_fifo_rd_en      <= 1'b1;
                    feature_back_ready <= 1'b1;
                    feature_back_cnt   <= 0;
                    state_work_cnt     <= 3;
                end
            end
            3: begin
                rx_fifo_rd_en  <= 1'b0;
                state_work_cnt <= 4;
            end
            4: begin
                if (feature_back_cnt < FEATURE_NUM_BACK) begin
                    feature_back_data <= rx_fifo_rd_data;
                    feature_back_wren <= 1'b1;
                    feature_back_cnt  <= feature_back_cnt + 1;
                    rx_fifo_rd_en     <= 1'b1;
                    state_work_cnt    <= 5;
                end
                else if (feature_back_cnt == FEATURE_NUM_BACK) begin
                    rx_fifo_rd_en      <= 1'b0;
                    feature_back_wren  <= 1'b0;
                    feature_back_ready <= 1'b0;
                    feature_back_cnt   <= 0;
                    state_work_cnt     <= 6;
                    net_input_enable   <= 1'b1;
                end
            end
            5: begin
                rx_fifo_rd_en   <= 1'b0;
                feature_back_wren <= 1'b0;
                state_work_cnt  <= 4;
            end
            6: begin
                if(net_input_valid && (net_input_wr_en && !net_input_wr_en_reg0) && (net_action_cnt < ACTION_NUM-1)) begin
                    tx_fifo_wr_data <= net_input_data;
                    tx_fifo_wr_en   <= 1'b1;
                    state_work_cnt  <= 60;
                end else if(net_input_valid && (net_input_wr_en && !net_input_wr_en_reg0)  && (net_action_cnt == ACTION_NUM-1)) begin
                    tx_fifo_wr_data <= net_input_data;
                    tx_fifo_wr_en   <= 1'b1;
                    state_work_cnt  <= 61;
                end else begin
                    tx_fifo_wr_en <= 1'b0;
                end
            end
            60: begin
                tx_fifo_wr_en <= 1'b0;
                net_action_cnt <= net_action_cnt + 1;
                state_work_cnt <= 6;
            end
            61: begin
                tx_fifo_wr_en <= 1'b0;
                net_action_cnt  <= 0;
                send_en <= 1'b1;
                state_work_cnt  <= 7;
            end
            7: begin
                tx_fifo_wr_en <= 1'b0;
                net_action_cnt  <= 0;
                net_input_enable <= 1'b0;
                udp_work_done <= 1'b1;
                send_en <= 1'b1;
                tx_byte_num <= ACTION_NUM;
                state_work_cnt <= 0;
                udp_work_state  <= UDP_STATE_IDLE;
            end
            endcase
        end
        UDP_STATE_READ_PARAMS: begin
            case(state_work_cnt)
                0: begin
                    udp_data_signals <= 0;
                    params_ram_addr <= 0;
                    ram_addr_cnt <= 0;
                    tx_fifo_wr_en <= 0;
                    send_en <= 0;
                    state_work_cnt <= 1;
                end
                1: begin
                    params_ram_addr <= ram_addr_cnt;
                    tx_fifo_wr_en <= 0;
                    state_work_cnt <= 2;
                end
                2: begin
                    params_ram_rd_en <= 1;
                    state_work_cnt <= 3;
                end
                3: begin
                    tx_fifo_wr_data <= params_ram_rd_data;
                    tx_fifo_wr_en   <= 1;
                    params_ram_rd_en <= 0;
                    state_work_cnt <= 4;
                end
                4: begin
                    tx_fifo_wr_en <= 0;
                    if (ram_addr_cnt < PARAMS_NUM-1) begin
                        ram_addr_cnt <= ram_addr_cnt + 1;
                        params_ram_addr <= ram_addr_cnt + 1;
                        params_ram_rd_en <= 1;
                        state_work_cnt <= 2; 
                    end else begin
                        send_en <= 1;
                        params_ram_rd_en <= 0;
                        state_work_cnt <= 7;
                    end
                end
                7: begin
                    tx_fifo_wr_en <= 0;
                    send_en <= 1;
                    tx_byte_num <= PARAMS_NUM + 1;
                    udp_work_state <= UDP_STATE_IDLE;
                    udp_work_done <= 1;
                    state_work_cnt <= 0;
                    ram_addr_cnt <= 0;
                end
            endcase
        end
        endcase
    end
end

// FIFO缓存
async_fifo_1024x8b fifo_1024x8b_udp_rx(
    .wr_clk_i   (clk_25m),
    .wr_en_i    (rec_en),
    .wdata      (rec_data),
    .rd_clk_i   (sys_2xclk),
    .rd_en_i    (rx_fifo_rd_en),
    .rdata      (rx_fifo_rd_data),
    .a_rd_rst_i (~sys_rst_n || send_end),
    .a_wr_rst_i (~sys_rst_n || send_end)
    );

reg rd_en_i_reg0;
reg rd_en_i_reg1;
always@(negedge eth_clk) begin
    if(!sys_rst_n) begin
        rd_en_i_reg0 <= 0;
        rd_en_i_reg1 <= 0;
    end else begin 
        rd_en_i_reg0 <= read_data_req;
        rd_en_i_reg1 <= rd_en_i_reg0;
    end
end
async_fifo_1024x8b fifo_1024x8b_udp_tx(
    .wr_clk_i   (sys_clk),
    .wr_en_i    (tx_fifo_wr_en),
    .wdata      (tx_fifo_wr_data),
    .rd_clk_i   (clk_25m),
    .rd_en_i    (rd_en_i_reg0),
    .rdata      (send_data),
    .a_rd_rst_i(~sys_rst_n || rec_en || rec_en_reg0),
    .a_wr_rst_i(~sys_rst_n || rec_en || rec_en_reg0)
    );

udp#(
    .BOARD_MAC      (BOARD_MAC      ),   //板卡MAC地址
    .BOARD_IP       (BOARD_IP       ),   //板卡IP地址
    //.BOARD_PORT   (BOARD_PORT     ), //板卡端口号
    .DES_MAC        (PC_MAC         ),   //PC机MAC地址
    .DES_IP         (PC_IP          )    //PC机IP地址
    //.PC_PORT      (PC_PORT        )  //PC机端口号
    )udp_inst(
    .rst_n          (sys_rst_n)     , //复位信号，低电平有效
    //GMII接口
    .gmii_rx_clk    (clk_25m)       , //GMII接收数据时钟
    .gmii_rx_dv     (gmii_rx_dv)    , //GMII输入数据有效信号
    .gmii_rxd       (gmii_rxd)      , //GMII输入数据
    .gmii_tx_clk    (clk_25m)       , //GMII发送数据时钟    
    .gmii_tx_en     (gmii_tx_en)    , //GMII输出数据有效信号
    .gmii_txd       (gmii_txd)      , //GMII输出数据 
    //用户接口
    .rec_pkt_done   (rec_end)       , //以太网单包数据接收完成信号
    .rec_en         (rec_en)        , //以太网接收的数据使能信号
    .rec_data       (rec_data)      , //以太网接收的数据
    .rec_byte_num   (rec_byte_num)  , //以太网接收的有效字节数 单位:byte     
    .tx_start_en    (send_en)       , //以太网开始发送信号
    .tx_data        (send_data)     , //以太网待发送数据  
    .tx_byte_num    (tx_byte_num)   , //以太网发送的有效字节数 单位:byte  
    .des_mac        (PC_MAC)        , //发送的目标MAC地址
    .des_ip         (PC_IP)         , //发送的目标IP地址    
    .tx_done        (send_end)      , //以太网发送完成信号
    .tx_req         (read_data_req)   //读数据请求信号    
    );
// RMII与MII转换模块
rmii_to_mii rmii_to_mii_inst( 
    .eth_rmii_clk   (eth_clk ),      //rmii时钟 
    .eth_mii_clk    (clk_25m ),      //mii时钟 
    .sys_rst_n      (sys_rst_n ),    //复位信号 
    .rx_dv          (eth_rxdv_r ),   //输入数据有效信号(rmii) 
    .rx_data        (eth_rx_data_r ),//输入数据(rmii) 
    .eth_rx_dv      (eth_rxdv ),     //输入数据有效信号(mii) 
    .eth_rx_data    (eth_rx_data )   //输入数据(mii) 
    );  
mii_to_rmii mii_to_rmii_inst(
    .eth_mii_clk    (clk_25m),      // 50MHz MII时钟
    .eth_rmii_clk   (eth_clk),      // RMII时钟
    .sys_rst_n      (sys_rst_n),    // 复位信号
    .tx_dv          (eth_tx_en),    // MII 输出数据有效信号
    .tx_data        (eth_tx_data),  // MII 输出有效数据

    .eth_tx_dv      (eth_tx_en_r), // RMII 输出数据有效信号
    .eth_tx_data    (eth_tx_data_r)// RMII 输出数据
    );

endmodule
