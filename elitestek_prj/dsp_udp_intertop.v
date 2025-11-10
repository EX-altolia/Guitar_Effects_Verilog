module dsp_udp_top(
    input clk24m,
    input pll_inst1_CLKOUT1_12m,
    input pll_inst1_CLKOUT0_24m,
    input pll_inst1_CLKOUT2_50m,
    input pll_inst1_CLKOUT3_100m,

    input eth_clk_IN,
    input eth_rxdv_r_IN,
    input eth_rx_data_r0_IN,
    input eth_rx_data_r1_IN,
    output eth_tx_en_r_OUT,
    output eth_tx_data_r0_OUT,
    output eth_tx_data_r1_OUT,

    input bck_IN,
    input lrck_IN,
    input dout_IN,
    output sclk_OUT,
    output DAC_SCK_OUT,
    output DAC_BCLK_OUT,
    output DAC_LRCK_OUT,
    output DAC_DIN_OUT
);

//clk24m——c5
//lan8720
//（从下往上
// 右左六——TX1——io27——GPIO_R_P_12   ——G13
// 右左七——TXen——io28——GPIO_R_N_10  ——H12
// 右左八——TX0 ——io29——GPIO_R_P_10  ——H13
//（从上往下
// 右左六——rxen——io36——GPIOT_N_03   ——A6
// 右左七——refclk——io35——GPIOT_P_00 ——E6
// 右左八——rx1 ——io34——GPIOT_N_00   ——D5
// 右左九——rx0——io33——GPIOT_P_11    ——B9
// 右左四，右左三   io39 io38 GPIOL_P_18 GPIOL_N_18 b2 a2
//audio（pcm1808，pcm5102
//从5v方向开始
// 左左三——pcm1808_bck——io0——GPIOL_N_02 ——M2
// 左左四——pcm1808_dout——io1——GPIOL_P_02——N2
// 左左五——pcm1808_lrck——io2——GPIOL_N_06——K2
// 左左六——pcm1808_sck——io3——GPIOL_P_06 ——K3
// 左左七——pcm1808_fmt——io4——GPIOL_N_08 ——H3
// 左左八——pcm1808_md1——io5——GPIOL_P_08 ——J2
// 左左九——pcm1808_md0——io6——GPIOL_N_05 ——J3
//从3v3方向开始 
// 左左四——pcm5102_sck——io22——GPIOL_N_07——J1
// 左左五——pcm5102_bck——io21——GPIOL_P_03——M1
// 左左六——pcm5102_din——io20——GPIOL_N_03——L1
// 左左七——pcm5102_lrck——io19——GPIOL_P_01——P1
(* syn_preserve = "true" *)reg for_clk24m;
    always@(posedge clk24m) 
        for_clk24m <= ~for_clk24m;

(* syn_preserve = "true" *)reg sys_rst_n;
    always@(posedge pll_inst1_CLKOUT0_24m) 
    sys_rst_n <= 1;

dsp_udp dsp_udp_inst(
    .sys_clk   (pll_inst1_CLKOUT2_50m), 
    .sys_2xclk (pll_inst1_CLKOUT3_100m),
    .sys_rst_n (sys_rst_n), 
    .audio_clk (pll_inst1_CLKOUT1_12m),
    //PL以太网RGMII接口   
    .eth_clk         (eth_clk_IN),  
    .eth_rxdv_r      (eth_rxdv_r_IN),  
    .eth_rx_data_r   ({eth_rx_data_r1_IN, eth_rx_data_r0_IN}),   
    .eth_tx_en_r     (eth_tx_en_r_OUT),  
    .eth_tx_data_r   ({eth_tx_data_r1_OUT,eth_tx_data_r0_OUT}),  
    //pcm1840侧
    .FMT (),
    .MD0 (),
    .MD1 (),
    .sclk(sclk_OUT),
    .bck (bck_IN),
    .lrck(lrck_IN),
    .dout(dout_IN),
    //pcm5102a侧
    .DAC_SCK (DAC_SCK_OUT),         
    .DAC_BCLK(DAC_BCLK_OUT),        
    .DAC_LRCK(DAC_LRCK_OUT),         
    .DAC_DIN (DAC_DIN_OUT)   

    );

endmodule

