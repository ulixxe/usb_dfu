
localparam [15:0] TRANSFER_SIZE = 256;
localparam [15:0] DETACH_TIMEOUT = 1000;
localparam ALT = 4;

localparam FIRST_ALT_STRING = 'd3; // First Alternate Setting String
// DFU Mode Configuration Descriptor (in reverse order)
localparam              DCDL = 'h9+'h9*ALT+'h9; // DFU_CONF_DESCR Length
localparam [8*DCDL-1:0] DFU_CONF_DESCR = {
                                          // Standard Configuration Descriptor, USB1.0
                                          8'h09, // bLength
                                          8'h02, // bDescriptorType (CONFIGURATION)
                                          DCDL[7:0], // wTotalLength[0]
                                          DCDL[15:8], // wTotalLength[1]
                                          8'h01, // bNumInterfaces
                                          8'h01, // bConfigurationValue
                                          8'h00, // iConfiguration (no string)
                                          8'h80, // bmAttributes (bus powered, no remote wakeup)
                                          8'h32, // bMaxPower (100mA)

                                          // DFU Interface Descriptor, DFU1.1 4.2.3, page 15-16, Table 4-4
                                          8'h09, // bLength
                                          8'h04, // bDescriptorType (INTERFACE)
                                          8'h00, // bInterfaceNumber
                                          8'h00, // bAlternateSetting
                                          8'h00, // bNumEndpoints
                                          8'hFE, // bInterfaceClass (Application Specific)
                                          8'h01, // bInterfaceSubClass (Device Firmware Upgrade)
                                          8'h02, // bInterfaceProtocol (DFU Mode)
                                          8'h00+FIRST_ALT_STRING[7:0], // iInterface

                                          // DFU Interface Descriptor, DFU1.1 4.2.3, page 15-16, Table 4-4
                                          8'h09, // bLength
                                          8'h04, // bDescriptorType (INTERFACE)
                                          8'h00, // bInterfaceNumber
                                          8'h01, // bAlternateSetting
                                          8'h00, // bNumEndpoints
                                          8'hFE, // bInterfaceClass (Application Specific)
                                          8'h01, // bInterfaceSubClass (Device Firmware Upgrade)
                                          8'h02, // bInterfaceProtocol (DFU Mode)
                                          8'h01+FIRST_ALT_STRING[7:0], // iInterface

                                          // DFU Interface Descriptor, DFU1.1 4.2.3, page 15-16, Table 4-4
                                          8'h09, // bLength
                                          8'h04, // bDescriptorType (INTERFACE)
                                          8'h00, // bInterfaceNumber
                                          8'h02, // bAlternateSetting
                                          8'h00, // bNumEndpoints
                                          8'hFE, // bInterfaceClass (Application Specific)
                                          8'h01, // bInterfaceSubClass (Device Firmware Upgrade)
                                          8'h02, // bInterfaceProtocol (DFU Mode)
                                          8'h02+FIRST_ALT_STRING[7:0], // iInterface

                                          // DFU Interface Descriptor, DFU1.1 4.2.3, page 15-16, Table 4-4
                                          8'h09, // bLength
                                          8'h04, // bDescriptorType (INTERFACE)
                                          8'h00, // bInterfaceNumber
                                          8'h03, // bAlternateSetting
                                          8'h00, // bNumEndpoints
                                          8'hFE, // bInterfaceClass (Application Specific)
                                          8'h01, // bInterfaceSubClass (Device Firmware Upgrade)
                                          8'h02, // bInterfaceProtocol (DFU Mode)
                                          8'h03+FIRST_ALT_STRING[7:0], // iInterface

                                          // DFU Functional Descriptor, DFU1.1 4.1.3, page 13-14, Table 4-2
                                          8'h09, // bLength
                                          8'h21, // bDescriptorType (DFU FUNCTIONAL)
                                          8'h0F, // bmAttributes (bitWillDetach, bitManifestationTolerant, bitCanUpload, bitCanDnload)
                                          DETACH_TIMEOUT[7:0], // wDetachTimeOut[0]
                                          DETACH_TIMEOUT[15:8], // wDetachTimeOut[1]
                                          TRANSFER_SIZE[7:0], // wTransferSize[0]
                                          TRANSFER_SIZE[15:8], // wTransferSize[1]
                                          8'h10, // bcdDFUVersion[0]
                                          8'h01 // bcdDFUVersion[1] (1.10)
                                          };

// String Descriptor
localparam              STR01L = 2*3+2; // STRING_DESCR_01 Length
localparam [8*STR01L-1:0]  STRING_DESCR_01 = {
                                           // UNICODE String Descriptor, USB2.0 9.6.7, page 273-274, Table 9-16
                                           STR01L[7:0], // bLength
                                           8'h03, // bDescriptorType (STRING)
                                           "I", // wString[0]
                                           8'h00, // wString[1]
                                           "D", // wString[0]
                                           8'h00, // wString[1]
                                           "0", // wString[0]
                                           8'h00 // wString[1]
                                           };

// String Descriptor
localparam              STR02L = 2*2+2; // STRING_DESCR_02 Length
localparam [8*STR02L-1:0]  STRING_DESCR_03 = {
                                           // UNICODE String Descriptor, USB2.0 9.6.7, page 273-274, Table 9-16
                                           STR02L[7:0], // bLength
                                           8'h03, // bDescriptorType (STRING)
                                           "A", // wString[0]
                                           8'h00, // wString[1]
                                           "0", // wString[0]
                                           8'h00 // wString[1]
                                           };

