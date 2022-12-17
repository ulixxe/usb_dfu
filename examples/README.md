# USB_DFU Examples

All the examples are built with both [Lattice iCEcube2](https://www.latticesemi.com/iCEcube2) and [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) design flows.

* Lattice design flow
	* Open `examples/<board name>/iCEcube2/<example name>/usb_dfu_sbt.project` file with iCEcube2.
* OSS CAD Suite flow
	* inside `examples/<board name>/OSS_CAD_Suite` run `make all PROJ=<example name>`

Testbenches can be simulated with iverilog/GTKWave.
To run them, inside `examples/<board name>/OSS_CAD_Suite` run `make sim PROJ=<example name>`. Or run `make wave PROJ=<example name>` to show waveforms too.

The GTKWave console makes available a few commands (such as `top`, `out`, `phy_rx`, etc.) to show various waveforms inside the design.

## `bootloader`
The `bootloader` example implements an equivalent of the original TinyFPGA bootloader with the DFU function added. It is fully compatible with the `tinyprog` programmer.

In Run-time mode (after USB reset), the device can respond to both `tinyprog` and `dfu-util`:

```
> tinyprog -l

    TinyProg CLI
    ------------
    Using device id 1d50:6130
    Only one board with active bootloader, using it.

    Boards with active bootloaders:

        /dev/cu.usbmodem001: TinyFPGA BX 1.0.0
            UUID: a6121c87-091b-4037-90c5-7091192fc44d
            FPGA: ice40lp8k-cm81

```
```
> dfu-util -lv
dfu-util 0.11

Copyright 2005-2009 Weston Schmidt, Harald Welte and OpenMoko Inc.
Copyright 2010-2021 Tormod Volden and Stefan Schmidt
This program is Free Software and has ABSOLUTELY NO WARRANTY
Please report bugs to http://sourceforge.net/p/dfu-util/tickets/

libusb version 1.0.24 (11584)
Found Runtime: [1d50:6130] ver=0100, devnum=10, cfg=1, intf=2, path="20-4.4.4", alt=0, name="USB_DFU", serial="00"
```
To switch from Run-time to DFU mode:

```
> dfu-util -ev
dfu-util 0.11

Copyright 2005-2009 Weston Schmidt, Harald Welte and OpenMoko Inc.
Copyright 2010-2021 Tormod Volden and Stefan Schmidt
This program is Free Software and has ABSOLUTELY NO WARRANTY
Please report bugs to http://sourceforge.net/p/dfu-util/tickets/

libusb version 1.0.24 (11584)
Opening DFU capable USB device...
Device ID 1d50:6130
Run-Time device DFU version 0110
DFU attributes: (0x0f) bitCanDnload bitCanUpload bitManifestationTolerant bitWillDetach
Detach timeout 1000 ms
Claiming USB DFU (Run-Time) Interface...
Setting Alternate Interface zero...
Determining device status...
Device does not implement get_status, assuming appIDLE
Device really in Run-Time Mode, send DFU detach request...
Device will detach and reattach...
```
and then to show the available DFU alternate interface settings:

```
> dfu-util -lv
dfu-util 0.11

Copyright 2005-2009 Weston Schmidt, Harald Welte and OpenMoko Inc.
Copyright 2010-2021 Tormod Volden and Stefan Schmidt
This program is Free Software and has ABSOLUTELY NO WARRANTY
Please report bugs to http://sourceforge.net/p/dfu-util/tickets/

libusb version 1.0.24 (11584)
Found DFU: [1d50:ffff] ver=0100, devnum=11, cfg=1, intf=0, path="20-4.4.4", alt=2, name="BOOT", serial="00"
Found DFU: [1d50:ffff] ver=0100, devnum=11, cfg=1, intf=0, path="20-4.4.4", alt=1, name="RD ALL", serial="00"
Found DFU: [1d50:ffff] ver=0100, devnum=11, cfg=1, intf=0, path="20-4.4.4", alt=0, name="RD/WR", serial="00"
```
Purpose of alternate interface settings is:

* `alt=0` to read/write user image at 0x28000-0x4FFFF.
* `alt=1` to read the whole 1Mbyte of flash memory.
* `alt=2` to boot user image with a fake DFU read/write.

For example to read whole flash memory:

```
> dfu-util -v -a 1 -U flash.bin
dfu-util 0.11

Copyright 2005-2009 Weston Schmidt, Harald Welte and OpenMoko Inc.
Copyright 2010-2021 Tormod Volden and Stefan Schmidt
This program is Free Software and has ABSOLUTELY NO WARRANTY
Please report bugs to http://sourceforge.net/p/dfu-util/tickets/

libusb version 1.0.24 (11584)
Opening DFU capable USB device...
Device ID 1d50:ffff
Device DFU version 0110
DFU attributes: (0x0f) bitCanDnload bitCanUpload bitManifestationTolerant bitWillDetach
Detach timeout 1000 ms
Claiming USB DFU Interface...
Setting Alternate Interface #1 ...
Determining device status...
DFU state(2) = dfuIDLE, status(0) = No error condition is present
DFU mode device DFU version 0110
Device returned transfer size 256
Copying data from DFU device to PC
Upload	[=========================] 100%      1048576 bytes
Upload done.
Received a total of 1048576 bytes
```
Or to write a new user image:

```
> dfu-util -v -a 0 -D ./user_image.bin
dfu-util 0.11

Copyright 2005-2009 Weston Schmidt, Harald Welte and OpenMoko Inc.
Copyright 2010-2021 Tormod Volden and Stefan Schmidt
This program is Free Software and has ABSOLUTELY NO WARRANTY
Please report bugs to http://sourceforge.net/p/dfu-util/tickets/

libusb version 1.0.24 (11584)
dfu-util: Warning: Invalid DFU suffix signature
dfu-util: A valid DFU suffix will be required in a future dfu-util release
Opening DFU capable USB device...
Device ID 1d50:ffff
Device DFU version 0110
DFU attributes: (0x0f) bitCanDnload bitCanUpload bitManifestationTolerant bitWillDetach
Detach timeout 1000 ms
Claiming USB DFU Interface...
Setting Alternate Interface #0 ...
Determining device status...
DFU state(2) = dfuIDLE, status(0) = No error condition is present
DFU mode device DFU version 0110
Device returned transfer size 256
Copying data from PC to DFU device
Download	[=========================] 100%       135178 bytes
Download done.
Sent a total of 135178 bytes
DFU state(7) = dfuMANIFEST, status(0) = No error condition is present
DFU state(2) = dfuIDLE, status(0) = No error condition is present
Done!
```
And after that to boot the new user image:

```
> dfu-util -v -a 2 -U dummy.bin
dfu-util 0.11

Copyright 2005-2009 Weston Schmidt, Harald Welte and OpenMoko Inc.
Copyright 2010-2021 Tormod Volden and Stefan Schmidt
This program is Free Software and has ABSOLUTELY NO WARRANTY
Please report bugs to http://sourceforge.net/p/dfu-util/tickets/

libusb version 1.0.24 (11584)
Opening DFU capable USB device...
Device ID 1d50:ffff
Device DFU version 0110
DFU attributes: (0x0f) bitCanDnload bitCanUpload bitManifestationTolerant bitWillDetach
Detach timeout 1000 ms
Claiming USB DFU Interface...
Setting Alternate Interface #2 ...
Determining device status...
DFU state(2) = dfuIDLE, status(0) = No error condition is present
DFU mode device DFU version 0110
Device returned transfer size 256
Copying data from DFU device to PC
Upload	[                         ]   0%            0 bytesdfu-util:
Error during upload (LIBUSB_ERROR_PIPE)


Failed.
```
The `LIBUSB_ERROR_PIPE` error is due to device reboot.


## `loopback`
This is an example to test USB\_DFU functionality.
At Run-time it presents a CDC/ACM function in loopback and a DFU function.

The four DFU alternate interface settings allow to read/write a small RAM and to read/write the flash memory at address 0xB0000-EFFFF.


