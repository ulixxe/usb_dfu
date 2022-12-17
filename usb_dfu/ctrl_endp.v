//  USB 2.0 full speed IN/OUT Control Endpoints.
//  Written in verilog 2001

// CTRL_ENDP module shall implement IN/OUT Control Endpoint.
// CTRL_ENDP shall manage control transfers:
//   - Provide device information.
//   - Keep device states (Default, Address and Configured).
//   - Keep Run-time and DFU Mode states.
//   - Keep and provide to SIE the device address.
//   - Respond to standard device requests:
//       - GET_STATUS (00h)
//       - CLEAR_FEATURE (01h)
//       - SET_ADDRESS (05h)
//       - GET_DESCRIPTOR (DEVICE, CONFIGURATION, STRING and BOS) (06h)
//       - GET_CONFIGURATION (08h)
//       - SET_CONFIGURATION (09h)
//       - GET_INTERFACE (0Ah)
//       - SET_INTERFACE (0Bh)
//   - Respond to Abstract Control Model (ACM) subclass requests:
//       - SET_LINE_CODING (20h)
//       - GET_LINE_CODING (21h)
//       - SET_CONTROL_LINE_STATE (22h)
//       - SEND_BREAK (23h)
//   - Respond to Run-time DFU requests:
//       - DFU_DETACH (00h)
//   - Respond to DFU Mode DFU requests:
//       - DFU_DNLOAD (01h)
//       - DFU_UPLOAD (02h)
//       - DFU_GETSTATUS (03h)
//       - DFU_CLRSTATUS (04h)
//       - DFU_GETSTATE (05h)
//       - DFU_ABORT (06h)
//   - Respond to Microsoft OS 2.0 Descriptor requests in Run-time.
//   - Respond to Microsoft OS 1.0 Descriptor requests in DFU Mode.

`define max(a,b) ((a) > (b) ? (a) : (b))
`define min(a,b) ((a) < (b) ? (a) : (b))

module ctrl_endp
  #(parameter VENDORID = 16'h0000,
    parameter             PRODUCTID = 16'h0000,
    parameter [8*128-1:0] RTI_STRING = "0", // Run-time DFU interface string
    parameter [8*128-1:0] SN_STRING = "0", // Run-time/DFU Mode Device Serial Number
    parameter [8*128-1:0] ALT_STRINGS = "0", // concatenation of strings separated by "\000" or by "\n"
    parameter             TRANSFER_SIZE = 'd64,
    parameter             POLLTIMEOUT = 'd10, // ms
    parameter             MS20 = 1, // if 0 disable run-time MS20, enable otherwire
    parameter             WCID = 1, // if 0 disable DFU Mode WCID, enable otherwire
    parameter             CTRL_MAXPACKETSIZE = 'd8,
    parameter             IN_BULK_MAXPACKETSIZE = 'd8,
    parameter             OUT_BULK_MAXPACKETSIZE = 'd8,
    parameter             ENDP_BULK = 4'd1,
    parameter             ENDP_INT = 4'd2)
   (
    // ---- to/from USB_DFU module ---------------------------------
    input         clk_i,
    // clk_i clock shall have a frequency of 12MHz*BIT_SAMPLES.
    input         rstn_i,
    // While rstn_i is low (active low), the module shall be reset.
    output        configured_o,
    // While USB_CDC is in configured state, configured_o shall be high.

    // ---- to/from SIE module ------------------------------------
    input         usb_reset_i,
    // While usb_reset_i is high, the module shall be reset.
    output        usb_en_o,
    // While device is in POWERED_STATE and usb_reset_i is low, usb_en_o shall be low.
    output        usb_detach_o,
    // When a DFU_DETACH request is received, usb_detach_o shall change from low to high.
    // When usb_reset_i is high, usb_detach_o shall change from high to low.
    output [6:0]  addr_o,
    // addr_o shall be the device address.
    // addr_o shall be updated at the end of SET_ADDRESS control transfer.
    output        stall_o,
    // While control pipe is addressed and is in stall state, stall_o shall
    //   be high, otherwise shall be low.
    output        out_toggle_reset_o,
    // When out_toggle_reset_o is high, data toggle synchronization of
    //   OUT bulk pipe shall be reset to DATA0.
    output        in_toggle_reset_o,
    // When in_toggle_reset_o is high, data toggle synchronization of
    //   IN bulk pipe shall be reset to DATA0.
    output [7:0]  in_data_o,
    // While in_valid_o is high and in_zlp_o is low, in_data_o shall be valid.
    output        in_zlp_o,
    // While in_req_i is high and IN Control Endpoint have to reply with zero length
    //   packet, IN Control Endpoint shall put both in_zlp_o and in_valid_o high.
    output        in_valid_o,
    // While in_req_i is high and IN Control Endpoint have data or zero length packet
    //   available, IN Control Endpoint shall put in_valid_o high.
    input         in_req_i,
    input         in_ready_i,
    // When both in_ready_i and in_valid_o are high, in_data_o or zero length
    //   packet shall be consumed.
    // When in_data_o or zlp is consumed, in_ready_i shall be high only for
    //   one clk_i period.
    input         setup_i,
    // While last correctly checked PID (USB2.0 8.3.1) is SETUP, setup_i shall
    //   be high, otherwise shall be low.
    input         in_data_ack_i,
    // When in_data_ack_i is high and out_ready_i is high, an ACK packet shall be received.
    input [7:0]   out_data_i,
    input         out_valid_i,
    // While out_valid_i is high, the out_data_i shall be valid and both
    //   out_valid_i and out_data_i shall not change until consumed.
    input         out_err_i,
    // When both out_err_i and out_ready_i are high, SIE shall abort the
    //   current packet reception and OUT Control Endpoint shall manage the error
    //   condition.
    input         out_ready_i,
    // When both out_valid_i and out_ready_i are high, the out_data_i shall
    //   be consumed.
    // When setup_i is high and out_ready_i is high, a new SETUP transaction shall be
    //   received.
    // When setup_i, in_data_ack_i, out_valid_i and out_err_i are low and out_ready_i is high, the
    //   on-going OUT transaction shall end.
    // out_ready_i shall be high only for one clk_i period.

    // ---- to/from DFU functions ------------------------------------
    output        dfu_mode_o,
    // While device is in DFU Mode, dfu_mode_o shall be high.
    output [2:0]  dfu_alt_o,
    // dfu_alt_o shall report the current alternate interface setting.
    output        dfu_upload_o,
    // While DFU is in dfuUPLOAD_IDLE state, dfu_upload_o shall be high.
    output        dfu_dnload_o,
    // While DFU is in dfuDNBUSY|dfuDNLOAD_SYNC|dfuDNLOAD_IDLE states, dfu_dnload_o shall be high.
    output        dfu_fifo_o,
    // While DFU is transferring data for DFU_DNLOAD/DFU_UPLOAD requests, dfu_fifo_o shall be high.
    output        dfu_clear_status_o,
    // While DFU is in dfuIDLE state, dfu_clear_status_o shall be high.
    output [15:0] dfu_blocknum_o,
    // dfu_blocknum_o shall report DFU_DNLOAD/DFU_UPLOAD block sequence number.
    input [3:0]   dfu_status_i,
    // dfu_status_i shall report the status resulting from the execution of the most recent DFU request.
    input         dfu_busy_i,
    // When DFU_DNLOAD request target is busy and needs time to be ready for next data, dfu_busy_i
    //   shall be high.
    input         dfu_done_i
    // When DFU_DNLOAD/DFU_UPLOAD request target has finished, dfu_done_i shall be high.
    // When dfu_clear_status_o is high, dfu_done_i shall return low.
    );

   function integer ceil_log2;
      input integer arg;
      begin
         ceil_log2 = 0;
         while ((2 ** ceil_log2) < arg)
           ceil_log2 = ceil_log2 + 1;
      end
   endfunction

   function is_sep;
      input [7:0] char;
      begin
         is_sep = (char == "\000" || char == "\n") ? 1'b1 : 1'b0;
      end
   endfunction

   function integer nstrings;
      input [8*128-1:0] string_arg; // concatenation of strings separated by "\000" or by "\n"
      integer           i;
      reg [7:0]         char;
      begin
         nstrings = 0;
         char = "\000";
         for (i = 128; i > 0; i = i - 1) begin
            if (~is_sep(string_arg[8*i-1 -:8]) && is_sep(char))
              nstrings = nstrings + 1;
            char = string_arg[8*i-1 -:8];
         end
      end
   endfunction

   function integer string_pos;
      input [8*128-1:0] string_arg; // concatenation of strings separated by "\000" or by "\n"
      input integer     int_arg; // string index starting from 1
      integer           i;
      reg [7:0]         char;
      begin
         string_pos = 128;
         char = "\000";
         i = 0;
         while (string_pos > 0 && i < int_arg) begin
            if (~is_sep(string_arg[8*string_pos-1 -:8]) && is_sep(char))
              i = i + 1;
            char = string_arg[8*string_pos-1 -:8];
            string_pos = string_pos - 1;
         end
         if (i == int_arg)
           string_pos = string_pos + 1;
      end
   endfunction

   function integer string_length;
      input [8*128-1:0] string_arg; // concatenation of strings separated by "\000" or by "\n"
      input integer     int_arg; // string index starting from 1
      integer           i;
      begin
         string_length = 0;
         i = string_pos(string_arg, int_arg);
         while (string_length == 0 && i > 0) begin
            if (is_sep(string_arg[8*i-1 -:8]))
              string_length = string_pos(string_arg, int_arg) - i;
            i = i - 1;
         end
         if (i == 0 && ~is_sep(string_arg[7 -:8]))
           string_length = string_pos(string_arg, int_arg);
      end
   endfunction

   function [8*128-1:0] string_descr;
      input [8*128-1:0] string_arg; // concatenation of strings separated by "\000" or by "\n"
      input integer     int_arg; // string index starting from 1
      integer           i;
      begin
         string_descr = {128{8'h00}};
         i = 2*string_length(string_arg, int_arg)+2;
         // UNICODE String Descriptor, USB2.0 9.6.7, page 273-274, Table 9-16
         string_descr[7:0] = i[7:0]; // bLength
         string_descr[15:8] = 8'h03; // bDescriptorType (STRING)
         for (i = 0; i < string_length(string_arg, int_arg); i = i + 1) begin
            string_descr[8*(2*i+3)-1 -:8] = string_arg[8*(string_pos(string_arg, int_arg)-i)-1 -:8];
            string_descr[8*(2*i+4)-1 -:8] = 8'h00;
         end
      end
   endfunction

   localparam ALT = nstrings(ALT_STRINGS);

   function [ALT*32-1:0] string_lengths;
      input [8*128-1:0] string_arg;
      integer           i;
      begin
         for (i=0; i < ALT; i = i + 1)
           string_lengths[i*32 +:32] = string_length(string_arg, i+1)*2+2;
      end
   endfunction

   localparam [ALT*32-1:0] STRING_DESCR_LENGTHS = string_lengths(ALT_STRINGS);

   function [ALT*8*128-1:0] string_descrs;
      input [8*128-1:0]    string_arg;
      integer              i;
      begin
         for (i=0; i < ALT; i = i + 1)
           string_descrs[i*8*128 +:8*128] = string_descr(string_arg, i+1);
      end
   endfunction

   localparam [ALT*8*128-1:0] STRING_DESCRS = string_descrs(ALT_STRINGS);
   localparam                 FIRST_ALT_STRING = 'd3; // First Alternate Setting String

   function [8*'h09*ALT-1:0] alt_descr;
      input integer           arg;
      integer                 i;
      begin
         for (i = 0; i < arg; i = i + 1) begin
            alt_descr[8*'h09*i +:8*'h09] = {
                                            i[7:0]+FIRST_ALT_STRING[7:0], // iInterface
                                            8'h02, // bInterfaceProtocol (DFU Mode)
                                            8'h01, // bInterfaceSubClass (Device Firmware Upgrade)
                                            8'hFE, // bInterfaceClass (Application Specific)
                                            8'h00, // bNumEndpoints
                                            i[7:0],// bAlternateSetting
                                            8'h00, // bInterfaceNumber
                                            8'h04, // bDescriptorType (INTERFACE)
                                            8'h09  // bLength
                                            // DFU Interface Descriptor, DFU1.1 4.2.3, page 15-16, Table 4-4
                                            };
         end
      end
   endfunction

   localparam DETACH_TIMEOUT = 1000;
   localparam [15:0] DFU_PRODUCTID = 16'hFFFF;
   localparam [7:0]  VENDORCODE = 8'h77;

   // Run-time Device Descriptor (in reverse order)
   localparam [8*'h12-1:0] DEV_DESCR = {8'h01, // bNumConfigurations
                                        8'h01, // iSerialNumber (STRING_DESCR_01 string)
                                        8'h00, // iProduct (no string)
                                        8'h00, // iManufacturer (no string)
                                        8'h01, // bcdDevice[1] (1.00)
                                        8'h00, // bcdDevice[0]
                                        PRODUCTID[15:8], // idProduct[1]
                                        PRODUCTID[7:0], // idProduct[0]
                                        VENDORID[15:8], // idVendor[1]
                                        VENDORID[7:0], // idVendor[0]
                                        CTRL_MAXPACKETSIZE[7:0], // bMaxPacketSize0
                                        8'h01, // bDeviceProtocol (Interface Association Descriptor)
                                        8'h02, // bDeviceSubClass (Common Class)
                                        8'hEF, // bDeviceClass (Miscellaneous Device Class)
                                        8'h02, // bcdUSB[1] (2.10)
                                        8'h10, // bcdUSB[0]
                                        8'h01, // bDescriptorType (DEVICE)
                                        8'h12 // bLength
                                        }; // Standard Device Descriptor, USB2.0 9.6.1, page 261-263, Table 9-8

   // Run-time Configuration Descriptor (in reverse order)
   localparam              DFU_INTF = 'h02;
   localparam              CDL = 'h9+'h9+'h7+'h7+'h9+'h7+'h5+'h4+'h5+'h5+'h9+'h8+'h9; // CONF_DESCR Length
   localparam [8*CDL-1:0]  CONF_DESCR = {8'h01, // bcdDFUVersion[1] (1.10)
                                         8'h10, // bcdDFUVersion[0]
                                         TRANSFER_SIZE[15:8], // wTransferSize[1]
                                         TRANSFER_SIZE[7:0], // wTransferSize[0]
                                         DETACH_TIMEOUT[15:8], // wDetachTimeOut[1]
                                         DETACH_TIMEOUT[7:0], // wDetachTimeOut[0]
                                         8'h0F, // bmAttributes (bitWillDetach, bitManifestationTolerant, bitCanUpload, bitCanDnload)
                                         8'h21, // bDescriptorType (DFU FUNCTIONAL)
                                         8'h09, // bLength
                                         // DFU Functional Descriptor, DFU1.1 4.1.3, page 13-14, Table 4-2

                                         8'h02, // iInterface (STRING_DESCR_02 string)
                                         8'h01, // bInterfaceProtocol (Run-time)
                                         8'h01, // bInterfaceSubClass (Device Firmware Upgrade)
                                         8'hFE, // bInterfaceClass (Application Specific)
                                         8'h00, // bNumEndpoints
                                         8'h00, // bAlternateSetting
                                         DFU_INTF[7:0], // bInterfaceNumber
                                         8'h04, // bDescriptorType (INTERFACE)
                                         8'h09, // bLength
                                         // DFU Interface Descriptor, DFU1.1 4.1.2, page 11-12, Table 4-1

                                         8'h00, // bInterval
                                         8'h00, // wMaxPacketSize[1]
                                         IN_BULK_MAXPACKETSIZE[7:0], // wMaxPacketSize[0]
                                         8'h02, // bmAttributes (bulk)
                                         {4'h8, ENDP_BULK}, // bEndpointAddress (1 IN)
                                         8'h05, // bDescriptorType (ENDPOINT)
                                         8'h07, // bLength
                                         // Standard Endpoint Descriptor, USB2.0 9.6.6, page 269-271, Table 9-13

                                         8'h00, // bInterval
                                         8'h00, // wMaxPacketSize[1]
                                         OUT_BULK_MAXPACKETSIZE[7:0], // wMaxPacketSize[0]
                                         8'h02, // bmAttributes (bulk)
                                         {4'h0, ENDP_BULK}, // bEndpointAddress (1 OUT)
                                         8'h05, // bDescriptorType (ENDPOINT)
                                         8'h07, // bLength
                                         // Standard Endpoint Descriptor, USB2.0 9.6.6, page 269-271, Table 9-13

                                         8'h00, // iInterface (no string)
                                         8'h00, // bInterfaceProtocol
                                         8'h00, // bInterfaceSubClass
                                         8'h0A, // bInterfaceClass (CDC-Data)
                                         8'h02, // bNumEndpoints
                                         8'h00, // bAlternateSetting
                                         8'h01, // bInterfaceNumber
                                         8'h04, // bDescriptorType (INTERFACE)
                                         8'h09, // bLength
                                         // Standard Interface Descriptor, USB2.0 9.6.5, page 267-269, Table 9-12

                                         8'hFF, // bInterval (255 ms)
                                         8'h00, // wMaxPacketSize[1]
                                         8'h08, // wMaxPacketSize[0]
                                         8'h03, // bmAttributes (interrupt)
                                         {4'h8, ENDP_INT}, // bEndpointAddress (2 IN)
                                         8'h05, // bDescriptorType (ENDPOINT)
                                         8'h07, // bLength
                                         // Standard Endpoint Descriptor, USB2.0 9.6.6, page 269-271, Table 9-13

                                         8'h01, // bSlaveInterface0
                                         8'h00, // bMasterInterface
                                         8'h06, // bDescriptorSubtype (Union Functional)
                                         8'h24, // bDescriptorType (CS_INTERFACE)
                                         8'h05, // bFunctionLength
                                         // Union Functional Descriptor, CDC1.1 5.2.3.8, Table 33

                                         8'h00, // bmCapabilities (none)
                                         8'h02, // bDescriptorSubtype (Abstract Control Management Functional)
                                         8'h24, // bDescriptorType (CS_INTERFACE)
                                         8'h04, // bFunctionLength
                                         // Abstract Control Management Functional Descriptor, CDC1.1 5.2.3.3, Table 28

                                         8'h01, // bDataInterface
                                         8'h00, // bmCapabilities (no call mgmnt)
                                         8'h01, // bDescriptorSubtype (Call Management Functional)
                                         8'h24, // bDescriptorType (CS_INTERFACE)
                                         8'h05, // bFunctionLength
                                         // Call Management Functional Descriptor, CDC1.1 5.2.3.2, Table 27

                                         8'h01, // bcdCDC[1] (1.1)
                                         8'h10, // bcdCDC[0]
                                         8'h00, // bDescriptorSubtype (Header Functional)
                                         8'h24, // bDescriptorType (CS_INTERFACE)
                                         8'h05, // bFunctionLength
                                         // Header Functional Descriptor, CDC1.1 5.2.3.1, Table 26

                                         8'h00, // iInterface (no string)
                                         8'h01, // bInterfaceProtocol (AT Commands in ITU V.25ter)
                                         8'h02, // bInterfaceSubClass (Abstract Control Model)
                                         8'h02, // bInterfaceClass (Communications Device Class)
                                         8'h01, // bNumEndpoints
                                         8'h00, // bAlternateSetting
                                         8'h00, // bInterfaceNumber
                                         8'h04, // bDescriptorType (INTERFACE)
                                         8'h09, // bLength
                                         // Standard Interface Descriptor, USB2.0 9.6.5, page 267-269, Table 9-12

                                         8'h00, // iFunction (no string)
                                         8'h01, // bFunctionProtocol (AT Commands in ITU V.25ter)
                                         8'h02, // bFunctionSubClass (Abstract Control Model)
                                         8'h02, // bFunctionClass (Communications Device Class)
                                         8'h02, // bInterfaceCount
                                         8'h00, // bFirstInterface
                                         8'h0B, // bDescriptorType (INTERFACE ASSOCIATION)
                                         8'h08, // bLength
                                         // Interface Association Descriptor, USB2.0 ECN 9.X.Y, page 4-5, Table 9-Z

                                         8'h32, // bMaxPower (100mA)
                                         8'h80, // bmAttributes (bus powered, no remote wakeup)
                                         8'h00, // iConfiguration (no string)
                                         8'h01, // bConfigurationValue
                                         8'h03, // bNumInterfaces
                                         CDL[15:8], // wTotalLength[1]
                                         CDL[7:0], // wTotalLength[0]
                                         8'h02, // bDescriptorType (CONFIGURATION)
                                         8'h09 // bLength
                                         }; // Standard Configuration Descriptor, USB2.0 9.6.3, page 264-266, Table 9-10

   // DFU Mode Device Descriptor (in reverse order)
   localparam [8*'h12-1:0] DFU_DEV_DESCR = {8'h01, // bNumConfigurations
                                            8'h01, // iSerialNumber (STRING_DESCR_01 string)
                                            8'h00, // iProduct (no string)
                                            8'h00, // iManufacturer (no string)
                                            8'h01, // bcdDevice[1] (1.00)
                                            8'h00, // bcdDevice[0]
                                            DFU_PRODUCTID[15:8], // idProduct[1]
                                            DFU_PRODUCTID[7:0], // idProduct[0]
                                            VENDORID[15:8], // idVendor[1]
                                            VENDORID[7:0], // idVendor[0]
                                            CTRL_MAXPACKETSIZE[7:0], // bMaxPacketSize0
                                            8'h00, // bDeviceProtocol (specified at interface level)
                                            8'h00, // bDeviceSubClass (specified at interface level)
                                            8'h00, // bDeviceClass (specified at interface level)
                                            8'h02, // bcdUSB[1] (2.00)
                                            8'h00, // bcdUSB[0]
                                            8'h01, // bDescriptorType (DEVICE)
                                            8'h12 // bLength
                                            }; // DFU Device Descriptor, DFU1.1 4.2.1, page 14-15, Table 4-3

   // DFU Mode Configuration Descriptor (in reverse order)
   localparam              DCDL = 'h9+'h9*ALT+'h9; // DFU_CONF_DESCR Length
   localparam [8*DCDL-1:0] DFU_CONF_DESCR = {8'h01, // bcdDFUVersion[1] (1.10)
                                             8'h10, // bcdDFUVersion[0]
                                             TRANSFER_SIZE[15:8], // wTransferSize[1]
                                             TRANSFER_SIZE[7:0], // wTransferSize[0]
                                             DETACH_TIMEOUT[15:8], // wDetachTimeOut[1]
                                             DETACH_TIMEOUT[7:0], // wDetachTimeOut[0]
                                             8'h0F, // bmAttributes (bitWillDetach, bitManifestationTolerant, bitCanUpload, bitCanDnload)
                                             8'h21, // bDescriptorType (DFU FUNCTIONAL)
                                             8'h09, // bLength
                                             // DFU Functional Descriptor, DFU1.1 4.1.3, page 13-14, Table 4-2

                                             alt_descr(ALT),

                                             8'h32, // bMaxPower (100mA)
                                             8'h80, // bmAttributes (bus powered, no remote wakeup)
                                             8'h00, // iConfiguration (no string)
                                             8'h01, // bConfigurationValue
                                             8'h01, // bNumInterfaces
                                             DCDL[15:8], // wTotalLength[1]
                                             DCDL[7:0], // wTotalLength[0]
                                             8'h02, // bDescriptorType (CONFIGURATION)
                                             8'h09 // bLength
                                             }; // Standard Configuration Descriptor, USB1.0

   // String Descriptor Zero (in reverse order)
   localparam [8*'h4-1:0]  STRING_DESCR_00 = {8'h04, // wLANGID[1] (US English)
                                              8'h09, // wLANGID[0]
                                              8'h03, // bDescriptorType (STRING)
                                              8'h04 // bLength
                                              }; // String Descriptor Zero, USB2.0 9.6.7, page 273-274, Table 9-15

   // SerialNumber String Descriptor
   localparam              STR01L = 2*string_length(SN_STRING, 1)+2; // STRING_DESCR_01 Length
   localparam [8*128-1:0]  STRING_DESCR_01 = string_descr(SN_STRING, 1);

   // Run-time DFU interface String Descriptor
   localparam              STR02L = 2*string_length(RTI_STRING, 1)+2; // STRING_DESCR_02 Length
   localparam [8*128-1:0]  STRING_DESCR_02 = string_descr(RTI_STRING, 1);

   // DFU Mode WCID String Descriptor (in reverse order)
   localparam [8*'h12-1:0] STRING_DESCR_EE = {8'h00, // bPad
                                              VENDORCODE, // bMS_VendorCode
                                              8'h00, "0",
                                              8'h00, "0",
                                              8'h00, "1",
                                              8'h00, "T",
                                              8'h00, "F",
                                              8'h00, "S",
                                              8'h00, "M", // qwSignature
                                              8'h03, // bDescriptorType (STRING)
                                              8'h12 // bLength
                                              }; // UNICODE String Descriptor, USB2.0 9.6.7, page 273-274, Table 9-16

   // Run-time Microsoft OS 2.0 Platform Capability Descriptor (in reverse order)
   localparam              MS20RL = 'h50+'h2+'h2A+'h8; // MSOS registry property Descriptor Length
   localparam              MS20FL = MS20RL+'h14+'h8; // MSOS Descriptor Funtion Subset Length
   localparam              MS20CL = MS20FL+'h8; // MSOS Descriptor Configuration TotalLength
   localparam              MS20L = MS20CL+'hA; // MSOSDescriptorSetTotalLength
   localparam [8*'h21-1:0] BOS_DESCR = {8'h00, // bAltEnumCode
                                        VENDORCODE, // bMS_VendorCode
                                        MS20L[15:8], MS20L[7:0], // wMSOSDescriptorSetTotalLength
                                        8'h06, 8'h03, 8'h00, 8'h00, // dwWindowsVersion (Windows 8.1)
                                        8'h9F, 8'h8A, 8'h64, 8'h9E, 8'h9D, 8'h65,
                                        8'hD2, 8'h9C,
                                        8'h4C, 8'hC7,
                                        8'h45, 8'h89,
                                        8'hD8, 8'hDD, 8'h60, 8'hDF, // UUID (D8DD60DF-4589-4CC7-9CD2-659D9E648A9F)
                                        // MS OS 2.0 Platform Capability ID

                                        8'h00, // bReserved
                                        8'h05, // bDevCapabilityType (PLATFORM)
                                        8'h10, // bDescriptorType (DEVICE CAPABILITY)
                                        8'h1C, // bLength
                                        // Microsoft OS 2.0 Platform Capability Descriptor

                                        8'h01, // bNumDeviceCaps
                                        8'h00, 8'h21, // wTotalLength
                                        8'h0F, // bDescriptorType (BOS)
                                        8'h05 // bLength
                                        }; // BOS Descriptor

   // Run-time Microsoft OS 2.0 Descriptor Set (in reverse order)
   localparam [8*MS20L-1:0] MS20_DESCR = {8'h00, 8'h00,
                                          8'h00, 8'h00,
                                          8'h00, "}",
                                          8'h00, "f",
                                          8'h00, "f",
                                          8'h00, "d",
                                          8'h00, "a",
                                          8'h00, "4",
                                          8'h00, "1",
                                          8'h00, "6",
                                          8'h00, "f",
                                          8'h00, "5",
                                          8'h00, "d",
                                          8'h00, "9",
                                          8'h00, "8",
                                          8'h00, "-",
                                          8'h00, "2",
                                          8'h00, "f",
                                          8'h00, "d",
                                          8'h00, "a",
                                          8'h00, "-",
                                          8'h00, "5",
                                          8'h00, "7",
                                          8'h00, "3",
                                          8'h00, "4",
                                          8'h00, "-",
                                          8'h00, "4",
                                          8'h00, "4",
                                          8'h00, "8",
                                          8'h00, "0",
                                          8'h00, "-",
                                          8'h00, "e",
                                          8'h00, "a",
                                          8'h00, "1",
                                          8'h00, "6",
                                          8'h00, "9",
                                          8'h00, "7",
                                          8'h00, "4",
                                          8'h00, "d",
                                          8'h00, "{", // PropertyData ({d47961ae-0844-4375-adf2-89d5f614adff}\0\0)
                                          8'h00, 8'h50, // wPropertyDataLength
                                          8'h00, 8'h00,
                                          8'h00, "s",
                                          8'h00, "D",
                                          8'h00, "I",
                                          8'h00, "U",
                                          8'h00, "G",
                                          8'h00, "e",
                                          8'h00, "c",
                                          8'h00, "a",
                                          8'h00, "f",
                                          8'h00, "r",
                                          8'h00, "e",
                                          8'h00, "t",
                                          8'h00, "n",
                                          8'h00, "I",
                                          8'h00, "e",
                                          8'h00, "c",
                                          8'h00, "i",
                                          8'h00, "v",
                                          8'h00, "e",
                                          8'h00, "D", // PropertyName (DeviceInterfaceGUIDs)
                                          8'h00, 8'h2A, // wPropertyNameLength
                                          8'h00, 8'h07, // wPropertyDataType
                                          8'h00, 8'h04, // wDescriptorType (MS_OS_20_FEATURE_REG_PROPERTY)
                                          MS20RL[15:8], MS20RL[7:0], // wLength
                                          // Microsoft OS 2.0 Registry Property Descriptor

                                          8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, // SubCompatibleID
                                          8'h00, 8'h00, "B", "S", "U", "N", "I", "W", // CompatibleID
                                          8'h00, 8'h03, // wDescriptorType (MS_OS_FEATURE_COMPATIBLE_ID)
                                          8'h00, 8'h14, // wLength
                                          // Microsoft OS 2.0 Compatible ID Descriptor

                                          MS20FL[15:8], MS20FL[7:0], // wSubsetLength
                                          8'h00, // bReserved
                                          DFU_INTF[7:0], // bFirstInterface
                                          8'h00, 8'h02, // wDescriptorType (MS_OS_20_SUBSET_HEADER_FUNCTION)
                                          8'h00, 8'h08, // wLength
                                          // Microsoft OS 2.0 Function Subset Header

                                          MS20CL[15:8], MS20CL[7:0], // wTotalLength
                                          8'h00, // bReserved
                                          8'h00, // bConfigurationValue
                                          8'h00, 8'h01, // wDescriptorType (MS_OS_20_SUBSET_HEADER_CONFIGURATION)
                                          8'h00, 8'h08, // wLength
                                          // Microsoft OS 2.0 Configuration Subset Header

                                          MS20L[15:8], MS20L[7:0], // wTotalLength
                                          8'h06, 8'h03, 8'h00, 8'h00, // dwWindowsVersion (Windows 8.1)
                                          8'h00, 8'h00, // wDescriptorType (MS_OS_20_SET_HEADER_DESCRIPTOR)
                                          8'h00, 8'h0A // wLength
                                          }; // Microsoft OS 2.0 Descriptor Set Header

   // DFU Mode WCID Extended Properties Feature Descriptor (in reverse order)
   localparam [8*'h8e-1:0]  EXT_WCID_DESCR = {8'h00, 8'h00,
                                              8'h00, "}",
                                              8'h00, "f",
                                              8'h00, "f",
                                              8'h00, "d",
                                              8'h00, "a",
                                              8'h00, "4",
                                              8'h00, "1",
                                              8'h00, "6",
                                              8'h00, "f",
                                              8'h00, "5",
                                              8'h00, "d",
                                              8'h00, "9",
                                              8'h00, "8",
                                              8'h00, "-",
                                              8'h00, "2",
                                              8'h00, "f",
                                              8'h00, "d",
                                              8'h00, "a",
                                              8'h00, "-",
                                              8'h00, "5",
                                              8'h00, "7",
                                              8'h00, "3",
                                              8'h00, "4",
                                              8'h00, "-",
                                              8'h00, "4",
                                              8'h00, "4",
                                              8'h00, "8",
                                              8'h00, "0",
                                              8'h00, "-",
                                              8'h00, "e",
                                              8'h00, "a",
                                              8'h00, "1",
                                              8'h00, "6",
                                              8'h00, "9",
                                              8'h00, "7",
                                              8'h00, "4",
                                              8'h00, "d",
                                              8'h00, "{", // wPropertyData ({d47961ae-0844-4375-adf2-89d5f614adff}\0)
                                              8'h00, // dwPropertyDataLength[3]
                                              8'h00, // dwPropertyDataLength[2]
                                              8'h00, // dwPropertyDataLength[1]
                                              8'h4e, // dwPropertyDataLength[0]
                                              8'h00, 8'h00,
                                              8'h00, "D",
                                              8'h00, "I",
                                              8'h00, "U",
                                              8'h00, "G",
                                              8'h00, "e",
                                              8'h00, "c",
                                              8'h00, "a",
                                              8'h00, "f",
                                              8'h00, "r",
                                              8'h00, "e",
                                              8'h00, "t",
                                              8'h00, "n",
                                              8'h00, "I",
                                              8'h00, "e",
                                              8'h00, "c",
                                              8'h00, "i",
                                              8'h00, "v",
                                              8'h00, "e",
                                              8'h00, "D", // wPropertyName (DeviceInterfaceGUIDs)
                                              8'h00, // wPropertyNameLength[1]
                                              8'h28, // wPropertyNameLength[0]
                                              8'h00, // dwPropertyDataType[3]
                                              8'h00, // dwPropertyDataType[2]
                                              8'h00, // dwPropertyDataType[1]
                                              8'h01, // dwPropertyDataType[0]
                                              8'h00, // dwSize[3]
                                              8'h00, // dwSize[2]
                                              8'h00, // dwSize[1]
                                              8'h84, // dwSize[0]
                                              8'h00, // wCount[1] (0x0001)
                                              8'h01, // wCount[0]
                                              8'h00, // wIndex[1] (0x0005)
                                              8'h05, // wIndex[0]
                                              8'h01, // bcdVersion[1] (1.0)
                                              8'h00, // bcdVersion[0]
                                              8'h00, // dwLength[3]
                                              8'h00, // dwLength[2]
                                              8'h00, // dwLength[1]
                                              8'h8e // dwLength[0]
                                              };

   // DFU Mode WCID Descriptor (in reverse order)
   localparam [8*'h28-1:0]  WCID_DESCR = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, // Reserved
                                          8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, // SubCompatibleID
                                          8'h00, 8'h00, "B", "S", "U", "N", "I", "W", // CompatibleID
                                          8'h01, // Reserved
                                          8'h00, // bFirstInterfaceNumber (DFU Mode Interface)
                                          8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, // Reserved
                                          8'h01, // bCount
                                          8'h00, // wIndex[1] (0x0004)
                                          8'h04, // wIndex[0]
                                          8'h01, // bcdVersion[1] (1.0)
                                          8'h00, // bcdVersion[0]
                                          8'h00, // dwLength[3]
                                          8'h00, // dwLength[2]
                                          8'h00, // dwLength[1]
                                          8'h28 // dwLength[0]
                                          };

   localparam [3:0]         DFU_ST_appIDLE = 4'd0,
                            DFU_ST_appDETACH = 4'd1,
                            DFU_ST_dfuIDLE = 4'd2,
                            DFU_ST_dfuDNLOAD_SYNC = 4'd3,
                            DFU_ST_dfuDNBUSY = 4'd4,
                            DFU_ST_dfuDNLOAD_IDLE = 4'd5,
                            DFU_ST_dfuMANIFEST_SYNC = 4'd6,
                            DFU_ST_dfuMANIFEST = 4'd7,
                            DFU_ST_dfuMANIFEST_WAIT_RESET = 4'd8,
                            DFU_ST_dfuUPLOAD_IDLE = 4'd9,
                            DFU_ST_dfuERROR = 4'd10,
                            DFU_ST_dfuIDLE0 = 4'd11;

   localparam [1:0]         ST_IDLE = 2'd0,
                            ST_STALL = 2'd1,
                            ST_SETUP = 2'd2,
                            ST_DATA = 2'd3;
   localparam [1:0]         REC_DEVICE = 2'd0,
                            REC_INTERFACE = 2'd1,
                            REC_ENDPOINT = 2'd2;
   // Supported Standard Requests
   localparam [7:0]         STD_REQ_GET_STATUS = 'd0,
                            STD_REQ_CLEAR_FEATURE = 'd1,
                            STD_REQ_SET_ADDRESS = 'd5,
                            STD_REQ_GET_DESCRIPTOR = 'd6,
                            STD_REQ_GET_CONFIGURATION = 'd8,
                            STD_REQ_SET_CONFIGURATION = 'd9,
                            STD_REQ_GET_INTERFACE = 'd10,
                            STD_REQ_SET_INTERFACE = 'd11;
   // Supported ACM Class Requests
   localparam [7:0]         ACM_REQ_SET_LINE_CODING = 'h20,
                            ACM_REQ_GET_LINE_CODING = 'h21,
                            ACM_REQ_SET_CONTROL_LINE_STATE = 'h22,
                            ACM_REQ_SEND_BREAK = 'h23;
   // DFU Class Requests
   localparam [7:0]         DFU_REQ_DETACH = 'd0,
                            DFU_REQ_DNLOAD = 'd1,
                            DFU_REQ_UPLOAD = 'd2,
                            DFU_REQ_GETSTATUS = 'd3,
                            DFU_REQ_CLRSTATUS = 'd4,
                            DFU_REQ_GETSTATE = 'd5,
                            DFU_REQ_ABORT = 'd6;
   localparam [4:0]         REQ_NONE = 5'd0,
                            REQ_CLEAR_FEATURE = 5'd1,
                            REQ_GET_CONFIGURATION = 5'd2,
                            REQ_GET_DESCRIPTOR = 5'd3,
                            REQ_GET_DESCRIPTOR_DEVICE = 5'd4,
                            REQ_GET_DESCRIPTOR_CONFIGURATION = 5'd5,
                            REQ_GET_DESCRIPTOR_STRING = 5'd6,
                            REQ_GET_DESCRIPTOR_BOS = 5'd7,
                            REQ_GET_INTERFACE = 5'd8,
                            REQ_GET_STATUS = 5'd9,
                            REQ_SET_ADDRESS = 5'd10,
                            REQ_SET_CONFIGURATION = 5'd11,
                            REQ_SET_INTERFACE = 5'd12,
                            REQ_DFU_DETACH = 5'd13,
                            REQ_DFU_DNLOAD = 5'd14,
                            REQ_DFU_UPLOAD = 5'd15,
                            REQ_DFU_GETSTATUS = 5'd16,
                            REQ_DFU_CLRSTATUS = 5'd17,
                            REQ_DFU_GETSTATE = 5'd18,
                            REQ_DFU_ABORT = 5'd19,
                            REQ_MS20 = 5'd20,
                            REQ_WCID = 5'd21,
                            REQ_EXT_WCID = 5'd22,
                            REQ_DUMMY = 5'd23,
                            REQ_UNSUPPORTED = 5'd24;
   localparam [1:0]         POWERED_STATE = 2'd0,
                            DEFAULT_STATE = 2'd1,
                            ADDRESS_STATE = 2'd2,
                            CONFIGURED_STATE = 2'd3;

   localparam               BC_WIDTH = ceil_log2(`max(TRANSFER_SIZE+1, `max(CDL+1, `max(DCDL+1, `max(MS20L+1, 'h8e+1)))));

   reg [3:0]                dfu_state_q, dfu_state_d;
   reg [1:0]                state_q, state_d;
   reg [BC_WIDTH-1:0]       byte_cnt_q, byte_cnt_d;
   reg [BC_WIDTH-1:0]       max_length_q, max_length_d;
   reg [15:0]               blocknum_q, blocknum_d;
   reg                      in_dir_q, in_dir_d;
   reg                      class_q, class_d;
   reg                      vendor_q, vendor_d;
   reg [1:0]                rec_q, rec_d;
   reg [4:0]                req_q, req_d;
   reg [7:0]                string_index_q, string_index_d;
   reg [2:0]                alternate_setting_q, alternate_setting_d;
   reg [1:0]                dev_state_q, dev_state_d;
   reg [1:0]                dev_state_qq, dev_state_dd;
   reg [6:0]                addr_q, addr_d;
   reg [6:0]                addr_qq, addr_dd;
   reg                      in_endp_q, in_endp_d;
   reg [7:0]                in_data;
   reg                      in_zlp;
   reg                      in_valid;
   reg                      in_toggle_reset, out_toggle_reset;
   reg                      in_req_q;
   reg                      usb_reset_q;

   wire                     clk_gate;
   wire                     rstn;

   assign dfu_mode_o = (dfu_state_q != DFU_ST_appIDLE) ? 1'b1 : 1'b0;
   assign dfu_alt_o = alternate_setting_q;
   assign configured_o = (dev_state_qq == CONFIGURED_STATE) ? 1'b1 : 1'b0;
   assign addr_o = addr_qq;
   assign stall_o = (state_q == ST_STALL) ? 1'b1 : 1'b0;
   assign in_data_o = in_data;
   assign in_zlp_o = in_zlp & in_req_q;
   assign in_valid_o = in_valid & in_req_q;
   assign in_toggle_reset_o = in_toggle_reset;
   assign out_toggle_reset_o = out_toggle_reset;

   assign clk_gate = in_ready_i | out_ready_i;

   always @(posedge clk_i or negedge rstn_i) begin
      if (~rstn_i) begin
         in_req_q <= 1'b0;
         usb_reset_q <= 1'b0;
         dev_state_qq <= POWERED_STATE;
         dfu_state_q <= DFU_ST_appIDLE;
      end else begin
         in_req_q <= in_req_i;
         usb_reset_q <= usb_reset_i | usb_reset_q;
         if (usb_reset_q == 1'b1 && dfu_state_q == DFU_ST_appDETACH)
           dfu_state_q <= DFU_ST_dfuIDLE0;
         if (clk_gate) begin
            if (usb_reset_q) begin
               usb_reset_q <= 1'b0;
               dev_state_qq <= DEFAULT_STATE;
               if (dfu_state_q != DFU_ST_dfuIDLE0 && dfu_state_q != DFU_ST_appDETACH)
                 dfu_state_q <= DFU_ST_appIDLE;
            end else begin
               dev_state_qq <= dev_state_dd;
               dfu_state_q <= dfu_state_d;
            end
         end
      end
   end

   assign usb_en_o = (dev_state_qq == POWERED_STATE && usb_reset_q == 1'b0) ? 1'b0 : 1'b1;
   assign usb_detach_o = (dfu_state_q == DFU_ST_appDETACH) ? 1'b1 : 1'b0;
   assign rstn = rstn_i & ~usb_reset_i;

   always @(posedge clk_i or negedge rstn) begin
      if (~rstn) begin
         state_q <= ST_IDLE;
         byte_cnt_q <= 'd0;
         max_length_q <= 'd0;
         blocknum_q <= 16'd0;
         in_dir_q <= 1'b0;
         class_q <= 1'b0;
         vendor_q <= 1'b0;
         rec_q <= REC_DEVICE;
         req_q <= REQ_NONE;
         string_index_q <= 'd0;
         alternate_setting_q <= 'd0;
         dev_state_q <= DEFAULT_STATE;
         addr_q <= 7'd0;
         addr_qq <= 7'd0;
         in_endp_q <= 1'b0;
      end else begin
         if (clk_gate) begin
            state_q <= state_d;
            byte_cnt_q <= byte_cnt_d;
            max_length_q <= max_length_d;
            blocknum_q <= blocknum_d;
            in_dir_q <= in_dir_d;
            class_q <= class_d;
            vendor_q <= vendor_d;
            rec_q <= rec_d;
            req_q <= req_d;
            string_index_q <= string_index_d;
            alternate_setting_q <= alternate_setting_d;
            dev_state_q <= dev_state_d;
            addr_q <= addr_d;
            addr_qq <= addr_dd;
            in_endp_q <= in_endp_d;
         end
      end
   end

   reg dfu_fifo;

   assign dfu_blocknum_o = blocknum_q;
   assign dfu_fifo_o = dfu_fifo;
   assign dfu_upload_o = (dfu_state_q == DFU_ST_dfuUPLOAD_IDLE) ? 1'b1 : 1'b0;
   assign dfu_dnload_o = (dfu_state_q == DFU_ST_dfuDNBUSY || dfu_state_q == DFU_ST_dfuDNLOAD_SYNC || dfu_state_q == DFU_ST_dfuDNLOAD_IDLE) ? 1'b1 : 1'b0;
   assign dfu_clear_status_o = (dfu_state_q == DFU_ST_dfuIDLE) ? 1'b1 : 1'b0;

   reg string_done;
   integer i;

   always @(/*AS*/addr_q or addr_qq or alternate_setting_q
            or blocknum_q or byte_cnt_q or class_q or dev_state_q
            or dev_state_qq or dfu_busy_i or dfu_done_i or dfu_state_q
            or dfu_status_i or in_data_ack_i or in_dir_q or in_endp_q
            or in_req_q or max_length_q or out_data_i or out_err_i
            or out_valid_i or rec_q or req_q or setup_i or state_q
            or string_index_q or vendor_q) begin
      dfu_state_d = dfu_state_q;
      state_d = state_q;
      byte_cnt_d = 'd0;
      max_length_d = max_length_q;
      blocknum_d = blocknum_q;
      in_dir_d = in_dir_q;
      class_d = class_q;
      vendor_d = vendor_q;
      rec_d = rec_q;
      req_d = req_q;
      string_index_d = string_index_q;
      alternate_setting_d = alternate_setting_q;
      dev_state_d = dev_state_q;
      dev_state_dd = dev_state_qq;
      addr_d = addr_q;
      addr_dd = addr_qq;
      in_endp_d = in_endp_q;
      in_data = 8'd0;
      in_zlp = 1'b0;
      in_valid = 1'b0;
      in_toggle_reset = 1'b0;
      out_toggle_reset = 1'b0;
      dfu_fifo = 1'b0;
      string_done = 1'b0;

      if (out_err_i == 1'b1) begin
         if (state_q != ST_STALL)
           state_d = ST_IDLE;
      end else if (setup_i == 1'b1) begin
         state_d = ST_SETUP;
      end else begin
         case (state_q)
           ST_IDLE, ST_STALL : begin
           end
           ST_SETUP : begin
              if (out_valid_i == 1'b1) begin
                 byte_cnt_d = byte_cnt_q + 1;
                 case (byte_cnt_q)
                   'd0 : begin // bmRequestType
                      in_dir_d = out_data_i[7];
                      vendor_d = out_data_i[6];
                      class_d = out_data_i[5];
                      rec_d = out_data_i[1:0];
                      if (|out_data_i[4:2] != 1'b0 || out_data_i[1:0] == 2'b11)
                        req_d = REQ_UNSUPPORTED;
                      else
                        req_d = REQ_NONE;
                   end
                   'd1 : begin // bRequest
                      req_d = REQ_UNSUPPORTED;
                      if (req_q == REQ_NONE) begin
                         if (class_q == 1'b0 && vendor_q == 1'b0) begin
                            case (out_data_i)
                              STD_REQ_CLEAR_FEATURE : begin
                                 if (in_dir_q == 1'b0 && dev_state_qq != DEFAULT_STATE)
                                   req_d = REQ_CLEAR_FEATURE;
                              end
                              STD_REQ_GET_CONFIGURATION : begin
                                 if (in_dir_q == 1'b1 && rec_q == REC_DEVICE && dev_state_qq != DEFAULT_STATE)
                                   req_d = REQ_GET_CONFIGURATION;
                              end
                              STD_REQ_GET_DESCRIPTOR : begin
                                 if (in_dir_q == 1'b1 && rec_q == REC_DEVICE)
                                   req_d = REQ_GET_DESCRIPTOR;
                              end
                              STD_REQ_GET_INTERFACE : begin
                                 if (in_dir_q == 1'b1 && rec_q == REC_INTERFACE && dev_state_qq == CONFIGURED_STATE)
                                   req_d = REQ_GET_INTERFACE;
                              end
                              STD_REQ_GET_STATUS : begin
                                 if (in_dir_q == 1'b1 && dev_state_qq != DEFAULT_STATE)
                                   req_d = REQ_GET_STATUS;
                              end
                              STD_REQ_SET_ADDRESS : begin
                                 if (in_dir_q == 1'b0 && rec_q == REC_DEVICE)
                                   req_d = REQ_SET_ADDRESS;
                              end
                              STD_REQ_SET_CONFIGURATION : begin
                                 if (in_dir_q == 1'b0 && rec_q == REC_DEVICE && dev_state_qq != DEFAULT_STATE)
                                   req_d = REQ_SET_CONFIGURATION;
                              end
                              STD_REQ_SET_INTERFACE : begin
                                 if (in_dir_q == 1'b0 && rec_q == REC_INTERFACE && dev_state_qq == CONFIGURED_STATE)
                                   req_d = REQ_SET_INTERFACE;
                              end
                              default : begin
                              end
                            endcase
                         end else if (class_q == 1'b1 && vendor_q == 1'b0) begin
                            if (dev_state_qq == CONFIGURED_STATE) begin
                               if (dfu_state_q == DFU_ST_appIDLE) begin
                                  case (out_data_i)
                                    ACM_REQ_SET_LINE_CODING, ACM_REQ_GET_LINE_CODING,
                                    ACM_REQ_SET_CONTROL_LINE_STATE, ACM_REQ_SEND_BREAK : begin
                                       req_d = REQ_DUMMY;
                                    end
                                    DFU_REQ_DETACH : begin
                                       if (in_dir_q == 1'b0 && rec_q == REC_INTERFACE)
                                         req_d = REQ_DFU_DETACH;
                                    end
                                    default : begin
                                    end
                                  endcase
                               end else begin
                                  case (out_data_i)
                                    DFU_REQ_DNLOAD : begin
                                       if (in_dir_q == 1'b0 && rec_q == REC_INTERFACE)
                                         req_d = REQ_DFU_DNLOAD;
                                    end
                                    DFU_REQ_UPLOAD : begin
                                       if (in_dir_q == 1'b1 && rec_q == REC_INTERFACE)
                                         req_d = REQ_DFU_UPLOAD;
                                    end
                                    DFU_REQ_GETSTATUS : begin
                                       if (in_dir_q == 1'b1 && rec_q == REC_INTERFACE)
                                         req_d = REQ_DFU_GETSTATUS;
                                    end
                                    DFU_REQ_CLRSTATUS : begin
                                       if (in_dir_q == 1'b0 && rec_q == REC_INTERFACE)
                                         req_d = REQ_DFU_CLRSTATUS;
                                    end
                                    DFU_REQ_GETSTATE : begin
                                       if (in_dir_q == 1'b1 && rec_q == REC_INTERFACE)
                                         req_d = REQ_DFU_GETSTATE;
                                    end
                                    DFU_REQ_ABORT : begin
                                       if (in_dir_q == 1'b0 && rec_q == REC_INTERFACE)
                                         req_d = REQ_DFU_ABORT;
                                    end
                                    default : begin
                                    end
                                  endcase
                               end
                            end
                         end else if (class_q == 1'b0 && vendor_q == 1'b1) begin
                            if (out_data_i == VENDORCODE && in_dir_q == 1'b1) begin
                               if (dfu_state_q == DFU_ST_appIDLE && rec_q == REC_DEVICE && MS20 != 0)
                                 req_d = REQ_MS20;
                               else if (dfu_state_q != DFU_ST_appIDLE && (rec_q == REC_DEVICE || rec_q == REC_INTERFACE) &&
                                        WCID != 0)
                                 req_d = REQ_WCID;
                            end
                         end
                      end
                   end
                   'd2 : begin // wValue LSB
                      case (req_q)
                        REQ_CLEAR_FEATURE : begin // ENDPOINT_HALT
                           if (!(rec_q == REC_ENDPOINT && |out_data_i == 1'b0))
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_DESCRIPTOR : begin
                           if ((dfu_state_q == DFU_ST_appIDLE &&
                                (out_data_i == 8'h00 || out_data_i == 8'h01 || out_data_i == 8'h02)) ||
                               (dfu_state_q != DFU_ST_appIDLE &&
                                (out_data_i == 8'h00 || out_data_i == 8'h01 ||
                                 (out_data_i == 8'hEE && WCID != 0) || out_data_i < (FIRST_ALT_STRING[7:0]+ALT[7:0]))))
                             string_index_d = out_data_i;
                           else
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_INTERFACE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_STATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_ADDRESS : begin
                           if (out_data_i[7] == 1'b0)
                             addr_d = out_data_i[6:0];
                           else
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_CONFIGURATION : begin
                           if (out_data_i == 8'd0)
                             dev_state_d = ADDRESS_STATE;
                           else if (out_data_i == 8'd1)
                             dev_state_d = CONFIGURED_STATE;
                           else
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_INTERFACE : begin
                           if ((dfu_state_q == DFU_ST_appIDLE && |out_data_i == 1'b0) ||
                               (dfu_state_q != DFU_ST_appIDLE && out_data_i < ALT[7:0]))
                             alternate_setting_d = out_data_i[2:0];
                           else
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DETACH : begin
                        end
                        REQ_DFU_DNLOAD, REQ_DFU_UPLOAD : begin
                           blocknum_d[7:0] = out_data_i;
                        end
                        REQ_DFU_GETSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_CLRSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_GETSTATE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_ABORT : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_MS20 : begin
                           if (|out_data_i == 1'b1 && MS20 != 0)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_WCID : begin
                           if (|out_data_i == 1'b1 && WCID != 0)
                             req_d = REQ_UNSUPPORTED;
                        end
                        default : begin
                        end
                      endcase
                   end
                   'd3 : begin // wValue MSB
                      case (req_q)
                        REQ_CLEAR_FEATURE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_DESCRIPTOR : begin
                           if (out_data_i == 8'd1 && |string_index_q == 1'b0)
                             req_d = REQ_GET_DESCRIPTOR_DEVICE;
                           else if (out_data_i == 8'd2 && |string_index_q == 1'b0)
                             req_d = REQ_GET_DESCRIPTOR_CONFIGURATION;
                           else if (out_data_i == 8'd3)
                             req_d = REQ_GET_DESCRIPTOR_STRING;
                           else if (out_data_i == 8'd15 && |string_index_q == 1'b0)
                             req_d = REQ_GET_DESCRIPTOR_BOS;
                           else
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_INTERFACE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_STATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_ADDRESS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_INTERFACE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DETACH : begin
                        end
                        REQ_DFU_DNLOAD, REQ_DFU_UPLOAD : begin
                           blocknum_d[15:8] = out_data_i;
                        end
                        REQ_DFU_GETSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_CLRSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_GETSTATE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_ABORT : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_MS20 : begin
                           if (|out_data_i == 1'b1 && MS20 != 0)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_WCID : begin
                           if (|out_data_i == 1'b1 && WCID != 0)
                             req_d = REQ_UNSUPPORTED;
                        end
                        default : begin
                        end
                      endcase
                   end
                   'd4 : begin // wIndex LSB
                      in_endp_d = out_data_i[7];
                      case (req_q)
                        REQ_CLEAR_FEATURE : begin
                           if (!((rec_q == REC_ENDPOINT) &&
                                 (out_data_i == 8'h00 || out_data_i == 8'h80 ||
                                  out_data_i == 8'h01 || out_data_i == 8'h81 ||
                                  out_data_i == 8'h82)))
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_DESCRIPTOR_DEVICE, REQ_GET_DESCRIPTOR_CONFIGURATION, REQ_GET_DESCRIPTOR_BOS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_DESCRIPTOR_STRING : begin
                        end
                        REQ_GET_INTERFACE : begin
                           if (!((dfu_state_q == DFU_ST_appIDLE && out_data_i <= 8'd2) ||
                                 (dfu_state_q != DFU_ST_appIDLE && |out_data_i == 1'b0)))
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_STATUS : begin
                           if (!(((rec_q == REC_DEVICE) && (|out_data_i == 1'b0)) ||
                                 ((rec_q == REC_INTERFACE) && (|out_data_i[7:1] == 1'b0)) ||
                                 ((rec_q == REC_ENDPOINT) &&
                                  (out_data_i == 8'h00 || out_data_i == 8'h80 ||
                                   out_data_i == 8'h01 || out_data_i == 8'h81 ||
                                   out_data_i == 8'h82))))
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_ADDRESS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_INTERFACE : begin
                           if (!((dfu_state_q == DFU_ST_appIDLE && out_data_i <= 8'd2) ||
                                 (dfu_state_q != DFU_ST_appIDLE && |out_data_i == 1'b0)))
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DETACH : begin
                           if (out_data_i != 8'd2)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DNLOAD : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_UPLOAD : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_GETSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_CLRSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_GETSTATE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_ABORT : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_MS20 : begin
                           if (out_data_i != 8'h07 && MS20 != 0)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_WCID : begin
                           if (WCID != 0) begin
                              if (out_data_i == 8'h05 && rec_q == REC_INTERFACE)
                                req_d = REQ_EXT_WCID;
                              else if (out_data_i != 8'h04 || rec_q != REC_DEVICE)
                                req_d = REQ_UNSUPPORTED;
                           end
                        end
                        default : begin
                        end
                      endcase
                   end
                   'd5 : begin // wIndex MSB
                      case (req_q)
                        REQ_CLEAR_FEATURE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_DESCRIPTOR_DEVICE, REQ_GET_DESCRIPTOR_CONFIGURATION, REQ_GET_DESCRIPTOR_BOS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_DESCRIPTOR_STRING : begin
                        end
                        REQ_GET_INTERFACE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_STATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_ADDRESS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_INTERFACE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DETACH : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DNLOAD : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_UPLOAD : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_GETSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_CLRSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_GETSTATE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_ABORT : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_MS20 : begin
                           if (|out_data_i == 1'b1 && MS20 != 0)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_WCID : begin
                           if (|out_data_i == 1'b1 && WCID != 0)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_EXT_WCID : begin
                           if (|out_data_i == 1'b1 && WCID != 0)
                             req_d = REQ_UNSUPPORTED;
                        end
                        default : begin
                        end
                      endcase
                   end
                   'd6 : begin // wLength LSB
                      max_length_d[`min(BC_WIDTH-1, 7):0] = out_data_i[`min(BC_WIDTH-1, 7):0];
                      case (req_q)
                        REQ_CLEAR_FEATURE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_CONFIGURATION : begin
                           if (out_data_i != 8'd1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_DESCRIPTOR_DEVICE, REQ_GET_DESCRIPTOR_CONFIGURATION, REQ_GET_DESCRIPTOR_STRING, REQ_GET_DESCRIPTOR_BOS : begin
                           if (BC_WIDTH < 8 && |out_data_i[7:`min(BC_WIDTH, 7)] == 1'b1)
                             max_length_d = {BC_WIDTH{1'b1}};
                        end
                        REQ_GET_INTERFACE : begin
                           if (out_data_i != 8'd1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_STATUS : begin
                           if (out_data_i != 8'd2)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_ADDRESS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_INTERFACE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DETACH : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DNLOAD, REQ_DFU_UPLOAD : begin
                           if (BC_WIDTH < 8 && |out_data_i[7:`min(BC_WIDTH, 7)] == 1'b1)
                             max_length_d = {BC_WIDTH{1'b1}};
                        end
                        REQ_DFU_GETSTATUS : begin
                           if (out_data_i != 8'd6)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_CLRSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_GETSTATE : begin
                           if (out_data_i != 8'd1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_ABORT : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_MS20, REQ_WCID, REQ_EXT_WCID : begin
                           if (BC_WIDTH < 8 && |out_data_i[7:`min(BC_WIDTH, 7)] == 1'b1 && (MS20 != 0 || WCID != 0))
                             max_length_d = {BC_WIDTH{1'b1}};
                        end
                        default : begin
                        end
                      endcase
                   end
                   'd7 : begin // wLength MSB
                      if (BC_WIDTH > 8)
                        max_length_d[BC_WIDTH-1:`min(8, BC_WIDTH-1)] = out_data_i[BC_WIDTH-1-`min(8, BC_WIDTH-1):0];
                      case (req_q)
                        REQ_CLEAR_FEATURE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_DESCRIPTOR_DEVICE, REQ_GET_DESCRIPTOR_CONFIGURATION, REQ_GET_DESCRIPTOR_STRING, REQ_GET_DESCRIPTOR_BOS : begin
                           if (BC_WIDTH < 16 && |out_data_i[7:`min(`max(BC_WIDTH-8, 0), 7)] == 1'b1)
                             max_length_d = {BC_WIDTH{1'b1}};
                        end
                        REQ_GET_INTERFACE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_GET_STATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_ADDRESS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_CONFIGURATION : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_SET_INTERFACE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DETACH : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_DNLOAD, REQ_DFU_UPLOAD : begin
                           if (BC_WIDTH < 16 && |out_data_i[7:`min(`max(BC_WIDTH-8, 0), 7)] == 1'b1)
                             max_length_d = {BC_WIDTH{1'b1}};
                        end
                        REQ_DFU_GETSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_CLRSTATUS : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_GETSTATE : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_DFU_ABORT : begin
                           if (|out_data_i == 1'b1)
                             req_d = REQ_UNSUPPORTED;
                        end
                        REQ_MS20, REQ_WCID, REQ_EXT_WCID : begin
                           if (BC_WIDTH < 16 && |out_data_i[7:`min(`max(BC_WIDTH-8, 0), 7)] == 1'b1 && (MS20 != 0 || WCID != 0))
                             max_length_d = {BC_WIDTH{1'b1}};
                        end
                        default : begin
                        end
                      endcase
                   end
                   default : begin
                   end
                 endcase
              end else begin
                 if (byte_cnt_q == 'd8) begin
                    if (req_q == REQ_UNSUPPORTED)
                      state_d = ST_STALL;
                    else if (in_dir_q == 1'b1) begin
                       if (req_q == REQ_DFU_UPLOAD)
                         dfu_state_d = DFU_ST_dfuUPLOAD_IDLE;
                       else if (req_q == REQ_DFU_GETSTATUS) begin
                          if (dfu_status_i != 4'h0) begin
                             dfu_state_d = DFU_ST_dfuERROR;
                          end else if (dfu_state_q == DFU_ST_dfuDNLOAD_SYNC || dfu_state_q == DFU_ST_dfuDNBUSY) begin
                             if (dfu_busy_i)
                               dfu_state_d = DFU_ST_dfuDNBUSY;
                             else
                               dfu_state_d = DFU_ST_dfuDNLOAD_IDLE;
                          end else if (dfu_state_q == DFU_ST_dfuMANIFEST_SYNC || dfu_state_q == DFU_ST_dfuMANIFEST) begin
                             if (dfu_done_i)
                               dfu_state_d = DFU_ST_dfuIDLE;
                             else
                               dfu_state_d = DFU_ST_dfuMANIFEST;
                          end
                       end else if (req_q == REQ_DFU_GETSTATE) begin
                          if (dfu_status_i != 4'h0)
                            dfu_state_d = DFU_ST_dfuERROR;
                          else if (dfu_state_q == DFU_ST_dfuDNBUSY)
                            dfu_state_d = DFU_ST_dfuDNLOAD_SYNC;
                          else if (dfu_state_q == DFU_ST_dfuMANIFEST)
                            dfu_state_d = DFU_ST_dfuMANIFEST_SYNC;
                       end
                       state_d = ST_DATA;
                    end else begin
                       if (max_length_q == 'd0) begin // No-data Control STATUS stage
                          byte_cnt_d = byte_cnt_q;
                          in_zlp = 1'b1;
                          in_valid = 1'b1;
                          if (in_data_ack_i) begin
                             state_d = ST_IDLE;
                             case (req_q)
                               REQ_SET_ADDRESS : begin
                                  addr_dd = addr_q;
                                  if (addr_q == 7'd0)
                                    dev_state_dd = DEFAULT_STATE;
                                  else
                                    dev_state_dd = ADDRESS_STATE;
                               end
                               REQ_CLEAR_FEATURE : begin
                                  if (in_endp_q == 1'b1)
                                    in_toggle_reset = 1'b1;
                                  else
                                    out_toggle_reset = 1'b1;
                               end
                               REQ_SET_CONFIGURATION : begin
                                  dev_state_dd = dev_state_q;
                                  alternate_setting_d = 'd0;
                                  in_toggle_reset = 1'b1;
                                  out_toggle_reset = 1'b1;
                                  if (dfu_state_q == DFU_ST_dfuIDLE0)
                                    dfu_state_d = DFU_ST_dfuIDLE;
                               end
                               REQ_DFU_DETACH : begin
                                  dfu_state_d = DFU_ST_appDETACH;
                               end
                               REQ_DFU_ABORT : begin
                                  if (dfu_state_q == DFU_ST_dfuDNLOAD_SYNC ||
                                      dfu_state_q == DFU_ST_dfuDNLOAD_IDLE ||
                                      dfu_state_q == DFU_ST_dfuMANIFEST_SYNC ||
                                      dfu_state_q == DFU_ST_dfuUPLOAD_IDLE)
                                    dfu_state_d = DFU_ST_dfuIDLE;
                               end
                               REQ_DFU_CLRSTATUS : begin
                                  if (dfu_state_q == DFU_ST_dfuERROR)
                                    dfu_state_d = DFU_ST_dfuIDLE;
                               end
                               REQ_DFU_DNLOAD : begin
                                  if (dfu_status_i != 4'h0 || dfu_state_q != DFU_ST_dfuDNLOAD_IDLE) begin
                                     state_d = ST_STALL;
                                     dfu_state_d = DFU_ST_dfuERROR;
                                  end else
                                    dfu_state_d = DFU_ST_dfuMANIFEST_SYNC;
                               end
                               default : begin
                               end
                             endcase
                          end
                       end else begin
                          state_d = ST_DATA;
                          if (req_q == REQ_DFU_DNLOAD) begin
                             if (dfu_status_i != 4'h0 ||
                                 !(dfu_state_q == DFU_ST_dfuIDLE || dfu_state_q == DFU_ST_dfuDNLOAD_IDLE)) begin
                                state_d = ST_STALL;
                                dfu_state_d = DFU_ST_dfuERROR;
                             end else
                               dfu_state_d = DFU_ST_dfuDNLOAD_SYNC;
                          end
                       end
                    end
                 end else
                   state_d = ST_STALL;
              end
           end
           ST_DATA : begin
              byte_cnt_d = byte_cnt_q;
              if (in_dir_q == 1'b1) begin
                 if (out_valid_i == 1'b1) begin
                    state_d = ST_STALL;
                 end else begin
                    case (req_q)
                      REQ_DFU_UPLOAD : begin
                         if (dfu_done_i == 1'b1 && byte_cnt_q == 'h00) begin
                            in_zlp = 1'b1;
                            in_valid = 1'b1;
                         end else
                           dfu_fifo = 1'b1;
                      end
                      default : begin
                      end
                    endcase
                    for (i = 0; i < ALT; i = i + 1) begin
                       if (byte_cnt_q == STRING_DESCR_LENGTHS[i*32 +:BC_WIDTH] && req_q == REQ_GET_DESCRIPTOR_STRING && string_index_q == (i[7:0]+FIRST_ALT_STRING[7:0]))
                         string_done = 1'b1;
                    end
                    if (byte_cnt_q == max_length_q ||
                        (byte_cnt_q == 'h12 && req_q == REQ_GET_DESCRIPTOR_DEVICE && dfu_state_q == DFU_ST_appIDLE) ||
                        (byte_cnt_q == 'h12 && req_q == REQ_GET_DESCRIPTOR_DEVICE && dfu_state_q != DFU_ST_appIDLE) ||
                        (byte_cnt_q == CDL[BC_WIDTH-1:0] && req_q == REQ_GET_DESCRIPTOR_CONFIGURATION && dfu_state_q == DFU_ST_appIDLE) ||
                        (byte_cnt_q == DCDL[BC_WIDTH-1:0] && req_q == REQ_GET_DESCRIPTOR_CONFIGURATION && dfu_state_q != DFU_ST_appIDLE) ||
                        (byte_cnt_q == 'h21 && req_q == REQ_GET_DESCRIPTOR_BOS && dfu_state_q == DFU_ST_appIDLE && MS20 != 0) ||
                        (byte_cnt_q == 'h04 && req_q == REQ_GET_DESCRIPTOR_STRING && string_index_q == 'h00) ||
                        (byte_cnt_q == STR01L[BC_WIDTH-1:0] && req_q == REQ_GET_DESCRIPTOR_STRING && string_index_q == 'h01) ||
                        (byte_cnt_q == STR02L[BC_WIDTH-1:0] && req_q == REQ_GET_DESCRIPTOR_STRING && string_index_q == 'h02) ||
                        (byte_cnt_q == 'h12 && req_q == REQ_GET_DESCRIPTOR_STRING && string_index_q == 'hEE && WCID != 0) ||
                        (string_done == 1'b1) ||
                        (byte_cnt_q == MS20L[BC_WIDTH-1:0] && req_q == REQ_MS20 && dfu_state_q == DFU_ST_appIDLE && MS20 != 0) ||
                        (byte_cnt_q == 'h28 && req_q == REQ_WCID && dfu_state_q != DFU_ST_appIDLE && WCID != 0) ||
                        (byte_cnt_q == 'h8e && req_q == REQ_EXT_WCID && dfu_state_q != DFU_ST_appIDLE && WCID != 0) ||
                        (dfu_done_i == 1'b1 && req_q == REQ_DFU_UPLOAD)) begin
                       if (in_req_q == 1'b0) begin
                          if (~in_data_ack_i) begin // Control Read STATUS stage
                             case (req_q)
                               REQ_DFU_UPLOAD : begin
                                  if (byte_cnt_q != max_length_q)
                                    dfu_state_d = DFU_ST_dfuIDLE;
                               end
                               default : begin
                               end
                             endcase
                             state_d = ST_IDLE;
                          end
                       end else
                         state_d = ST_STALL;
                    end else begin
                       if (in_req_q == 1'b1)
                         byte_cnt_d = byte_cnt_q + 1;
                       case (req_q)
                         REQ_GET_CONFIGURATION : begin
                            if (dev_state_qq == ADDRESS_STATE) begin
                               in_data = 8'd0;
                               in_valid = 1'b1;
                            end else if (dev_state_qq == CONFIGURED_STATE) begin
                               in_data = 8'd1;
                               in_valid = 1'b1;
                            end
                         end
                         REQ_GET_DESCRIPTOR_DEVICE : begin
                            if (dfu_state_q == DFU_ST_appIDLE)
                              in_data = DEV_DESCR[8*byte_cnt_q +:8];
                            else
                              in_data = DFU_DEV_DESCR[8*byte_cnt_q +:8];
                            in_valid = 1'b1;
                         end
                         REQ_GET_DESCRIPTOR_CONFIGURATION : begin
                            if (dfu_state_q == DFU_ST_appIDLE)
                              in_data = CONF_DESCR[8*byte_cnt_q +:8];
                            else
                              in_data = DFU_CONF_DESCR[8*byte_cnt_q +:8];
                            in_valid = 1'b1;
                         end
                         REQ_GET_DESCRIPTOR_STRING : begin
                            case (string_index_q)
                              'hEE : begin
                                 if (WCID != 0) begin
                                    in_data = STRING_DESCR_EE[8*byte_cnt_q +:8];
                                    in_valid = 1'b1;
                                 end
                              end
                              'h02 : begin
                                 in_data = STRING_DESCR_02[8*byte_cnt_q +:8];
                                 in_valid = 1'b1;
                              end
                              'h01 : begin
                                 in_data = STRING_DESCR_01[8*byte_cnt_q +:8];
                                 in_valid = 1'b1;
                              end
                              'h00 : begin
                                 in_data = STRING_DESCR_00[8*byte_cnt_q +:8];
                                 in_valid = 1'b1;
                              end
                              default : begin
                                 for (i = 0; i < ALT; i = i + 1) begin
                                    if (string_index_q == (i[7:0]+FIRST_ALT_STRING[7:0]))
                                      in_data = STRING_DESCRS[i*8*128+8*byte_cnt_q +:8];
                                 end
                                 in_valid = 1'b1;
                              end
                            endcase
                         end
                         REQ_GET_DESCRIPTOR_BOS : begin
                            if (dfu_state_q == DFU_ST_appIDLE && MS20 != 0) begin
                               in_data = BOS_DESCR[8*byte_cnt_q +:8];
                               in_valid = 1'b1;
                            end
                         end
                         REQ_GET_INTERFACE : begin
                            in_data = {5'd0, alternate_setting_q};
                            in_valid = 1'b1;
                         end
                         REQ_GET_STATUS : begin
                            in_data = 8'd0;
                            in_valid = 1'b1;
                         end
                         REQ_DFU_UPLOAD : begin
                         end
                         REQ_DFU_GETSTATUS : begin
                            case (byte_cnt_q)
                              'd0 : in_data = {4'd0, ((|dfu_status_i) ?
                                                      dfu_status_i :
                                                      ((dfu_state_q == DFU_ST_dfuERROR) ? 4'hF : 4'h0))}; // bStatus
                              'd1 : in_data = (dfu_busy_i) ? POLLTIMEOUT[7:0] : 8'd1; // bwPollTimeout[0] (ms)
                              'd2 : in_data = (dfu_busy_i) ? POLLTIMEOUT[15:8] : 8'd0; // bwPollTimeout[1]
                              'd3 : in_data = (dfu_busy_i) ? POLLTIMEOUT[23:16] : 8'd0; // bwPollTimeout[2]
                              'd4 : in_data = {4'd0, dfu_state_q}; // bState
                              'd5 : in_data = 8'd0; // iString (none)
                              default : in_data = 8'd0;
                            endcase
                            in_valid = 1'b1;
                         end
                         REQ_DFU_GETSTATE : begin
                            in_data = {4'd0, dfu_state_q};
                            in_valid = 1'b1;
                         end
                         REQ_MS20 : begin
                            if (dfu_state_q == DFU_ST_appIDLE && MS20 != 0) begin
                               in_data = MS20_DESCR[8*byte_cnt_q +:8];
                               in_valid = 1'b1;
                            end
                         end
                         REQ_WCID : begin
                            if (dfu_state_q != DFU_ST_appIDLE && WCID != 0) begin
                               in_data = WCID_DESCR[8*byte_cnt_q +:8];
                               in_valid = 1'b1;
                            end
                         end
                         REQ_EXT_WCID : begin
                            if (dfu_state_q != DFU_ST_appIDLE && WCID != 0) begin
                               in_data = EXT_WCID_DESCR[8*byte_cnt_q +:8];
                               in_valid = 1'b1;
                            end
                         end
                         default : begin
                            in_data = 8'd0;
                            in_valid = 1'b1;
                         end
                       endcase
                    end
                 end
              end else begin
                 in_zlp = 1'b1;
                 in_valid = 1'b1;
                 if (req_q == REQ_DFU_DNLOAD) begin
                    dfu_fifo = 1'b1;
                 end
                 if (in_req_q == 1'b1)
                   state_d = ST_STALL;
                 else if (out_valid_i == 1'b1) begin
                 end else begin
                    if (in_data_ack_i) begin // Control Write STATUS stage
                       state_d = ST_IDLE;
                       case (req_q)
                         REQ_DFU_DNLOAD : begin
                            if (dfu_status_i != 4'h0) begin
                               state_d = ST_STALL;
                               dfu_state_d = DFU_ST_dfuERROR;
                            end
                         end
                         default : begin
                         end
                       endcase
                    end
                 end
              end
           end
           default : begin
              state_d = ST_IDLE;
           end
         endcase
      end
   end
endmodule
