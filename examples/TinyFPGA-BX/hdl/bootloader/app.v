// APP module shall implement an example of bootloader.
// APP shall:
//   - Provide access to tinyprog to the FLASH.
//   - Provide access to dfu-util to the FLASH:
//       - alt=0: read/program FLASH user image (from 0x28000 to 0x4FFFF)
//       - alt=1: read only whole FLASH data (from 0x0 to 0xFFFFF)
//       - alt=2: boot to user image with fake download/upload data

`define max(a,b)((a) > (b) ? (a) : (b))

module app
  (
   input        clk_i,
   input        rstn_i,

   // ---- to/from USB_DFU ------------------------------------------
   output [7:0] in_data_o,
   output       in_valid_o,
   // While in_valid_o is high, in_data_o shall be valid.
   input        in_ready_i,
   // When both in_ready_i and in_valid_o are high, in_data_o shall
   //   be consumed.
   input [7:0]  out_data_i,
   input        out_valid_i,
   // While out_valid_i is high, the out_data_i shall be valid and both
   //   out_valid_i and out_data_i shall not change until consumed.
   output       out_ready_o,
   // When both out_valid_i and out_ready_o are high, the out_data_i shall
   //   be consumed.
   input        dfu_mode_i,
   // While USB_DFU is in DFU Mode, dfu_mode_i shall be high.
   input [2:0]  dfu_alt_i,
   // dfu_alt_i shall report the current alternate interface setting.
   input        dfu_out_en_i,
   // While DFU is in dfuDNBUSY|dfuDNLOAD_SYNC|dfuDNLOAD_IDLE states, dfu_out_en_i shall be high.
   input        dfu_in_en_i,
   // While DFU is in dfuUPLOAD_IDLE state, dfu_in_en_i shall be high.
   output [7:0] dfu_in_data_o,
   output       dfu_in_valid_o,
   // While dfu_in_valid_o is high, dfu_in_data_o shall be valid.
   input        dfu_in_ready_i,
   // When both dfu_in_ready_i and dfu_in_valid_o are high, dfu_in_data_o shall
   //   be consumed.
   input [7:0]  dfu_out_data_i,
   input        dfu_out_valid_i,
   // While dfu_out_valid_i is high, the dfu_out_data_i shall be valid and both
   //   dfu_out_valid_i and dfu_out_data_i shall not change until consumed.
   output       dfu_out_ready_o,
   // When both dfu_out_valid_i and dfu_out_ready_o are high, the dfu_out_data_i shall
   //   be consumed.
   input        dfu_clear_status_i,
   // While DFU is in dfuIDLE state, dfu_clear_status_o shall be high.
   output       dfu_busy_o,
   // When DFU_DNLOAD request target is busy and needs time to be ready for next data, dfu_busy_o
   //   shall be high.
   output [3:0] dfu_status_o,
   // dfu_status_o shall report the status resulting from the execution of the most recent DFU request.
   input        heartbeat_i,
   // heartbeat_i transitions shall occur if the USB interface is alive.
   output       boot_o,
   // boot_o shall be high to force an FPGA reboot to the programmed image.
   output       sck_o,
   output       csn_o,
   output       mosi_o,
   input        miso_i
   );

   function integer ceil_log2;
      input integer arg;
      begin
         ceil_log2 = 0;
         while ((2 ** ceil_log2) < arg)
           ceil_log2 = ceil_log2 + 1;
      end
   endfunction

   reg [1:0]         rstn_sq;

   wire              rstn;

   assign rstn = rstn_sq[0];

   always @(posedge clk_i or negedge rstn_i) begin
      if (~rstn_i) begin
         rstn_sq <= 2'd0;
      end else begin
         rstn_sq <= {1'b1, rstn_sq[1]};
      end
   end

   reg        boot;

   wire       dfu_boot;
   wire       spi_wr_ready;
   wire [7:0] spi_rd_data;
   wire       spi_rd_valid;

   assign boot_o = boot | dfu_boot;

   //-------- tinyprog management -------------

   localparam [2:0] ST_IDLE = 3'd0,
                    ST_WR_LO_LENGTH = 3'd1,
                    ST_WR_HI_LENGTH = 3'd2,
                    ST_RD_LO_LENGTH = 3'd3,
                    ST_RD_HI_LENGTH = 3'd4,
                    ST_WR_DATA = 3'd5,
                    ST_RD_DATA = 3'd6,
                    ST_BOOT = 3'd7;
   localparam       TIMER_MSB = ceil_log2(2*16000000); // 2 sec

   reg [2:0]        state_q, state_d;
   reg [15:0]       wr_length_q, wr_length_d;
   reg [15:0]       rd_length_q, rd_length_d;
   reg [TIMER_MSB:0] timer_q, timer_d;
   reg [2:0]         heartbeat_sq;

   wire              rt_rstn = rstn & ~dfu_mode_i;

   always @(posedge clk_i or negedge rt_rstn) begin
      if (~rt_rstn) begin
         state_q <= ST_IDLE;
         wr_length_q <= 'd0;
         rd_length_q <= 'd0;
         timer_q <= 'd0;
         heartbeat_sq <= 3'd0;
      end else begin
         state_q <= state_d;
         wr_length_q <= wr_length_d;
         rd_length_q <= rd_length_d;
         timer_q <= timer_d;
         heartbeat_sq <= {heartbeat_i, heartbeat_sq[2:1]};
      end
   end

   reg        en;
   reg        wr_valid;
   reg        rd_ready;
   reg        in_valid;
   reg        out_ready;

   wire       wr_ready;
   wire       rd_valid;

   assign in_data_o = spi_rd_data;
   assign in_valid_o = in_valid;
   assign out_ready_o = out_ready;

   always @(/*AS*/heartbeat_sq or in_ready_i or out_data_i
            or out_valid_i or rd_length_q or rd_valid or state_q
            or timer_q or wr_length_q or wr_ready) begin
      state_d = state_q;
      wr_length_d = wr_length_q;
      rd_length_d = rd_length_q;
      if (heartbeat_sq[1] != heartbeat_sq[0])
        timer_d = 'd0;
      else
        timer_d = timer_q + 1;
      en = 1'b0;
      wr_valid = 1'b0;
      rd_ready = 1'b0;
      in_valid = 1'b0;
      out_ready = 1'b0;
      boot = 1'b0;

      if (timer_q[TIMER_MSB])
        state_d = ST_BOOT;

      case (state_q)
        ST_IDLE : begin
           out_ready = 1'b1;
           if (out_valid_i == 1'b1) begin
              if (out_data_i == 8'h00)
                state_d = ST_BOOT;
              else if (out_data_i == 8'h01)
                state_d = ST_WR_LO_LENGTH;
           end
        end
        ST_WR_LO_LENGTH : begin
           out_ready = 1'b1;
           if (out_valid_i == 1'b1) begin
              state_d = ST_WR_HI_LENGTH;
              wr_length_d[7:0] = out_data_i;
           end
        end
        ST_WR_HI_LENGTH : begin
           out_ready = 1'b1;
           if (out_valid_i == 1'b1) begin
              state_d = ST_RD_LO_LENGTH;
              wr_length_d[15:8] = out_data_i;
           end
        end
        ST_RD_LO_LENGTH : begin
           out_ready = 1'b1;
           if (out_valid_i == 1'b1) begin
              state_d = ST_RD_HI_LENGTH;
              rd_length_d[7:0] = out_data_i;
           end
        end
        ST_RD_HI_LENGTH : begin
           out_ready = 1'b1;
           if (out_valid_i == 1'b1) begin
              state_d = ST_WR_DATA;
              rd_length_d[15:8] = out_data_i;
           end
        end
        ST_WR_DATA : begin
           en = 1'b1;
           if (wr_length_q == 'd0) begin
              if (rd_length_q == 'd0)
                state_d = ST_IDLE;
              else if (rd_valid)
                state_d = ST_RD_DATA;
           end else begin
              wr_valid = out_valid_i;
              out_ready = wr_ready;
              if (wr_ready & out_valid_i)
                wr_length_d = wr_length_q - 1;
           end
        end
        ST_RD_DATA : begin
           en = 1'b1;
           if (rd_length_q == 'd0) begin
              state_d = ST_IDLE;
           end else begin
              in_valid = rd_valid;
              rd_ready = in_ready_i;
              if (rd_valid & in_ready_i)
                rd_length_d = rd_length_q - 1;
           end
        end
        ST_BOOT : begin
           boot = 1'b1;
        end
        default : begin
           state_d = ST_IDLE;
        end
      endcase
   end


   //-------- DFU management -------------

   localparam       FLASH_SIZE = 'd1048576; // byte size
   localparam       FLASH_BLOCK_SIZE = 'd4096; // byte size
   localparam       FLASH_START_ADDR = 'h28000;
   localparam       FLASH_END_ADDR = 'h50000-'d1;
   localparam       FLASH_END_READ_ADDR = FLASH_SIZE-'d1;

   wire [ceil_log2(FLASH_SIZE)-ceil_log2(FLASH_BLOCK_SIZE)-1:0] flash_start_block_addr;
   wire [ceil_log2(FLASH_SIZE)-ceil_log2(FLASH_BLOCK_SIZE)-1:0] flash_end_block_addr;
   wire                                                         flash_out_en, flash_in_en;
   wire                                                         flash_out_valid;
   wire                                                         flash_out_ready;

   assign dfu_boot = (dfu_alt_i == 'd2) ? dfu_out_en_i | dfu_in_en_i : 1'b0;
   assign flash_start_block_addr = (dfu_alt_i == 'd0) ?
                                   FLASH_START_ADDR[ceil_log2(FLASH_SIZE)-1:ceil_log2(FLASH_BLOCK_SIZE)] :
                                   'd0;
   assign flash_end_block_addr = (dfu_alt_i == 'd0) ?
                                 FLASH_END_ADDR[ceil_log2(FLASH_SIZE)-1:ceil_log2(FLASH_BLOCK_SIZE)] :
                                 FLASH_END_READ_ADDR[ceil_log2(FLASH_SIZE)-1:ceil_log2(FLASH_BLOCK_SIZE)];
   assign flash_out_en = (dfu_alt_i == 'd0) ? dfu_out_en_i : 1'b0;
   assign flash_in_en = (dfu_alt_i == 'd0 || dfu_alt_i == 'd1) ? dfu_in_en_i : 1'b0;
   assign flash_out_valid = (dfu_alt_i == 'd0) ? dfu_out_valid_i : 1'b0;
   assign dfu_out_ready_o = (dfu_alt_i == 'd0) ? flash_out_ready : 1'b0;

   wire [ceil_log2('d512)-1:0]                                  fifo_in_addr;
   wire [ceil_log2('d512)-1:0]                                  fifo_out_addr;
   wire [7:0]                                                   fifo_out_data;
   wire                                                         fifo_in_clke;
   wire                                                         fifo_out_clke;
   wire                                                         fifo_out_ready;
   wire                                                         fifo_out_valid;
   wire                                                         fifo_empty;
   wire                                                         dfu_en;
   wire [7:0]                                                   dfu_wr_data;
   wire                                                         dfu_wr_valid;
   wire                                                         dfu_wr_ready;
   wire                                                         dfu_rd_valid;
   wire                                                         dfu_rd_ready;

   ram_fifo_if #(.RAM_SIZE('d512))
   u_ram_fifo_if (.clk_i(clk_i),
                  .rstn_i(rstn & dfu_mode_i),
                  .en_i((flash_out_en | ~fifo_empty) & ~dfu_clear_status_i),
                  .in_valid_i(flash_out_valid),
                  .in_ready_o(flash_out_ready),
                  .out_valid_o(fifo_out_valid),
                  .out_ready_i(fifo_out_ready),
                  .empty_o(fifo_empty),
                  .full_o(),
                  .in_clke_o(fifo_in_clke),
                  .out_clke_o(fifo_out_clke),
                  .in_addr_o(fifo_in_addr),
                  .out_addr_o(fifo_out_addr));

   dpram #(.VECTOR_LENGTH('d512),
           .WORD_WIDTH('d8),
           .ADDR_WIDTH(ceil_log2('d512)))
   u_dpram (.rdata_o(fifo_out_data),
            .rclk_i(clk_i),
            .rclke_i(fifo_out_clke),
            .re_i(1'b1),
            .raddr_i(fifo_out_addr),
            .wdata_i(dfu_out_data_i),
            .wclk_i(clk_i),
            .wclke_i(fifo_in_clke),
            .we_i(1'b1),
            .waddr_i(fifo_in_addr),
            .mask_i(8'd0));

   flash_if #(.SCK_PERIOD_MULTIPLIER('d2),
              .CLK_PERIODS_PER_US('d16),
              .FLASH_SIZE(FLASH_SIZE),
              .BLOCK_SIZE(FLASH_BLOCK_SIZE),
              .PAGE_SIZE('d256),
              .RESUME_US('d10),
              .BLOCK_ERASE_US('d60000),
              .PAGE_PROG_US('d700))
   u_flash_if (.clk_i(clk_i),
               .rstn_i(rstn & dfu_mode_i),
               .out_en_i(flash_out_en | ~fifo_empty),
               .in_en_i(flash_in_en),
               .start_block_addr_i(flash_start_block_addr),
               .end_block_addr_i(flash_end_block_addr),
               .read_addr_offset_i({ceil_log2(FLASH_BLOCK_SIZE){1'd0}}),
               .out_data_i(fifo_out_data),
               .out_valid_i(fifo_out_valid),
               .out_ready_o(fifo_out_ready),
               .in_data_o(dfu_in_data_o),
               .in_valid_o(dfu_in_valid_o),
               .in_ready_i(dfu_in_ready_i),
               .clear_status_i(dfu_clear_status_i),
               .status_o(dfu_status_o),
               .erase_busy_o(dfu_busy_o),
               .program_busy_o(),
               .spi_en_o(dfu_en),
               .spi_wr_data_o(dfu_wr_data),
               .spi_wr_valid_o(dfu_wr_valid),
               .spi_wr_ready_i(dfu_wr_ready),
               .spi_rd_data_i(spi_rd_data),
               .spi_rd_valid_i(dfu_rd_valid),
               .spi_rd_ready_o(dfu_rd_ready));


   assign dfu_wr_ready = (dfu_mode_i) ? spi_wr_ready : 1'b0;
   assign wr_ready = (dfu_mode_i) ? 1'b0 : spi_wr_ready;
   assign dfu_rd_valid = (dfu_mode_i) ? spi_rd_valid : 1'b0;
   assign rd_valid = (dfu_mode_i) ? 1'b0 : spi_rd_valid;

   spi #(.SCK_PERIOD_MULTIPLIER('d2))
   u_spi (.clk_i(clk_i),
          .rstn_i(rstn),
          .en_i((dfu_mode_i) ? dfu_en : en),
          .wr_data_i((dfu_mode_i) ? dfu_wr_data : out_data_i),
          .wr_valid_i((dfu_mode_i) ? dfu_wr_valid : wr_valid),
          .wr_ready_o(spi_wr_ready),
          .rd_data_o(spi_rd_data),
          .rd_valid_o(spi_rd_valid),
          .rd_ready_i((dfu_mode_i) ? dfu_rd_ready : rd_ready),
          .sck_o(sck_o),
          .csn_o(csn_o),
          .mosi_o(mosi_o),
          .miso_i(miso_i));
endmodule
