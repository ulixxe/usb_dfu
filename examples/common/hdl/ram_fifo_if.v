//  FLASH memory serial interface.
//  Written in verilog 2001

//  FLASH_SPI module shall provide access to read/program serial FLASH memory:
//    - When en_i changes from low to high, a new read/program operation shall start.
//    - Memory read shall start at byte address specified by start_block_addr_i+read_addr_offset_i.
//    - Memory programming shall start at beginning of the block addressed by start_block_addr_i.
//    - Memory read/program operation shall end at the end of the block addressed by end_block_addr_i.
//  FLASH_SPI module shall check correct block erasing and correct data programming:
//    - Erase/Programming failures shall be reported by status_o.
//    - When status_o reports a failure, FLASH_SPI shall wait a clear_status_i pulse to clear status_o
//        and to allow the next read/program operation.

module ram_fifo_if
  #(parameter RAM_SIZE = 'd1024) // byte size
   (
    input                            clk_i,
    input                            rstn_i,
    // While rstn_i is low (active low), the module shall be reset

    // ---- to/from application module --------------
    input                            en_i,
    input                            in_valid_i,
    output                           in_ready_o,
    output                           out_valid_o,
    input                            out_ready_i,
    output                           empty_o,
    output                           full_o,
    output                           in_clke_o,
    output                           out_clke_o,
    output [ceil_log2(RAM_SIZE)-1:0] in_addr_o,
    output [ceil_log2(RAM_SIZE)-1:0] out_addr_o
    );

   function integer ceil_log2;
      input integer                  arg;
      begin
         ceil_log2 = 0;
         while ((2 ** ceil_log2) < arg)
           ceil_log2 = ceil_log2 + 1;
      end
   endfunction

   reg [ceil_log2(RAM_SIZE)+1-1:0] in_addr_q, in_addr_d;
   reg [ceil_log2(RAM_SIZE)+1-1:0] out_addr_q, out_addr_d;
   reg                             out_valid_q, out_valid_d;

   wire                            empty, full;

   assign empty_o = empty & ~out_valid_q;
   assign full_o = full;
   assign empty = (in_addr_q == out_addr_q) ? 1'b1 : 1'b0;
   assign full = (in_addr_q[ceil_log2(RAM_SIZE)-1:0] == out_addr_q[ceil_log2(RAM_SIZE)-1:0] &&
                  in_addr_q[ceil_log2(RAM_SIZE)+1-1] != out_addr_q[ceil_log2(RAM_SIZE)+1-1]) ?
                 1'b1 : 1'b0;
   assign in_ready_o = ~full;
   assign out_valid_o = out_valid_q;
   assign in_addr_o = in_addr_q[ceil_log2(RAM_SIZE)-1:0];
   assign out_addr_o = out_addr_q[ceil_log2(RAM_SIZE)-1:0];

   always @(posedge clk_i or negedge rstn_i) begin
      if (~rstn_i) begin
         in_addr_q <= 'd0;
         out_addr_q <= 'd0;
         out_valid_q <= 1'b0;
      end else begin
         in_addr_q <= in_addr_d;
         out_addr_q <= out_addr_d;
         out_valid_q <= out_valid_d;
      end
   end

   reg in_clke;
   reg out_clke;

   assign in_clke_o = in_clke;
   assign out_clke_o = out_clke;

   always @(/*AS*/empty or en_i or full or in_addr_q or in_valid_i
            or out_addr_q or out_ready_i or out_valid_q) begin
      in_addr_d = in_addr_q;
      out_addr_d = out_addr_q;
      out_valid_d = out_valid_q;
      in_clke = 1'b0;
      out_clke = 1'b0;

      if (~en_i) begin
         in_addr_d = 'd0;
         out_addr_d = 'd0;
         out_valid_d = 1'b0;
      end else begin
         if (in_valid_i & ~full) begin
            in_addr_d = in_addr_q + 1;
            in_clke = 1'b1;
         end

         if (~empty | out_valid_q) begin
            if (~out_valid_q) begin
               out_addr_d = out_addr_q + 1;
               out_valid_d = 1'b1;
               out_clke = 1'b1;
            end else if (out_ready_i) begin
               if (~empty) begin
                  out_addr_d = out_addr_q + 1;
                  out_clke = 1'b1;
               end else begin
                  out_valid_d = 1'b0;
               end
            end
         end
      end
   end

endmodule
