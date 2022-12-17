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
dpram.v \
spi.v \
flash_if.v \
ram_fifo_if.v \
app.v \
bootloader.v \

# Testbench HDL files
TB_HDL_FILES = \
SB_PLL40_CORE.v \
AT25SF081.v \
usb_monitor.v \
tb_bootloader.v \

# list of HDL files directories separated by ":"
VPATH = ../../../usb_dfu: \
        ../hdl/bootloader: \
        ../../common/hdl: \
        ../../common/hdl/ice40: \
        ../../common/hdl/flash: \
