create_clock -waveform {20.834 41.667} -period 41.667 -name pll_inst1_CLKOUT0_24m [get_ports {pll_inst1_CLKOUT0_24m}]
create_clock -waveform {40.834 81.667} -period 81.667 -name pll_inst1_CLKOUT1_12m [get_ports {pll_inst1_CLKOUT1_12m}]
create_clock -waveform {10.000 20.000} -period 20.000 -name pll_inst1_CLKOUT2_50m [get_ports {pll_inst1_CLKOUT2_50m}]
create_clock -waveform {10.000 20.000} -period 20.000 -name eth_clk_IN [get_ports {eth_clk_IN}]
create_clock -period 10.000 -name pll_inst1_CLKOUT3_100m [get_ports {pll_inst1_CLKOUT3_100m}]

set_clock_groups -exclusive -group {pll_inst1_CLKOUT3_100m}
set_clock_groups -exclusive -group {pll_inst1_CLKOUT0_24m}
set_clock_groups -exclusive -group {pll_inst1_CLKOUT1_12m}
set_clock_groups -exclusive -group {pll_inst1_CLKOUT2_50m}
set_clock_groups -exclusive -group {eth_clk_IN}