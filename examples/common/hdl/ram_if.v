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

`define min(a,b)((a) < (b) ? (a) : (b))

module ram_if
  #(parameter RAM_SIZE = 'd1024) // byte size
   (
    input                            clk_i,
    input                            rstn_i,
    // While rstn_i is low (active low), the module shall be reset

    // ---- to/from application module --------------
    input                            en_i,
    // When en_i changes from low to high, a new read/program operation shall start.
    // When en_i changes from high to low, the current read/program operation shall end.
    input [ceil_log2(RAM_SIZE)-1:0]  start_addr_i,
    input [ceil_log2(RAM_SIZE)-1:0]  end_addr_i,
    //    input [7:0]                      out_data_i,
    // While out_valid_i is high, the out_data_i shall be valid.
    input                            out_valid_i,
    // When both en_i and out_valid_i change from low to high, a new programming
    //   operation shall start.
    output                           out_ready_o,
    // While en_i is high and when both out_valid_i and out_ready_o are high, out_data_i
    //   shall be consumed.
    //    output [7:0]                     in_data_o,
    // While in_valid_o is high, the in_data_o shall be valid.
    output                           in_valid_o,
    // While en_i is high and when both in_valid_o and in_ready_i are high, in_data_o
    //   shall be consumed by application module.
    // in_valid_o shall be high only for one clk_i period.
    input                            in_ready_i,
    // When both en_i and in_ready_i change from low to high, a new read
    //   operation shall start.
    input                            clear_status_i,
    // While status_o reports an error or the end of programming/read operation (4'bF),
    //   when clear_status_i is high, status_o shall be cleared to 4'h0.
    output [3:0]                     status_o,
    // status_o shall report an error (4'h5, 4'h7 or 4'h8) or the end of a correct
    //   programming/read operation (4'hF), otherwise shall be 4'h0.

    output                           ram_clke_o,
    output                           ram_we_o,
    output [ceil_log2(RAM_SIZE)-1:0] ram_addr_o
    );

   function integer ceil_log2;
      input integer                  arg;
      begin
         ceil_log2 = 0;
         while ((2 ** ceil_log2) < arg)
           ceil_log2 = ceil_log2 + 1;
      end
   endfunction

   localparam [1:0] IDLE_STATE = 'd0,
                    READ_RAM_STATE = 'd1,
                    WRITE_RAM_STATE = 'd2;
   localparam [3:0] STATUS_OK = 4'h0,
                    STATUS_errADDRESS = 4'h8,
                    STATUS_errNOTDONE = 4'h9,
                    STATUS_END = 4'hF;

   reg [1:0]        state_q, state_d;
   reg [3:0]        status_q, status_d;
   reg              mem_valid_q, mem_valid_d;
   reg [ceil_log2(RAM_SIZE)+1-1:0] mem_addr_q, mem_addr_d;

   always @(posedge clk_i or negedge rstn_i) begin
      if (~rstn_i) begin
         state_q <= IDLE_STATE;
         status_q <= STATUS_OK;
         mem_valid_q <= 1'b0;
         mem_addr_q <= 'd0;
      end else begin
         state_q <= state_d;
         status_q <= status_d;
         mem_valid_q <= mem_valid_d;
         mem_addr_q <= mem_addr_d;
      end
   end

   reg out_ready;
   reg ram_clke;
   reg ram_we;

   assign out_ready_o = out_ready;
   assign in_valid_o = mem_valid_q;
   assign status_o = status_q;
   assign ram_clke_o = ram_clke;
   assign ram_we_o = ram_we;
   assign ram_addr_o = mem_addr_q[ceil_log2(RAM_SIZE)-1:0];

   always @(/*AS*/clear_status_i or en_i or end_addr_i or in_ready_i
            or mem_addr_q or mem_valid_q or out_valid_i
            or start_addr_i or state_q or status_q) begin
      state_d = state_q;
      status_d = status_q;
      mem_valid_d = mem_valid_q;
      mem_addr_d = mem_addr_q;
      out_ready = 1'b0;
      ram_clke = 1'b0;
      ram_we = 1'b0;

      case (state_q) 
        IDLE_STATE: begin
           if (en_i == 1'b1 && status_q == STATUS_OK) begin
              if (out_valid_i)
                state_d = WRITE_RAM_STATE;
              else if (in_ready_i)
                state_d = READ_RAM_STATE;
           end
           if (clear_status_i)
             status_d = STATUS_OK;
           mem_valid_d = 1'b0;
           mem_addr_d = {1'b0, start_addr_i};
        end
        WRITE_RAM_STATE: begin
           if (en_i == 1'b1 && mem_addr_q <= {1'b0, end_addr_i}) begin
              ram_we = 1'b1;
              out_ready = 1'b1;
              if (out_valid_i) begin
                 mem_addr_d = mem_addr_q + 1;
                 ram_clke = 1'b1;
              end
           end else begin
              if (status_q != STATUS_errADDRESS) begin
                 if (mem_addr_q <= {1'b0, end_addr_i})
                   status_d = STATUS_errNOTDONE;
                 else
                   status_d = STATUS_END;
              end
              if (en_i & out_valid_i)
                status_d = STATUS_errADDRESS;
              if (~en_i)
                state_d = IDLE_STATE;
           end
        end
        READ_RAM_STATE: begin
           if (en_i == 1'b1 && (mem_addr_q <= {1'b0, end_addr_i} || mem_valid_q == 1'b1)) begin
              if (~mem_valid_q) begin
                 mem_valid_d = 1'b1;
                 mem_addr_d = mem_addr_q + 1;
                 ram_clke = 1'b1;
              end else if (in_ready_i) begin
                 if (mem_addr_q <= {1'b0, end_addr_i}) begin
                    mem_addr_d = mem_addr_q + 1;
                    ram_clke = 1'b1;
                 end else begin
                    mem_valid_d = 1'b0;
                 end
              end
           end else begin
              state_d = IDLE_STATE;
              status_d = STATUS_END;
           end
        end
        default: begin
           state_d = IDLE_STATE;
        end
      endcase
   end

endmodule
