# HDL files
HDL_FILES = \
phy_tx.v \
phy_rx.v \
sie.v \
ctrl_endp.v \
in_fifo.v \
out_fifo.v \
fifo.v \
usb_dfu.v \
SB_RAM256x16.v \
ram.v \
dpram.v \
spi.v \
flash_spi.v \
ram_if.v \
ram_fifo_if.v \
dfu_app.v \
loopback.v \

# Testbench HDL files
TB_HDL_FILES = \
SB_PLL40_CORE.v \
AT25SF081.v \
usb_monitor.v \
tb_loopback.v \

# list of HDL files directories separated by ":"
VPATH = ../../../usb_dfu: \
        ../hdl/loopback: \
        ../../common/hdl: \
        ../../common/hdl/ice40: \
        ../../common/hdl/flash: \
