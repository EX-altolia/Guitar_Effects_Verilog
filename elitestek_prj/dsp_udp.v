`timescale 1ns / 1ps

module dsp_udp(
    input  wire       sys_clk   , //系统时钟
    input  wire       sys_rst_n , //系统复位信号，低电平有效 
    input  wire       audio_clk ,
    input  wire       sys_2xclk,
    //PL以太网RGMII接口   
    input   wire            eth_clk         ,   //PHY芯片时钟信号
    input   wire            eth_rxdv_r      ,   //PHY芯片输入数据有效信号
    input   wire    [1:0]   eth_rx_data_r   ,   //PHY芯片输入数据
    output  wire            eth_tx_en_r     ,   //PHY芯片输出数据有效信号
    output  wire    [1:0]   eth_tx_data_r   ,   //PHY芯片输出数据
    //pcm1840侧
    output wire  FMT ,
    output wire  MD0 ,
    output wire  MD1 ,
    output wire  sclk,
    input  wire  bck ,
    input  wire  lrck,
    input  wire  dout,
    //pcm5102a侧
    output wire  DAC_SCK ,         
    output wire  DAC_BCLK,        
    output wire  DAC_LRCK,         
    output wire  DAC_DIN    

    );

//udp控制模块变量
wire       udp_params_ram_clk       ;
wire       udp_params_ram_rw_en     ;
wire [7:0] udp_params_ram_wr_data   ;
wire [9:0] udp_params_ram_addr      ;
wire [7:0] udp_params_ram_rd_data   ;
wire [17:0]udp_params_match_reg     ;
wire       udp_params_change_en     ;
wire       udp_feature_wav_ready    ;
wire       udp_feature_wav_signal   ;
wire [31:0]udp_feature_wav_data     ;
wire       udp_feature_back_ready   ;
wire       udp_feature_back_wren    ;
wire [7:0] udp_feature_back_data    ;
wire       udp_feature_wav_select   ;
//效果器模块变量
wire        dsp_params_ram_clk      ;
wire        dsp_params_ram_rd_en    ;
wire [15:0] dsp_params_ram_rd_data  ;
wire [9:0]  dsp_params_ram_rd_addr  ;
wire        dsp_params_change_en    ;
wire [17:0] dsp_params_match_reg    ;
(* keep = "true" *) wire        dsp_params_change_finished;
wire        dsp_effects_work_enable             ;
wire        dsp_effects_audio_out_en            ;
wire        dsp_effects_audio_out_signal        ;
wire signed [31:0] dsp_effects_audio_out        ;
wire signed [31:0] dsp_effects_clear_audio_out  ;
wire        dsp_effects_clear_audio_out_signal  ;
wire        dsp_effects_clear_audio_ready       ;
//推理网络变量
wire        net_input_enable        ;
wire        net_output_valid        ;
wire        net_output_wr_en        ;
wire signed [7:0] net_output_data   ;
//ram控制线
wire        params_ram_clk      ;
wire        params_ram_wea      ;
wire [7:0]  params_ram_addr     ;
wire [15:0] params_ram_wr_data  ;
wire [15:0] params_ram_rd_data  ;

//效果器调整变量连接
assign dsp_params_change_en   = udp_params_change_en;
assign udp_feature_wav_ready  = udp_feature_wav_select ? dsp_effects_audio_out_en     : dsp_effects_clear_audio_ready       ;
assign udp_feature_wav_signal = udp_feature_wav_select ? dsp_effects_audio_out_signal : dsp_effects_clear_audio_out_signal  ;
assign udp_feature_wav_data   = udp_feature_wav_select ? dsp_effects_audio_out[31:0]  : dsp_effects_clear_audio_out[31:0]   ;

//参数存储ram变量连接
assign params_ram_clk  = dsp_params_ram_clk     ;
assign params_ram_wea  = 0  ;
assign params_ram_addr = dsp_params_ram_rd_addr ;
assign dsp_params_match_reg = udp_params_match_reg;

blk_mem_gen_1 bram_16x128_8x256_inst1(
    .we_a       (params_ram_wea),
    .addr_a     (params_ram_addr),
    .wdata_a    (0),
    .rdata_a    (dsp_params_ram_rd_data),
    .clk_a      (params_ram_clk),

    .we_b       (udp_params_ram_rw_en),
    .rdata_b    (udp_params_ram_rd_data),
    .addr_b     (udp_params_ram_addr),
    .wdata_b    (udp_params_ram_wr_data),
    .clk_b      (udp_params_ram_clk)
);

actor_net actor_net_inst1(
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .feature_back_ready(udp_feature_back_ready),
    .feature_back_wren (udp_feature_back_wren ),
    .feature_back_data (udp_feature_back_data ),
    .net_output_valid(net_output_valid), 
    .net_output_wr_en(net_output_wr_en),
    .net_output_data(net_output_data)
    );


effects_adjust effects_adjust_inst1(
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .audio_clk  (audio_clk),
    //pcm1840侧
    .FMT (FMT ),
    .MD0 (MD0 ),
    .MD1 (MD1 ),
    .sclk(sclk),
    .bck (bck ),
    .lrck(lrck),
    .dout(dout),
    //pcm5102a侧
    .DAC_SCK (DAC_SCK ),         
    .DAC_BCLK(DAC_BCLK),        
    .DAC_LRCK(DAC_LRCK),         
    .DAC_DIN (DAC_DIN ),         
    //参数配置接口
    .params_ram_clk         (dsp_params_ram_clk    ), 
    .params_ram_rd_en       (dsp_params_ram_rd_en  ),
    .params_ram_rd_data     (dsp_params_ram_rd_data),
    .params_ram_rd_addr     (dsp_params_ram_rd_addr),
    .params_change_en       (dsp_params_change_en  ),
    .params_match_reg       (dsp_params_match_reg  ),
    .params_change_finished (dsp_params_change_finished),
    //效果器音频输出
    //效果器音频输出
    .effects_work_enable            (1    ),
    .effects_audio_out_en           (dsp_effects_audio_out_en    ),
    .effects_audio_out_signal       (dsp_effects_audio_out_signal),
    .effects_audio_out              (dsp_effects_audio_out      ),
    //干声输出
    .effects_clear_audio_out        (dsp_effects_clear_audio_out),
    .effects_clear_audio_out_signal (dsp_effects_clear_audio_out_signal),
    .effects_clear_audio_ready      (dsp_effects_clear_audio_ready)
    );

udp_work_ctrl udp_work_ctrl_inst1(
    .sys_clk   (sys_clk   ), 
    .sys_rst_n (sys_rst_n ), 
    .sys_2xclk (sys_2xclk),
    .eth_clk      (eth_clk      ),
    .eth_rxdv_r   (eth_rxdv_r   ),
    .eth_rx_data_r(eth_rx_data_r),
    .eth_tx_en_r  (eth_tx_en_r  ),
    .eth_tx_data_r(eth_tx_data_r),

    .params_ram_clk     (udp_params_ram_clk     ), 
    .params_ram_rw_en   (udp_params_ram_rw_en   ),
    .params_ram_wr_data (udp_params_ram_wr_data ),
    .params_ram_addr    (udp_params_ram_addr    ),
    .params_ram_rd_data (udp_params_ram_rd_data ),
    .params_match_reg   (udp_params_match_reg  ),
    .params_change_en   (udp_params_change_en   ),

    
    .feature_wav_ready (udp_feature_wav_ready ),
    .feature_wav_signal(udp_feature_wav_signal),
    .feature_wav_data  (udp_feature_wav_data  ),
    .feature_wav_select(udp_feature_wav_select),
    .feature_back_ready(udp_feature_back_ready),
    .feature_back_wren (udp_feature_back_wren ),
    .feature_back_data (udp_feature_back_data ),
    .net_input_enable  ( net_input_enable     ),
    .net_input_valid   (net_output_valid ),
    .net_input_wr_en   (net_output_wr_en ),
    .net_input_data    (net_output_data  ) 
    );

endmodule
