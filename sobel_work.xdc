#=============================================================================
# Constraints File : top.xdc
# Board             : Boolean Board (Spartan-7 XC7S50)
# Project           : UART + FIFO + Sobel Pipeline
#
# Port names here MUST match top.v exactly:
#   clk, uart_rx, uart_tx, led[0..7]
#=============================================================================

# -----------------------------------------------------------------------------
# Bank voltage - required for Boolean board
# -----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# -----------------------------------------------------------------------------
# Clock - 100 MHz on-board oscillator (Pin F14)
# -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports {clk}]
create_clock -period 10.000 -name sys_clk [get_ports {clk}]

# -----------------------------------------------------------------------------
# UART RX - data coming INTO the FPGA from PC
# Board label : UART_rxd -> our port name : uart_rx
# -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {uart_rx}]

# -----------------------------------------------------------------------------
# UART TX - data going OUT of FPGA to PC
# Board label : UART_txd -> our port name : uart_tx
# -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports {uart_tx}]

# -----------------------------------------------------------------------------
# LEDs - shows last transmitted byte for debug (led[0] = LSB)
# -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN F2 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports {led[7]}]