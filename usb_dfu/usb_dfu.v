//  USB 2.0 full speed Communications Device Class and Device Firmware Upgrade (DFU) Class.
//  Written in verilog 2001

// USB_DFU module shall implement Full Speed (12Mbit/s) USB communications device
//   class (or USB CDC class), Abstract Control Model (ACM) subclass and DFU class.
// USB_DFU shall implement two IN/OUT FIFO interfaces between USB and external APP
//   module, one for ACM class and the other for DFU class.

module usb_dfu
  #(parameter VENDORID = 16'h0000,
    parameter             PRODUCTID = 16'h0000,
    parameter [8*128-1:0] RTI_STRING = "0", // Run-time DFU interface string
    parameter [8*128-1:0] SN_STRING = "0", // Run-time/DFU Mode Device Serial Number
    parameter [8*128-1:0] ALT_STRINGS = "0", // concatenation of strings separated by "\000" or by "\n"
    parameter             TRANSFER_SIZE = 'd64,
    parameter             POLLTIMEOUT = 'd10, // ms
    parameter             MS20 = 1, // if 0 disable run-time MS20, enable otherwire
    parameter             WCID = 1, // if 0 disable DFU Mode WCID, enable otherwire
    parameter             MAXPACKETSIZE = 'd8,
    parameter             BIT_SAMPLES = 'd4,
    parameter             USE_APP_CLK = 0,
    parameter             APP_CLK_RATIO = 'd4)
   (
    input         clk_i,
    // clk_i clock shall have a frequency of 12MHz*BIT_SAMPLES
    input         rstn_i,
    // While rstn_i is low (active low), the module shall be reset

    // ---- to/from Application ------------------------------------
    input         app_clk_i,
    output [7:0]  out_data_o,
    output        out_valid_o,
    // While out_valid_o is high, the out_data_o shall be valid and both
    //   out_valid_o and out_data_o shall not change until consumed.
    input         out_ready_i,
    // When both out_valid_o and out_ready_i are high, the out_data_o shall
    //   be consumed.
    input [7:0]   in_data_i,
    input         in_valid_i,
    // While in_valid_i is high, in_data_i shall be valid.
    output        in_ready_o,
    // When both in_ready_o and in_valid_i are high, in_data_i shall
    //   be consumed.
    output [10:0] frame_o,
    // frame_o shall be last recognized USB frame number sent by USB host.
    output        configured_o,
    // While USB_DFU is in configured state, configured_o shall be high.
    output        dfu_mode_o,
    // While USB_DFU is in DFU Mode, dfu_mode_o shall be high.
    output [2:0]  dfu_alt_o,
    // dfu_alt_o shall report the current alternate interface setting.
    output        dfu_out_en_o,
    // While DFU is in dfuDNBUSY|dfuDNLOAD_SYNC|dfuDNLOAD_IDLE states, dfu_out_en_o shall be high.
    output        dfu_in_en_o,
    // While DFU is in dfuUPLOAD_IDLE state, dfu_in_en_o shall be high.
    output [7:0]  dfu_out_data_o,
    output        dfu_out_valid_o,
    // While dfu_out_valid_o is high, the dfu_out_data_o shall be valid and both
    //   dfu_out_valid_o and dfu_out_data_o shall not change until consumed.
    input         dfu_out_ready_i,
    // When both dfu_out_valid_o and dfu_out_ready_i are high, the dfu_out_data_o shall
    //   be consumed.
    input [7:0]   dfu_in_data_i,
    input         dfu_in_valid_i,
    // While dfu_in_valid_i is high, dfu_in_data_i shall be valid.
    output        dfu_in_ready_o,
    // When both dfu_in_ready_o and dfu_in_valid_i are high, dfu_in_data_i shall
    //   be consumed.
    output        dfu_clear_status_o,
    // While DFU is in dfuIDLE state, dfu_clear_status_o shall be high.
    output [15:0] dfu_blocknum_o,
    // dfu_blocknum_o shall report DFU_DNLOAD/DFU_UPLOAD block sequence number.
    input         dfu_busy_i,
    // When DFU_DNLOAD request target is busy and needs time to be ready for next data, dfu_busy_i
    //   shall be high.
    input [3:0]   dfu_status_i,
    // dfu_status_i shall report the status resulting from the execution of the most recent DFU request.

    // ---- to USB bus physical transmitters/receivers --------------
    output        dp_pu_o,
    output        tx_en_o,
    output        dp_tx_o,
    output        dn_tx_o,
    input         dp_rx_i,
    input         dn_rx_i
    );

   function integer ceil_log2;
      input integer arg;
      begin
         ceil_log2 = 0;
         while ((2 ** ceil_log2) < arg)
           ceil_log2 = ceil_log2 + 1;
      end
   endfunction

   localparam [3:0] ENDP_CTRL = 'd0,
                    ENDP_BULK = 'd1,
                    ENDP_INT = 'd2;

   reg [1:0]        rstn_sq;

   wire             rstn;

   assign rstn = rstn_sq[0];

   always @(posedge clk_i or negedge rstn_i) begin
      if (~rstn_i) begin
         rstn_sq <= 2'd0;
      end else begin
         rstn_sq <= {1'b1, rstn_sq[1]};
      end
   end

   reg              dfu_clear_status_q;

   wire [7:0]       fifo_out_data, fifo2i_in_data;
   wire             fifo_out_valid;
   wire             fifo2i_in_valid;
   wire             usb_reset;
   wire             fifo_in_ready;
   wire             fifo_out_ready;
   wire             dfu_mode, dfu_upload, dfu_dnload;
   wire             dfu_clear_status;
   wire             fifo_out_empty;
   wire             dfu_mode_s;
   wire             dfu_out_en_s;
   wire             dfu_in_en_s;
   wire             dfu_status_s;
   wire             dfu_busy_s;
   wire             dfu_clear_status_s;

   assign dfu_mode_o = dfu_mode_s;
   assign dfu_out_en_o = dfu_out_en_s;
   assign dfu_in_en_o = dfu_in_en_s;
   assign dfu_clear_status_o = dfu_clear_status_s;
   assign dfu_out_data_o = fifo_out_data;
   assign out_data_o = fifo_out_data;
   assign dfu_out_valid_o = (dfu_dnload) ? fifo_out_valid : 1'b0;
   assign out_valid_o = (~dfu_mode_s) ? fifo_out_valid : 1'b0;
   assign dfu_in_ready_o = (dfu_upload) ? fifo_in_ready : 1'b0;
   assign in_ready_o = (~dfu_mode_s) ? fifo_in_ready : 1'b0;
   assign fifo_out_ready = (dfu_mode_s == 1'b0) ? out_ready_i : dfu_out_ready_i & dfu_dnload;
   assign fifo2i_in_data = (dfu_mode_s == 1'b0) ? in_data_i : dfu_in_data_i;
   assign fifo2i_in_valid = (dfu_mode_s == 1'b0) ? in_valid_i : dfu_in_valid_i & dfu_upload;

   generate
      if (USE_APP_CLK == 0) begin : u_sync_app
         assign dfu_mode_s = dfu_mode;
         assign dfu_out_en_s = dfu_dnload | ~fifo_out_empty;
         assign dfu_in_en_s = dfu_upload;
         assign dfu_status_s = |dfu_status_i;
         assign dfu_busy_s = dfu_busy_i;
         assign dfu_clear_status_s = dfu_clear_status_q;

      end else begin : u_async_app
         reg [1:0] app_rstn_sq;
         reg [1:0] dfu_mode_sq;
         reg [1:0] dfu_out_en_sq;
         reg [1:0] dfu_in_en_sq;
         reg [2:0] dfu_status_sq; // sync with 1 more bit to increase dfu_done delay in u_ctrl_endp
         reg [1:0] dfu_busy_sq;
         reg [1:0] dfu_clear_status_sq;

         wire      app_rstn;

         assign app_rstn = app_rstn_sq[0];
         assign dfu_mode_s = dfu_mode_sq[0];
         assign dfu_out_en_s = dfu_out_en_sq[0];
         assign dfu_in_en_s = dfu_in_en_sq[0];
         assign dfu_status_s = dfu_status_sq[0];
         assign dfu_busy_s = dfu_busy_sq[0];
         assign dfu_clear_status_s = dfu_clear_status_sq[0];

         always @(posedge clk_i or negedge rstn) begin
            if (~rstn) begin
               dfu_busy_sq <= 2'b0;
               dfu_status_sq <= 3'b0;
            end else begin
               dfu_busy_sq <= {dfu_busy_i, dfu_busy_sq[1]};
               dfu_status_sq <= {|dfu_status_i, dfu_status_sq[2:1]};
            end
         end

         always @(posedge app_clk_i or negedge rstn_i) begin
            if (~rstn_i) begin
               app_rstn_sq <= 2'd0;
            end else begin
               app_rstn_sq <= {1'b1, app_rstn_sq[1]};
            end
         end

         always @(posedge app_clk_i or negedge app_rstn) begin
            if (~app_rstn) begin
               dfu_mode_sq <= 2'd0;
               dfu_out_en_sq <= 2'd0;
               dfu_in_en_sq <= 2'd0;
               dfu_clear_status_sq <= 2'd0;
            end else begin
               dfu_mode_sq <= {dfu_mode, dfu_mode_sq[1]};
               dfu_out_en_sq <= {dfu_dnload | ~fifo_out_empty, dfu_out_en_sq[1]};
               dfu_in_en_sq <= {dfu_upload, dfu_in_en_sq[1]};
               dfu_clear_status_sq <= {dfu_clear_status_q, dfu_clear_status_sq[1]};
            end
         end
      end
   endgenerate

   always @(posedge clk_i or negedge rstn) begin
      if (~rstn) begin
         dfu_clear_status_q <= 1'b0;
      end else begin
         dfu_clear_status_q <= (dfu_clear_status | dfu_clear_status_q) & dfu_status_s & ~usb_reset;
      end
   end

   reg  fifo_in_full_q;

   wire [3:0] endp;
   wire [6:0] addr;
   wire [7:0] sie_out_data;
   wire [7:0] sie2i_in_data, ctrl_in_data, fifo_in_data;
   wire       sie2i_in_zlp, ctrl_in_zlp;
   wire       sie2i_in_valid, ctrl_in_valid, fifo_in_valid;
   wire       sie2i_stall, ctrl_stall;
   wire       sie2i_out_nak, fifo_out_nak;
   wire       sie2i_in_nak;
   wire       sie_out_valid;
   wire       sie_out_err;
   wire       sie_in_data_ack;
   wire       setup;
   wire       in_toggle_reset;
   wire       out_toggle_reset;
   wire       sie_in_ready, ctrl2i_in_ready, fifo2i_in_ready;
   wire       sie_out_ready, ctrl2i_out_ready, fifo2i_out_ready;
   wire       sie_in_req, ctrl2i_in_req, fifo2i_in_req;
   wire       usb_en, usb_detach;
   wire       dfu_done;
   wire       dfu_fifo;
   wire       fifo_in_empty;
   wire       fifo_in_full;

   assign sie2i_in_data = ((endp == ENDP_BULK && dfu_mode == 1'b0) || (endp == ENDP_CTRL && dfu_fifo == 1'b1)) ?
                          fifo_in_data : ctrl_in_data;
   assign sie2i_in_zlp = (endp == ENDP_CTRL) ? ctrl_in_zlp : 1'b0;
   assign sie2i_in_valid = (endp == ENDP_BULK && dfu_mode == 1'b0) ? fifo_in_valid :
                           ((endp == ENDP_CTRL && dfu_fifo == 1'b1 && dfu_upload) ? (fifo_in_valid & (fifo_in_full_q | dfu_status_s)):
                            ((endp == ENDP_CTRL) ? ctrl_in_valid : 1'b0));
   assign sie2i_stall = (endp == ENDP_CTRL) ? ctrl_stall : 1'b0;
   assign sie2i_out_nak = (endp == ENDP_BULK && dfu_mode == 1'b0) ? fifo_out_nak :
                          ((endp == ENDP_CTRL && dfu_fifo == 1'b1) ? fifo_out_nak : 1'b0);
   assign sie2i_in_nak = (endp == ENDP_CTRL && dfu_fifo == 1'b1 && dfu_upload) ? ~(fifo_in_full_q | dfu_status_s) : 1'b0;
   assign ctrl2i_in_ready = (endp == ENDP_CTRL) ? sie_in_ready : 1'b0;
   assign fifo2i_in_ready = ((endp == ENDP_BULK && dfu_mode == 1'b0) || (endp == ENDP_CTRL && dfu_fifo == 1'b1)) ? sie_in_ready : 1'b0;
   assign ctrl2i_out_ready = (endp == ENDP_CTRL) ? sie_out_ready : 1'b0;
   assign fifo2i_out_ready = ((endp == ENDP_BULK && dfu_mode == 1'b0) || (endp == ENDP_CTRL && dfu_fifo == 1'b1)) ? sie_out_ready : 1'b0;
   assign ctrl2i_in_req = (endp == ENDP_CTRL) ? sie_in_req : 1'b0;
   assign fifo2i_in_req = ((endp == ENDP_BULK && dfu_mode == 1'b0) || (endp == ENDP_CTRL && dfu_fifo == 1'b1)) ? sie_in_req : 1'b0;
   assign dfu_done = dfu_status_s & fifo_in_empty;

   always @(posedge clk_i or negedge rstn) begin
      if (~rstn) begin
         fifo_in_full_q <= 1'b0;
      end else begin
         if (~sie_in_req)
           fifo_in_full_q <= fifo_in_full;
      end
   end

   sie #(.CTRL_MAXPACKETSIZE(MAXPACKETSIZE),
         .IN_BULK_MAXPACKETSIZE(MAXPACKETSIZE),
         .ENDP_CTRL(ENDP_CTRL),
         .ENDP_BULK(ENDP_BULK),
         .BIT_SAMPLES(BIT_SAMPLES))
   u_sie (.usb_reset_o(usb_reset),
          .dp_pu_o(dp_pu_o),
          .tx_en_o(tx_en_o),
          .dp_tx_o(dp_tx_o),
          .dn_tx_o(dn_tx_o),
          .endp_o(endp),
          .frame_o(frame_o),
          .out_data_o(sie_out_data),
          .out_valid_o(sie_out_valid),
          .out_err_o(sie_out_err),
          .in_req_o(sie_in_req),
          .setup_o(setup),
          .out_ready_o(sie_out_ready),
          .in_ready_o(sie_in_ready),
          .in_data_ack_o(sie_in_data_ack),
          .clk_i(clk_i),
          .rstn_i(rstn),
          .usb_en_i(usb_en),
          .usb_detach_i(usb_detach),
          .dp_rx_i(dp_rx_i),
          .dn_rx_i(dn_rx_i),
          .addr_i(addr),
          .in_valid_i(sie2i_in_valid),
          .in_data_i(sie2i_in_data),
          .in_zlp_i(sie2i_in_zlp),
          .out_nak_i(sie2i_out_nak),
          .in_nak_i(sie2i_in_nak),
          .stall_i(sie2i_stall),
          .in_toggle_reset_i(in_toggle_reset),
          .out_toggle_reset_i(out_toggle_reset));

   ctrl_endp #(.VENDORID(VENDORID),
               .PRODUCTID(PRODUCTID),
               .RTI_STRING(RTI_STRING),
               .SN_STRING(SN_STRING),
               .ALT_STRINGS(ALT_STRINGS),
               .TRANSFER_SIZE(TRANSFER_SIZE),
               .POLLTIMEOUT(POLLTIMEOUT),
               .MS20(MS20),
               .WCID(WCID),
               .CTRL_MAXPACKETSIZE(MAXPACKETSIZE),
               .IN_BULK_MAXPACKETSIZE(MAXPACKETSIZE),
               .OUT_BULK_MAXPACKETSIZE(MAXPACKETSIZE),
               .ENDP_BULK(ENDP_BULK),
               .ENDP_INT(ENDP_INT))
   u_ctrl_endp (.configured_o(configured_o),
                .usb_en_o(usb_en),
                .usb_detach_o(usb_detach),
                .dfu_mode_o(dfu_mode),
                .dfu_alt_o(dfu_alt_o),
                .dfu_upload_o(dfu_upload),
                .dfu_dnload_o(dfu_dnload),
                .dfu_fifo_o(dfu_fifo),
                .dfu_clear_status_o(dfu_clear_status),
                .dfu_blocknum_o(dfu_blocknum_o),
                .addr_o(addr),
                .in_data_o(ctrl_in_data),
                .in_zlp_o(ctrl_in_zlp),
                .in_valid_o(ctrl_in_valid),
                .stall_o(ctrl_stall),
                .in_toggle_reset_o(in_toggle_reset),
                .out_toggle_reset_o(out_toggle_reset),
                .clk_i(clk_i),
                .rstn_i(rstn),
                .usb_reset_i(usb_reset),
                .dfu_status_i((dfu_status_s) ? ((&dfu_status_i) ? 4'h0 : dfu_status_i) : 4'h0), // if END operation (4'hF) report status OK
                .dfu_busy_i(dfu_busy_s),
                .dfu_done_i(dfu_done),
                .out_data_i(sie_out_data),
                .out_valid_i(sie_out_valid),
                .out_err_i(sie_out_err),
                .in_req_i(ctrl2i_in_req),
                .setup_i(setup),
                .in_data_ack_i(sie_in_data_ack),
                .out_ready_i(ctrl2i_out_ready),
                .in_ready_i(ctrl2i_in_ready));

   fifo #(.IN_MAXPACKETSIZE(MAXPACKETSIZE),
          .OUT_MAXPACKETSIZE(MAXPACKETSIZE),
          .BIT_SAMPLES(BIT_SAMPLES),
          .USE_APP_CLK(USE_APP_CLK),
          .APP_CLK_RATIO(APP_CLK_RATIO))
   u_fifo (.in_data_o(fifo_in_data),
           .in_valid_o(fifo_in_valid),
           .app_in_ready_o(fifo_in_ready),
           .out_nak_o(fifo_out_nak),
           .app_out_valid_o(fifo_out_valid),
           .app_out_data_o(fifo_out_data),
           .clk_i(clk_i),
           .app_clk_i(app_clk_i),
           .rstn_i(rstn & ~(dfu_mode & ~dfu_upload & ~((dfu_dnload | ~fifo_out_empty) & ~dfu_clear_status))),
           .usb_reset_i(usb_reset),
           .in_empty_o(fifo_in_empty),
           .in_full_o(fifo_in_full),
           .out_empty_o(fifo_out_empty),
           .out_data_i(sie_out_data),
           .out_valid_i(sie_out_valid),
           .out_err_i(sie_out_err),
           .in_req_i(fifo2i_in_req),
           .in_data_ack_i(sie_in_data_ack),
           .app_in_data_i(fifo2i_in_data),
           .app_in_valid_i(fifo2i_in_valid),
           .out_ready_i(fifo2i_out_ready),
           .in_ready_i(fifo2i_in_ready),
           .app_out_ready_i(fifo_out_ready));
endmodule
