
proc flash {} {
    gtkwave::/Edit/Insert_Comment "FLASH"
    set sigFilterList [list \
                           {flash_[^.]+\.state_q\[.*\]$} \
                           {flash_[^.]+\.status_o\[.*\]$} \
                           {flash_[^.]+\.byte_cnt_q\[.*\]$} \
                          ]
    addSignals $sigFilterList
    wavesFormat input/bootloader/gtkwave
    setData { {flash_[^.]+\.state_q\[.*\]$} } Decimal
    setData { {flash_[^.]+\.byte_cnt_q\[.*\]$} } Decimal
}

proc app {} {
    gtkwave::/Edit/Insert_Comment "APP"
    set sigFilterList [list \
                           {app\.wr_length_q\[.*\]$} \
                           {app\.rd_length_q\[.*\]$} \
                           {app\.timer_q\[.*\]$} \
                           {app\.state_q\[.*\]$}\
                          ]
    addSignals $sigFilterList
    wavesFormat input/bootloader/gtkwave
    setData { {app\.timer_q\[.*\]$} } Decimal
}

proc monitor {} {
    gtkwave::/Edit/Insert_Comment "MONITOR"
    set sigFilterList [list \
                           {u_usb_monitor\.info\[.*\]$} \
                           {u_usb_monitor\.pid\[.*\]$} \
                           {u_usb_monitor\.frame\[.*\]$} \
                           {u_usb_monitor\.addr\[.*\]$} \
                           {u_usb_monitor\.endp\[.*\]$} \
                           {u_usb_monitor\.bytes$} \
                           {u_usb_monitor\.data\[.*\]$} \
                           {u_usb_monitor\.warnings$}\
                          ]
    addSignals $sigFilterList
    wavesFormat input/bootloader/gtkwave
    setData  { {u_usb_monitor\.info\[.*\]$} } ASCII
    setColor { {u_usb_monitor\.info\[.*\]$} } Blue
    setColor { {u_usb_monitor\.warnings$} } Yellow
}

proc top {} {
    gtkwave::/Edit/Insert_Comment "TOP"
    set sigFilterList [list \
                           {^[^.]*\.test\[.*\]$} \
                           {^[^.]*\.dp_sense$} \
                           {^[^.]*\.dn_sense$} \
                           {^[^.]*\.errors$} \
                           {^[^.]*\.csn$} \
                           {^[^.]*\.sck$} \
                           {^[^.]*\.mosi$} \
                           {^[^.]*\.miso$} \
                          ]
    addSignals $sigFilterList
    wavesFormat input/bootloader/gtkwave
    setData  { {^[^.]*\.test\[.*\]$} } ASCII
    setColor { {^[^.]*\.test\[.*\]$} } Blue
    setColor { {^[^.]*\.errors$} } Red
}

set cmds "flash app monitor top $cmds"
