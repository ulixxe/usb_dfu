
proc addSignals {sigFilterList} {
    foreach sigFilter $sigFilterList {
        for {set i 0} {$i < [ gtkwave::getNumFacs ] } {incr i} {
            set facname [gtkwave::getFacName $i]
            set index [regexp $sigFilter $facname]
            if {$index == 1} {
                gtkwave::addSignalsFromList "$facname"
            }
        }
    }
}

proc setColor {sigFilterList color} {
    gtkwave::/Edit/UnHighlight_All
    foreach sigFilter $sigFilterList {
        for {set i 0} {$i < [ gtkwave::getNumFacs ] } {incr i} {
            set facname [gtkwave::getFacName $i]
            set index [regexp $sigFilter $facname]
            if {$index == 1} {
                gtkwave::highlightSignalsFromList "$facname"
            }
        }
    }
    gtkwave::/Edit/Color_Format/$color
    gtkwave::/Edit/UnHighlight_All
}

proc setData {sigFilterList data} {
    gtkwave::/Edit/UnHighlight_All
    foreach sigFilter $sigFilterList {
        for {set i 0} {$i < [ gtkwave::getNumFacs ] } {incr i} {
            set facname [gtkwave::getFacName $i]
            set index [regexp $sigFilter $facname]
            if {$index == 1} {
                gtkwave::highlightSignalsFromList "$facname"
            }
        }
    }
    gtkwave::/Edit/Data_Format/$data
    gtkwave::/Edit/UnHighlight_All
}

proc getConfig {mapfile} {
    set fd [open $mapfile r]
    set data [read $fd]
    close $fd

    set data_lines [split $data "\n"]
    set config_lines [lsearch -all -regexp $data_lines "^(\\s)*##.*##.*$"]
    set config_dict [dict create]
    foreach line $config_lines {
        set config_data [split [string map [list "##" \001] [lindex $data_lines $line]] \001]
        set key [string trim [lindex $config_data 1]]
        set value [string trim [lindex $config_data 2]]
        if { $key == "name"} {
            dict lappend config_dict $key $value
        } else {
            dict set config_dict $key $value
        }
    }
    return $config_dict
}

proc wavesTranslate {mapfile} {
    set config_dict [getConfig $mapfile]
    if {[dict exists $config_dict {name}]} {
        gtkwave::/Edit/UnHighlight_All
        foreach sigFilter [dict get $config_dict {name}] {
            for {set i 0} {$i < [gtkwave::getNumFacs] } {incr i} {
                set facname [gtkwave::getFacName $i]
                set index [regexp $sigFilter $facname]
                if {$index == 1} {
                    gtkwave::highlightSignalsFromList "$facname"
                }
            }
        }
        if {[dict exists $config_dict {color}]} {
            gtkwave::/Edit/Color_Format/[dict get $config_dict {color}]
        }
        if {[dict exists $config_dict {data}]} {
            gtkwave::/Edit/Data_Format/[dict get $config_dict {data}]
        }
        gtkwave::installFileFilter [gtkwave::setCurrentTranslateFile $mapfile]
        gtkwave::/Edit/UnHighlight_All
    }
}

proc wavesFormat {mapdir} {
    set files [ glob $mapdir/*.map ]
    foreach file $files {
        wavesTranslate $file
    }
}

proc phy_rx {} {
    gtkwave::/Edit/Insert_Comment "PHY_RX"
    set sigFilterList [list \
                           {phy_rx\.nrzi\[.*\]$} \
                           {phy_rx\.rx_state_q\[.*\]$} \
                           {phy_rx\.clk_gate$} \
                           {phy_rx\.rx_en_i$} \
                           {phy_rx\.rx_err_o$} \
                           {phy_rx\.rx_ready_o$} \
                           {phy_rx\.rx_valid_o$} \
                           {phy_rx\.rx_data_o\[.*\]$} \
                           {phy_rx\.usb_reset_o$} \
                           {phy_rx\.dp_pu_o$} \
                          ]
    addSignals $sigFilterList
    wavesFormat ../../common/gtkwave
}

proc phy_tx {} {
    gtkwave::/Edit/Insert_Comment "PHY_TX"
    set sigFilterList [list \
                           {phy_tx\.tx_state_q\[.*\]$} \
                           {phy_tx\.clk_gate$} \
                           {phy_tx\.tx_ready_o$} \
                           {phy_tx\.tx_valid_i$} \
                           {phy_tx\.tx_data_i\[.*\]$} \
                          ]
    addSignals $sigFilterList
    wavesFormat ../../common/gtkwave
}

proc sie {} {
    gtkwave::/Edit/Insert_Comment "SIE"
    set sigFilterList [list \
                           {sie\.frame_q\[.*\]$} \
                           {sie\.pid_q\[.*\]$} \
                           {sie\.addr_q\[.*\]$} \
                           {sie\.endp_q\[.*\]$} \
                           {sie\.phy_state_q\[.*\]$} \
                           {sie\.stall_i$} \
                           {sie\.setup_o$} \
                          ]
    addSignals $sigFilterList
    wavesFormat ../../common/gtkwave
    setData { {sie\.frame_q\[.*\]$} } Decimal
    setData { {sie\.addr_q\[.*\]$} } Decimal
}

proc sie_out {} {
    gtkwave::/Edit/Insert_Comment "SIE: OUT"
    set sigFilterList [list \
                           {sie\.out_err_o$} \
                           {sie\.out_ready_o$} \
                           {sie\.out_valid_o$} \
                           {sie\.out_data_o\[.*\]$} \
                          ]
    addSignals $sigFilterList
    wavesFormat ../../common/gtkwave
}

proc sie_in {} {
    gtkwave::/Edit/Insert_Comment "SIE: IN"
    set sigFilterList [list \
                           {sie\.in_req_o$} \
                           {sie\.in_ready_o$} \
                           {sie\.in_valid_i$} \
                           {sie\.in_zlp_i$} \
                           {sie\.in_data_i\[.*\]$} \
                          ]
    addSignals $sigFilterList
    wavesFormat ../../common/gtkwave
}

proc ctrl {} {
    gtkwave::/Edit/Insert_Comment "CTRL_ENDP"
    set sigFilterList [list \
                           {ctrl_endp\.dev_state_qq\[.*\]$} \
                           {ctrl_endp\.state_q\[.*\]$} \
                           {ctrl_endp\.dfu_state_q\[.*\]$} \
                           {ctrl_endp\.addr_o\[.*\]$} \
                           {ctrl_endp\.stall_o$} \
                           {ctrl_endp\.dfu_mode_o$} \
                           {ctrl_endp\.dfu_alt_o\[.*\]$} \
                           {ctrl_endp\.dfu_upload_o$} \
                           {ctrl_endp\.dfu_dnload_o$} \
                           {ctrl_endp\.dfu_clear_status_o$} \
                          ]
    addSignals $sigFilterList
    wavesFormat ../../common/gtkwave
}

proc fifo_out {} {
    gtkwave::/Edit/Insert_Comment "FIFO: OUT"
    set sigFilterList [list \
                           {u_fifo\.u_out_fifo\.app_clk_i$} \
                           {u_fifo\.u_out_fifo\.app_out_ready_i$} \
                           {u_fifo\.u_out_fifo\.app_out_valid_o$} \
                           {u_fifo\.u_out_fifo\.app_out_data_o\[.*\]$} \
                           {u_fifo\.u_out_fifo\.out_state_q\[.*\]$} \
                           {u_fifo\.u_out_fifo\.out_full_q$} \
                           {u_fifo\.u_out_fifo\.out_empty$} \
                          ]
    addSignals $sigFilterList
    wavesFormat ../../common/gtkwave
}

proc fifo_in {} {
    gtkwave::/Edit/Insert_Comment "FIFO: IN"
    set sigFilterList [list \
                           {u_fifo\.u_in_fifo\.app_clk_i$} \
                           {u_fifo\.u_in_fifo\.app_in_ready_o$} \
                           {u_fifo\.u_in_fifo\.app_in_valid_i$} \
                           {u_fifo\.u_in_fifo\.app_in_data_i\[.*\]$} \
                           {u_fifo\.u_in_fifo\.in_state_q$} \
                           {u_fifo\.u_in_fifo\.in_full$} \
                          ]
    addSignals $sigFilterList
    wavesFormat ../../common/gtkwave
    setColor { {u_fifo\.u_in_fifo\.in_state_q$} } Blue
}

proc dfu {} {
    gtkwave::/Edit/Insert_Comment "DFU"
    set sigFilterList [list \
                           {usb_dfu\.usb_reset$} \
                          ]
    addSignals $sigFilterList
    wavesFormat ../../common/gtkwave
}

proc out {} {
    phy_rx
    sie
    sie_out
    fifo_out
}

proc in {} {
    fifo_in
    sie
    sie_in
    phy_tx
}

set cmds "dfu out in phy_rx phy_tx sie sie_out sie_in ctrl fifo_in fifo_out"
if { [file exists input/$env(PROJ)/gtkwave/procs.tcl]} {
    source input/$env(PROJ)/gtkwave/procs.tcl
}

puts "\033\[92m"
puts "gtkwave console"
puts "Available commands to show waveforms:"
puts "  $cmds"
puts "\033\[0m"
