`timescale 1 ns/10 ps  // time-unit/precision
`define BIT_TIME (1000/12)
`define CLK_PER (1000/16)

module tb_loopback ( );
`define USB_DFU_INST tb_loopback.u_loopback.u_usb_dfu

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
   localparam             PRODUCTID = 16'h6131;
   localparam [15:0]      DFU_PRODUCTID = 16'hFFFF;
   localparam [7:0]       VENDORCODE = 8'h77;

`include "loopback_defs.v"
`include "usb_tasks.v"

   `progress_bar(182)

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

   loopback u_loopback (.clk(clk),
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

      test = "OUT BULK DATA";
      test_data_out(address, ENDP_BULK,
                    {8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07},
                    7, PID_ACK, OUT_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, dataout_toggle);

      test = "IN BULK DATA";
      test_data_in(address, ENDP_BULK,
                   {8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07},
                   7, PID_ACK, IN_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, datain_toggle, ZLP);

      test = "IN BULK DATA with NAK";
      test_data_in(address, ENDP_BULK,
                   {8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07},
                   7, PID_NAK, IN_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, datain_toggle, ZLP);

      test = "OUT BULK DATA";
      test_data_out(address, ENDP_BULK,
                    {8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17, 8'h18},
                    8, PID_ACK, OUT_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, dataout_toggle);

      test = "IN BULK DATA with ZLP";
      test_data_in(address, ENDP_BULK,
                   {8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17, 8'h18},
                   8, PID_ACK, IN_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, datain_toggle, ZLP);

      test = "OUT BULK DATA";
      test_data_out(address, ENDP_BULK,
                    {8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27, 8'h28,
                     8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37, 8'h38},
                    16, PID_ACK, OUT_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, dataout_toggle);

      test = "IN BULK DATA with ZLP";
      test_data_in(address, ENDP_BULK,
                   {8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27, 8'h28,
                    8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37, 8'h38},
                   16, PID_ACK, IN_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, datain_toggle, ZLP);

      test = "OUT BULK DATA";
      test_data_out(address, ENDP_BULK,
                    {8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47, 8'h48,
                     8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57, 8'h58,
                     8'h61, 8'h62, 8'h63},
                    19, PID_NAK, OUT_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, dataout_toggle);

      test = "IN BULK DATA with ZLP";
      test_data_in(address, ENDP_BULK,
                   {8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47, 8'h48,
                    8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57, 8'h58},
                   16, PID_ACK, IN_BULK_MAXPACKETSIZE, 100000/83*`BIT_TIME, 0, datain_toggle, ZLP);

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
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd64,
                    {8'h96, 8'h5F, 8'h98, 8'h47, 8'hB4, 8'hA3, 8'hBA, 8'hAA,
                     8'h19, 8'h0B, 8'h4F, 8'hB0, 8'hB1, 8'h19, 8'h4C},
                    'd15, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuIDLE, 'd1, PID_ACK);

      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd1, 8'd0, 8'd0, DFU_ST_dfuIDLE, 8'd0}, 'd6, PID_ACK);

      test = "DFU_CLRSTATUS";
      test_setup_out(address, 8'h21, DFU_REQ_CLRSTATUS, 16'h0000, 16'h0000, 16'h0000,
                     8'd0, 'd0, PID_ACK);

      test = "DFU_ABORT";
      test_setup_out(address, 8'h21, DFU_REQ_ABORT, 16'h0000, 16'h0000, 16'h0000,
                     8'd0, 'd0, PID_ACK);

      test = "SET_INTERFACE alt=1";
      test_setup_out(address, 8'h01, STD_REQ_SET_INTERFACE, 16'h0001, 16'h0000, 16'h0000,
                     8'd0, 0, PID_ACK);

      test = "DFU_UPLOAD alt=1 (1/3)";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    {8'h96, 8'h5F, 8'h98, 8'h47, 8'hB4, 8'hA3, 8'hBA, 8'hAA,
                     8'h19, 8'h0B, 8'h4F, 8'hB0, 8'hB1, 8'h19, 8'h4C, 8'h54,
                     8'hF7, 8'hCE, 8'hE8, 8'h53, 8'h46, 8'h82, 8'hE2, 8'h39,
                     8'h72, 8'hA4, 8'hD1, 8'h7E, 8'h73, 8'h49, 8'h0A, 8'h44},
                    'd32, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuUPLOAD_IDLE, 'd1, PID_ACK);

      test = "DFU_UPLOAD alt=1 (2/3)";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    {8'hF7, 8'h27, 8'hD7, 8'h2D, 8'hD7, 8'h29, 8'hD0, 8'hCD,
                     8'h10, 8'h5D, 8'h03, 8'h7E, 8'h20, 8'h21, 8'hA9, 8'h30,
                     8'h04, 8'hBD, 8'h9F, 8'h53, 8'hBC, 8'h8B, 8'hDF, 8'h22,
                     8'h57, 8'h01, 8'h83, 8'h59, 8'h65, 8'hF2, 8'h06, 8'hDB},
                    'd32, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuUPLOAD_IDLE, 'd1, PID_ACK);

      test = "DFU_UPLOAD alt=1 (3/3)";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    8'd0, 0, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuIDLE, 'd1, PID_ACK);

      test = "SET_INTERFACE alt=2";
      test_setup_out(address, 8'h01, STD_REQ_SET_INTERFACE, 16'h0002, 16'h0000, 16'h0000,
                     8'd0, 0, PID_ACK);

      test = "DFU_UPLOAD alt=2 (1/3)";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    {8'h96, 8'h5F, 8'h98, 8'h47, 8'hB4, 8'hA3, 8'hBA, 8'hAA,
                     8'h19, 8'h0B, 8'h4F, 8'hB0, 8'hB1, 8'h19, 8'h4C, 8'h54,
                     8'hF7, 8'hCE, 8'hE8, 8'h53, 8'h46, 8'h82, 8'hE2, 8'h39,
                     8'h72, 8'hA4, 8'hD1, 8'h7E, 8'h73, 8'h49, 8'h0A, 8'h44},
                    'd32, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuUPLOAD_IDLE, 'd1, PID_ACK);

      test = "DFU_UPLOAD alt=2 (2/3)";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    {8'hF7, 8'h27, 8'hD7, 8'h2D, 8'hD7, 8'h29, 8'hD0, 8'hCD,
                     8'h10, 8'h5D, 8'h03, 8'h7E, 8'h20, 8'h21, 8'hA9, 8'h30,
                     8'h04, 8'hBD, 8'h9F, 8'h53, 8'hBC, 8'h8B, 8'hDF, 8'h22,
                     8'h57, 8'h01, 8'h83, 8'h59, 8'h65, 8'hF2, 8'h06, 8'hDB},
                    'd32, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuUPLOAD_IDLE, 'd1, PID_ACK);

      test = "DFU_UPLOAD alt=2 (3/3)";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    {8'h06},
                    'd1, PID_ACK);

      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuIDLE, 'd1, PID_ACK);

      test = "DFU_UPLOAD alt=2 (1/3)";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd32,
                    {8'h96, 8'h5F, 8'h98, 8'h47, 8'hB4, 8'hA3, 8'hBA, 8'hAA,
                     8'h19, 8'h0B, 8'h4F, 8'hB0, 8'hB1, 8'h19, 8'h4C, 8'h54,
                     8'hF7, 8'hCE, 8'hE8, 8'h53, 8'h46, 8'h82, 8'hE2, 8'h39,
                     8'h72, 8'hA4, 8'hD1, 8'h7E, 8'h73, 8'h49, 8'h0A, 8'h44},
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

      test = "DFU_DNLOAD alt=2 (1/4)";
      test_setup_out(address, 8'h21, DFU_REQ_DNLOAD, 16'h0000, 16'h0000, 16'd32,
                     {"abcdefgh",
                      "01234567",
                      "ilmnopqr",
                      "stuvzxyw"},
                     'd32, PID_ACK);
 
      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuDNLOAD_SYNC, 'd1, PID_ACK);

      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd1, 8'd0, 8'd0, DFU_ST_dfuDNLOAD_IDLE, 8'd0}, 'd6, PID_ACK);

      test = "DFU_DNLOAD alt=2 (2/4)";
      test_setup_out(address, 8'h21, DFU_REQ_DNLOAD, 16'h0000, 16'h0000, 16'd32,
                     {"unlovely",
                      "-minx-br",
                      "ittle-ca",
                      "lcutta-0"},
                     'd32, PID_ACK);

      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd1, 8'd0, 8'd0, DFU_ST_dfuDNLOAD_IDLE, 8'd0}, 'd6, PID_ACK);

      test = "DFU_DNLOAD alt=2 (3/4)";
      test_setup_out(address, 8'h21, DFU_REQ_DNLOAD, 16'h0000, 16'h0000, 16'd1,
                     {"1"},
                     'd1, PID_ACK);

      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd1, 8'd0, 8'd0, DFU_ST_dfuDNLOAD_IDLE, 8'd0}, 'd6, PID_ACK);

      test = "DFU_DNLOAD alt=2 (4/4)";
      test_setup_out(address, 8'h21, DFU_REQ_DNLOAD, 16'h0000, 16'h0000, 16'd0,
                     {8'h00}, 'd0, PID_ACK);
 
      test = "DFU_GETSTATE";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATE, 16'h0000, 16'h0000, 16'h0001,
                    DFU_ST_dfuMANIFEST_SYNC, 'd1, PID_ACK);

      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd1, 8'd0, 8'd0, DFU_ST_dfuIDLE, 8'd0}, 'd6, PID_ACK);

      test = "SET_INTERFACE alt=0";
      test_setup_out(address, 8'h01, STD_REQ_SET_INTERFACE, 16'h0000, 16'h0000, 16'h0000,
                     8'd0, 0, PID_ACK);

      test = "DFU_UPLOAD alt=0";
      test_setup_in(address, 8'hA1, DFU_REQ_UPLOAD, 16'h0000, 16'h0000, 16'd64,
                     {"abcdefgh",
                      "0123456"},
                    'd15, PID_ACK);

      test = "SET_INTERFACE alt=3";
      test_setup_out(address, 8'h01, STD_REQ_SET_INTERFACE, 16'h0003, 16'h0000, 16'h0000,
                     8'd0, 0, PID_ACK);

      test = "DFU_UPLOAD alt=3";
      for (i = 0; i<32; i = i+1)
        data[8*(32-i-1) +:8] = flash_init_data[24'hB0000+i];
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

      test = "DFU_DNLOAD alt=3";
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

      test = "DFU_DNLOAD alt=3";
      test_setup_out(address, 8'h21, DFU_REQ_DNLOAD, 16'h0000, 16'h0000, 16'd0,
                     {8'h00}, 'd0, PID_ACK);

      #(2000000/83*`BIT_TIME); // wait 2ms

      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd1, 8'd0, 8'd0, DFU_ST_dfuIDLE, 8'd0}, 'd6, PID_ACK);

      test = "DFU_UPLOAD alt=3";
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

      test = "SET_INTERFACE alt=0";
      test_setup_out(address, 8'h01, STD_REQ_SET_INTERFACE, 16'h0000, 16'h0000, 16'h0000,
                     8'd0, 0, PID_ACK);

      test = "DFU_DNLOAD alt=0";
      test_setup_out(address, 8'h21, DFU_REQ_DNLOAD, 16'h0000, 16'h0000, 16'd16,
                     {"abcdefgh",
                      "stuvzxyw"},
                     'd16, PID_ACK);
 
      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {STATUS_errADDRESS, 8'd1, 8'd0, 8'd0, DFU_ST_dfuERROR, 8'd0}, 'd6, PID_ACK);

      test = "DFU_CLRSTATUS";
      test_setup_out(address, 8'h21, DFU_REQ_CLRSTATUS, 16'h0000, 16'h0000, 16'h0000,
                     8'd0, 'd0, PID_ACK);

 
      test = "DFU_GETSTATUS";
      test_setup_in(address, 8'hA1, DFU_REQ_GETSTATUS, 16'h0000, 16'h0000, 16'h0006,
                    {8'd0, 8'd1, 8'd0, 8'd0, DFU_ST_dfuIDLE, 8'd0}, 'd6, PID_ACK);


      test = "Test END";
      #(100*`BIT_TIME);
      `report_end("All tests correctly executed!")
   end
endmodule
