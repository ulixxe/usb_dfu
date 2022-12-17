`timescale 1 ns/10 ps  // time-unit/precision
`define BIT_TIME (1000/12)
`define CLK_PER (1000/16)

module tb_bootloader ( );
`define USB_DFU_INST tb_bootloader.u_bootloader.u_usb_dfu

   localparam MAX_BITS = 128;
   localparam MAX_BYTES = 128;
   localparam MAX_STRING = 128;

   function automatic [8*MAX_BYTES-1:0] rand_vect;
      input integer seed;
      integer       seed_var, i;
      begin
         for (i = 0; i < MAX_BYTES; i = i + 1) begin
            rand_vect[8*i +:8] = $dist_uniform(seed_var, 0, 255);
         end
      end
   endfunction

   reg        dp_force;
   reg        dn_force;
   reg        power_on;
   reg [8*MAX_STRING-1:0] test;
   reg [8*MAX_BYTES-1:0]  random;

   wire                   dp_sense;
   wire                   dn_sense;

   integer                errors;
   integer                warnings;

   localparam             IN_BULK_MAXPACKETSIZE = 'd8;
   localparam             OUT_BULK_MAXPACKETSIZE = 'd8;
   localparam             VENDORID = 16'h1D50;
   localparam             PRODUCTID = 16'h6130;
   localparam [15:0]      DFU_PRODUCTID = 16'hFFFF;
   localparam [7:0]       VENDORCODE = 8'h77;

`include "bootloader_defs.v"
`include "usb_tasks.v"
`include "bootloader_tasks.v"

   `progress_bar(181)

   reg                    clk;

   initial begin
      clk = 0;
   end

   always @(clk or power_on) begin
      if (power_on | clk)
        #(`CLK_PER/2) clk <= ~clk;
   end

   wire led;
   wire usb_p;
   wire usb_n;
   wire usb_pu;

   bootloader u_bootloader (.clk(clk),
                            .led(led),
                            .usb_p(usb_p),
                            .usb_n(usb_n),
                            .usb_pu(usb_pu),
                            .sck(sck),
                            .ss(csn),
                            .sdo(mosi),
                            .sdi(miso));

   localparam MEM_PATH = "../../common/hdl/flash/";

   wire       hold_n;
   wire       wp_n;

   assign hold_n = 1'b1;
   assign wp_n = 1'b1;

   AT25SF081 #(.CELL_DATA({MEM_PATH, "init_cell_data.hex"}),
               .CELL_DATA_SEC({MEM_PATH, "init_cell_data_sec.hex"}))
   u_flash (.SCLK(sck),
            .CS_N(csn),
            .SI(mosi),
            .HOLD_N(hold_n),
            .WP_N(wp_n),
            .SO(miso));

   assign usb_p = dp_force;
   assign usb_n = dn_force;

   assign (pull1, highz0) usb_p = usb_pu; // 1.5kOhm device pull-up resistor
   //pullup (usb_p); // to speedup simulation don't wait for usb_pu

   //pulldown (weak0) dp_pd (usb_p), dn_pd (usb_n); // 15kOhm host pull-down resistors
   assign (highz1, weak0) usb_p = 1'b0; // to bypass verilator error on above pulldown
   assign (highz1, weak0) usb_n = 1'b0; // to bypass verilator error on above pulldown

   assign dp_sense = usb_p;
   assign dn_sense = usb_n;

   usb_monitor #(.MAX_BITS(MAX_BITS),
                 .MAX_BYTES(MAX_BYTES))
   u_usb_monitor (.usb_dp_i(dp_sense),
                  .usb_dn_i(dn_sense));

   reg [6:0]  address;
   reg [15:0] datain_toggle;
   reg [15:0] dataout_toggle;
   reg [8*MAX_BYTES-1:0] data;
   reg [7:0]             flash_init_data[0:1024*1024-1];
   integer               i;

   initial begin : u_host
      $readmemh({MEM_PATH, "init_cell_data.hex"}, flash_init_data);
      $timeformat(-6, 3, "us", 3);
      $dumpfile("tb.dump");
      $dumpvars;

      power_on = 1'b1;
      dp_force = 1'bZ;
      dn_force = 1'bZ;
      errors = 0;
      warnings = 0;
      address = 'd0;
      dataout_toggle = 'd0;
      datain_toggle = 'd0;
      wait_idle(20000000/83*`BIT_TIME);
      #(100000/83*`BIT_TIME);

      test_usb(address, datain_toggle, dataout_toggle);

      test = "TRASH DATA";
      test_data_out(address, ENDP_BULK,
                    {8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08},
                    7, PID_ACK, OUT_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, dataout_toggle);

      test = "NOP";
      test_data_out(address, ENDP_BULK,
                    {8'h01, 8'h00, 8'h00, 8'h00, 8'h00},
                    5, PID_ACK, OUT_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, dataout_toggle);

      test = "WAKE";
      test_cmd(8'hAB, 'd0, 'd0,
               address, OUT_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, dataout_toggle);
      #(20000/83*`BIT_TIME); // wait 20us

      test = "READ ID (1/2)";
      test_cmd(8'h9F, 'd0, 'd3,
               address, OUT_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, dataout_toggle);

      test = "READ ID (2/2)";
      test_data_in(address, ENDP_BULK,
                   {8'h1F, 8'h85, 8'h01},
                   3, PID_ACK, IN_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, datain_toggle, ZLP);

      test = "READ @addr=0";
      for (i = 0; i<8; i = i+1)
        data[8*(8-i-1) +:8] = flash_init_data[24'd0+i];
      test_read('d0,
                data,
                8, address, IN_BULK_MAXPACKETSIZE, OUT_BULK_MAXPACKETSIZE,
                100000/83*`BIT_TIME, datain_toggle, dataout_toggle);

      test = "READ @addr=1000";
      for (i = 0; i<8; i = i+1)
        data[8*(8-i-1) +:8] = flash_init_data[24'd1000+i];
      test_read('d1000,
                data,
                8, address, IN_BULK_MAXPACKETSIZE, OUT_BULK_MAXPACKETSIZE,
                100000/83*`BIT_TIME, datain_toggle, dataout_toggle);

      test = "DFU_DETACH";
      test_setup_out(address, 8'h21, DFU_REQ_DETACH, DETACH_TIMEOUT, 16'h0002, 16'h0000,
                     8'd0, 0, PID_ACK);

      #(20000000/83*`BIT_TIME); // TSIGATT=16ms < 100ms (USB2.0 Tab.7-14 pag.188)
      address = 'd0;

      test = "SET_ADDRESS";
      test_set_address('d6, address);

      test = "SET_CONFIGURATION";
      test_set_configuration(address);

      test = "SET_INTERFACE alt=0";
      test_setup_out(address, 8'h01, STD_REQ_SET_INTERFACE, 16'h0000, 16'h0000, 16'h0000,
                     8'd0, 0, PID_ACK);

      test = "DFU_UPLOAD alt=0";
      for (i = 0; i<32; i = i+1)
        data[8*(32-i-1) +:8] = flash_init_data[24'h28000+i];
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    data,
                    'd32, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuUPLOAD_IDLE, 'd1, PID_ACK);

      test = "DFU_ABORT";
      test_setup_out(address, 8'h21, DFU_REQ_ABORT, 16'h0000, 16'h0000, 16'h0000,
                     8'd0, 'd0, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuIDLE, 'd1, PID_ACK);

      test = "DFU_DNLOAD alt=0";
      random = rand_vect(2022);
      test_setup_out(address, 8'h21, DFU_REQ_DNLOAD, 16'h0000, 16'h0000, 16'd32,
                     random[8*32-1:0], 'd32, PID_ACK);

      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd10, 8'd0, 8'd0, DFU_ST_dfuDNBUSY, 8'd0}, 'd6, PID_ACK);

      #(100000000/83*`BIT_TIME); // wait 100ms

      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd1, 8'd0, 8'd0, DFU_ST_dfuDNLOAD_IDLE, 8'd0}, 'd6, PID_ACK);

      test = "DFU_DNLOAD alt=0";
      test_setup_out(address, 8'h21, DFU_REQ_DNLOAD, 16'h0000, 16'h0000, 16'd0,
                     {8'h00}, 'd0, PID_ACK);

      #(2000000/83*`BIT_TIME); // wait 2ms

      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd1, 8'd0, 8'd0, DFU_ST_dfuIDLE, 8'd0}, 'd6, PID_ACK);

      test = "DFU_UPLOAD alt=0";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    random[8*32-1:0], 'd32, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuUPLOAD_IDLE, 'd1, PID_ACK);

      test = "DFU_ABORT";
      test_setup_out(address, 8'h21, DFU_REQ_ABORT, 16'h0000, 16'h0000, 16'h0000,
                     8'd0, 'd0, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuIDLE, 'd1, PID_ACK);

      test = "SET_INTERFACE alt=1";
      test_setup_out(address, 8'h01, STD_REQ_SET_INTERFACE, 16'h0001, 16'h0000, 16'h0000,
                     8'd0, 0, PID_ACK);

      test = "DFU_UPLOAD alt=1";
      for (i = 0; i<32; i = i+1)
        data[8*(32-i-1) +:8] = flash_init_data[24'h0+i];
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    data,
                    'd32, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuUPLOAD_IDLE, 'd1, PID_ACK);

      test = "DFU_ABORT";
      test_setup_out(address, 8'h21, DFU_REQ_ABORT, 16'h0000, 16'h0000, 16'h0000,
                     8'd0, 'd0, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuIDLE, 'd1, PID_ACK);

      test = "SET_INTERFACE alt=2";
      test_setup_out(address, 8'h01, STD_REQ_SET_INTERFACE, 16'h0002, 16'h0000, 16'h0000,
                     8'd0, 0, PID_ACK);

      test = "Boot user image. DFU_UPLOAD alt=2";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd1,
                    {8'h00},
                    'd1, PID_NAK);


      test = "Test END";
      #(100*`BIT_TIME);
      `report_end("All tests correctly executed!")
   end
endmodule
