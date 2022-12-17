// DFU_APP module shall implement an example of bootloader.
// DFU_APP shall:
//   - Provide access to dfu-util to the FLASH:
//       - alt=0: read/write RAM (from 0x0 to 0xE)
//       - alt=1: read/write RAM (from 0x0 to 0x3F)
//       - alt=2: read/write RAM (from 0x0 to 0x40)
//       - alt=3: read/program FLASH user image (from 0xB0000 to 0xEFFFF)

`define max(a,b)((a) > (b) ? (a) : (b))

module dfu_app
  (
   input        clk_i,
   input        rstn_i,

   // ---- to/from USB_DFU ------------------------------------------
   input [2:0]  dfu_alt_i,
   input        dfu_out_en_i,
   input        dfu_in_en_i,
   output [7:0] dfu_in_data_o,
   output       dfu_in_valid_o,
   // While in_valid_o is high, in_data_o shall be valid.
   input        dfu_in_ready_i,
   // When both in_ready_i and in_valid_o are high, in_data_o shall
   //   be consumed.
   input [7:0]  dfu_out_data_i,
   input        dfu_out_valid_i,
   // While out_valid_i is high, the out_data_i shall be valid and both
   //   out_valid_i and out_data_i shall not change until consumed.
   output       dfu_out_ready_o,
   // When both out_valid_i and out_ready_o are high, the out_data_i shall
   //   be consumed.
   input        dfu_clear_status_i,
   output       dfu_busy_o,
   output [3:0] dfu_status_o,
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

   localparam       RAM_SIZE = 'd1024; // byte size
   localparam       FLASH_SIZE = 'd1048576; // byte size
   localparam       FLASH_BLOCK_SIZE = 'd4096; // byte size
   localparam       WAIT_CYCLES = 'd10;
   localparam       FLASH_START_ADDR = 'hB0000;
   localparam       FLASH_END_ADDR = 'hEFFFF;

   reg [7:0]        wait_cnt_q;

   wire [ceil_log2(RAM_SIZE)-1:0] ram_start_addr;
   wire [ceil_log2(RAM_SIZE)-1:0] ram_end_addr;
   wire [ceil_log2(RAM_SIZE)-1:0] ram_addr;
   wire                           ram_clke;
   wire                           ram_we;
   wire [ceil_log2(FLASH_SIZE)-ceil_log2(FLASH_BLOCK_SIZE)-1:0] flash_start_block_addr;
   wire [ceil_log2(FLASH_SIZE)-ceil_log2(FLASH_BLOCK_SIZE)-1:0] flash_end_block_addr;
   wire                                                         ram_en, flash_out_en, flash_in_en;
   wire                                                         ram_out_valid, flash_out_valid;
   wire                                                         ram_out_ready, flash_out_ready;
   wire                                                         ram_in_valid, flash_in_valid;
   wire                                                         ram_in_ready, flash_in_ready;
   wire [7:0]                                                   ram_in_data, flash_in_data;
   wire                                                         ram_clear_status, flash_clear_status;
   wire [3:0]                                                   ram_status, flash_status;

   assign ram_start_addr = 'd0;
   assign ram_end_addr = (dfu_alt_i == 3'd0) ? ('d15-1) :
                         ((dfu_alt_i == 3'd1) ? ('d64-1) :
                          ((dfu_alt_i == 3'd2) ? ('d65-1) : 'd0));
   assign flash_start_block_addr = FLASH_START_ADDR[ceil_log2(FLASH_SIZE)-1:ceil_log2(FLASH_BLOCK_SIZE)];
   assign flash_end_block_addr = FLASH_END_ADDR[ceil_log2(FLASH_SIZE)-1:ceil_log2(FLASH_BLOCK_SIZE)];
   assign ram_en = (dfu_alt_i == 3'd0 || dfu_alt_i == 3'd1 || dfu_alt_i == 3'd2) ? dfu_out_en_i | dfu_in_en_i : 1'b0;
   assign flash_out_en = (dfu_alt_i == 3'd3) ? dfu_out_en_i : 1'b0;
   assign flash_in_en = (dfu_alt_i == 3'd3) ? dfu_in_en_i : 1'b0;
   assign ram_out_valid = (dfu_alt_i == 3'd0 || dfu_alt_i == 3'd1 || dfu_alt_i == 3'd2) ? dfu_out_valid_i & ~|wait_cnt_q : 1'b0;
   assign flash_out_valid = (dfu_alt_i == 3'd3) ? dfu_out_valid_i : 1'b0;
   assign dfu_out_ready_o = (dfu_alt_i == 3'd3) ? flash_out_ready : ram_out_ready & ~|wait_cnt_q;   
   assign dfu_in_valid_o = (dfu_alt_i == 3'd3) ? flash_in_valid : ram_in_valid & ~|wait_cnt_q;   
   assign ram_in_ready = (dfu_alt_i == 3'd0 || dfu_alt_i == 3'd1 || dfu_alt_i == 3'd2) ? dfu_in_ready_i & ~|wait_cnt_q : 1'b0;
   assign flash_in_ready = (dfu_alt_i == 3'd3) ? dfu_in_ready_i : 1'b0;
   assign dfu_in_data_o = (dfu_alt_i == 3'd3) ? flash_in_data : ram_in_data;   
   assign ram_clear_status = (dfu_alt_i == 3'd0 || dfu_alt_i == 3'd1 || dfu_alt_i == 3'd2) ? dfu_clear_status_i : 1'b0;
   assign flash_clear_status = (dfu_alt_i == 3'd3) ? dfu_clear_status_i : 1'b0;
   assign dfu_status_o = (dfu_alt_i == 3'd3) ? flash_status : ram_status;   

   always @(posedge clk_i or negedge rstn) begin
      if (~rstn) begin
         wait_cnt_q <= 8'd0;
      end else begin
         if (|wait_cnt_q)
           wait_cnt_q <= wait_cnt_q - 1;
         else begin
            if ((dfu_out_valid_i & ram_out_ready) ||
                (dfu_in_ready_i & ram_in_valid))
              wait_cnt_q <= WAIT_CYCLES;
         end
      end
   end

   ram_if #(.RAM_SIZE(RAM_SIZE))
   u_ram_if (.clk_i(clk_i),
             .rstn_i(rstn),
             .en_i(ram_en),
             .start_addr_i(ram_start_addr),
             .end_addr_i(ram_end_addr),
             .out_valid_i(ram_out_valid),
             .out_ready_o(ram_out_ready),
             .in_valid_o(ram_in_valid),
             .in_ready_i(ram_in_ready),
             .clear_status_i(ram_clear_status),
             .status_o(ram_status),
             .ram_clke_o(ram_clke),
             .ram_we_o(ram_we),
             .ram_addr_o(ram_addr));

   ram #(.VECTOR_LENGTH(RAM_SIZE),
         .WORD_WIDTH('d8),
         .ADDR_WIDTH(ceil_log2(RAM_SIZE)))
   u_ram (.rdata_o(ram_in_data),
          .clk_i(clk_i),
          .clke_i(ram_clke),
          .we_i(ram_we),
          .addr_i(ram_addr),
          .mask_i(8'd0),
          .wdata_i(dfu_out_data_i));

   wire [ceil_log2('d512)-1:0] fifo_in_addr;
   wire [ceil_log2('d512)-1:0] fifo_out_addr;
   wire [7:0]                  fifo_out_data;
   wire                        fifo_in_clke;
   wire                        fifo_out_clke;
   wire                        fifo_out_ready;
   wire                        fifo_out_valid;
   wire                        fifo_empty;

   ram_fifo_if #(.RAM_SIZE('d512))
   u_ram_fifo_if (.clk_i(clk_i),
                  .rstn_i(rstn),
                  .en_i(flash_out_en | ~fifo_empty),
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

   flash_spi #(.SCK_PERIOD_MULTIPLIER('d2),
               .CLK_PERIODS_PER_US('d16),
               .FLASH_SIZE(FLASH_SIZE),
               .BLOCK_SIZE(FLASH_BLOCK_SIZE),
               .PAGE_SIZE('d256),
               .RESUME_US('d10),
               .BLOCK_ERASE_US('d60000),
               .PAGE_PROG_US('d700))
   u_flash_spi (.clk_i(clk_i),
                .rstn_i(rstn),
                .out_en_i(flash_out_en | ~fifo_empty),
                .in_en_i(flash_in_en),
                .start_block_addr_i(flash_start_block_addr),
                .end_block_addr_i(flash_end_block_addr),
                .read_addr_offset_i({ceil_log2(FLASH_BLOCK_SIZE){1'd0}}),
                .out_data_i(fifo_out_data),
                .out_valid_i(fifo_out_valid),
                .out_ready_o(fifo_out_ready),
                .in_data_o(flash_in_data),
                .in_valid_o(flash_in_valid),
                .in_ready_i(flash_in_ready),
                .clear_status_i(flash_clear_status),
                .status_o(flash_status),
                .erase_busy_o(dfu_busy_o),
                .program_busy_o(),
                .sck_o(sck_o),
                .csn_o(csn_o),
                .mosi_o(mosi_o),
                .miso_i(miso_i));

endmodule
