//wb_sdio_device.v
/*
Distributed under the MIT license.
Copyright (c) 2015 Dave McCoy (dave.mccoy@cospandesign.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

/*
  Set the Vendor ID (Hexidecimal 64-bit Number)
  SDB_VENDOR_ID:0x800000000000C594

  Set the Device ID (Hexcidecimal 32-bit Number)
  SDB_DEVICE_ID:0x800000000000C594

  Set the version of the Core XX.XXX.XXX Example: 01.000.000
  SDB_CORE_VERSION:00.000.001

  Set the Device Name: 19 UNICODE characters
  SDB_NAME:wb_sdio_device

  Set the class of the device (16 bits) Set as 0
  SDB_ABI_CLASS:0

  Set the ABI Major Version: (8-bits)
  SDB_ABI_VERSION_MAJOR:0x24

  Set the ABI Minor Version (8-bits)
  SDB_ABI_VERSION_MINOR:0x01

  Set the Module URL (63 Unicode Characters)
  SDB_MODULE_URL:http://www.example.com

  Set the date of module YYYY/MM/DD
  SDB_DATE:2015/10/03

  Device is executable (True/False)
  SDB_EXECUTABLE:True

  Device is readable (True/False)
  SDB_READABLE:True

  Device is writeable (True/False)
  SDB_WRITEABLE:True

  Device Size: Number of Registers
  SDB_SIZE:3
*/

`define     BUFFER_OFFSET 32'h00000400

`define     BUFFER_EXP    10
`define     BUFFER_SIZE   2**(`BUFFER_EXP)

`define     MEM_TIMEOUT   1

`define     CNTRL_BIT_ENABLE          0
`define     CNTRL_BIT_INTERRUPT       1
`define     CNTRL_BIT_SEND_INTERRUPT  2


module wb_sdio_device (
  input               clk,
  input               rst,

  //Add signals to control your device here

  //Wishbone Bus Signals
  input               i_wbs_we,
  input               i_wbs_cyc,
  input       [3:0]   i_wbs_sel,
  input       [31:0]  i_wbs_dat,
  input               i_wbs_stb,
  output  reg         o_wbs_ack,
  output  reg [31:0]  o_wbs_dat,
  input       [31:0]  i_wbs_adr,

  //This interrupt can be controlled from this module or a submodule
  output  reg         o_wbs_int,
  //output              o_wbs_int

  //SDIO Physical Interface
  input               i_phy_sd_clk,
  inout               io_phy_sd_cmd,
  inout       [3:0]   io_phy_sd_data
);

//Local Parameters
localparam     CONTROL  = 32'h00000000;
localparam     STATUS   = 32'h00000001;
localparam     ADDR_2   = 32'h00000002;

reg     [31:0]    control;
wire              enable_sdio;
wire              enable_interrupt;

//Local Registers/Wires
wire              pll_locked;
wire              sd_clk;
wire              sd_clk_x2;

wire              sd_cmd_dir;
wire              sd_cmd_in;
wire              sd_cmd_out;


wire              sd_data_dir;
wire    [7:0]     sd_data_in;
wire    [7:0]     sd_data_out;

wire              fbr1_csa_en;
wire    [3:0]     fbr1_pwr_mode;
wire    [15:0]    fbr1_block_size;

wire              fbr2_csa_en;
wire    [3:0]     fbr2_pwr_mode;
wire    [15:0]    fbr2_block_size;

wire              fbr3_csa_en;
wire    [3:0]     fbr3_pwr_mode;
wire    [15:0]    fbr3_block_size;

wire              fbr4_csa_en;
wire    [3:0]     fbr4_pwr_mode;
wire    [15:0]    fbr4_block_size;

wire              fbr5_csa_en;
wire    [3:0]     fbr5_pwr_mode;
wire    [15:0]    fbr5_block_size;

wire              fbr6_csa_en;
wire    [3:0]     fbr6_pwr_mode;
wire    [15:0]    fbr6_block_size;

wire              fbr7_csa_en;
wire    [3:0]     fbr7_pwr_mode;
wire    [15:0]    fbr7_block_size;

wire    [7:0]     function_enable;
wire    [7:0]     function_ready;
wire    [2:0]     function_abort_stb;
wire    [7:0]     function_exec_status;
wire    [7:0]     function_ready_for_data;

wire              function_inc_addr;
wire              function_bock_mode;

wire              func_wr_stb   [0:8];
wire    [7:0]     func_wr_data  [0:8];
wire              func_rd_stb   [0:8];
wire    [7:0]     func_rd_data  [0:8];
wire              func_hst_rdy  [0:8];
wire              func_com_rdy  [0:8];
wire              func_activate [0:8];

wire    [7:0]     function_interrupt;
wire              func_inc_addr;
wire    [3:0]     func_num;
wire              func_write_flag;
wire              func_rd_after_wr;
wire    [17:0]    func_addr;
wire    [12:0]    func_data_count;
wire              func_block_mode;

//Function Specific Interface
wire              sdio_func_ready;
wire              sdio_func_int_pend;
wire              sdio_func_busy;
wire              sdio_func_exec_sts;


wire              local_buffer_en;
wire    [9:0]     local_buffer_addr;

wire              enable_interrupts;
wire              request_interrupt;

reg               mem_write_en;
reg     [31:0]    mem_data_in;
wire    [31:0]    mem_data_out;

reg     [1:0]     mem_sleep;
reg               prev_stb;
wire              posedge_stb;

//Submodules

//Possibly replace with a generate statement using an input parameter
`ifdef COCOTB_SIMULATION
sd_dev_platform_cocotb sdio_dev_plat(
  .clk            (clk                        ),
  .rst            (rst                        ),

  .o_locked       (pll_locked                 ),

  .o_sd_clk       (sd_clk                     ),
  .o_sd_clk_x2    (sd_clk_x2                  ),

  .i_sd_cmd_dir   (sd_cmd_dir                 ),
  .o_sd_cmd_in    (sd_cmd_in                  ),
  .i_sd_cmd_out   (sd_cmd_out                 ),

  .i_sd_data_dir  (sd_data_dir                ),
  .o_sd_data_in   (sd_data_in                 ),
  .i_sd_data_out  (sd_data_out                ),

  .i_phy_clk      (i_phy_sd_clk               ),
  .io_phy_sd_cmd  (io_phy_sd_cmd              ),
  .io_phy_sd_data (io_phy_sd_data             )
);
`else
//Spartan 6 Platform
sd_dev_platform_spartan6 #(
  .OUTPUT_DELAY   (63                         ),
  .INPUT_DELAY    (63                         )
)sdio_dev_plat (
  .clk            (clk                        ),
  .rst            (rst                        ),

  .o_locked       (pll_locked                 ),

  .o_sd_clk       (sd_clk                     ),
  .o_sd_clk_x2    (sd_clk_x2                  ),

  .i_sd_cmd_dir   (sd_cmd_dir                 ),
  .o_sd_cmd_in    (sd_cmd_in                  ),
  .i_sd_cmd_out   (sd_cmd_out                 ),

  .i_sd_data_dir  (sd_data_dir                ),
  .o_sd_data_in   (sd_data_in                 ),
  .i_sd_data_out  (sd_data_out                ),

  .i_phy_clk      (i_phy_sd_clk               ),
  .io_phy_sd_cmd  (io_phy_sd_cmd              ),
  .io_phy_sd_data (io_phy_sd_data             )
);
`endif

sdio_device_stack sdio_device (
  .sdio_clk             (sd_clk               ),
  .sdio_clk_x2          (sd_clk_x2            ),
  .rst                  (rst   || !pll_locked ),

  // Function Interfacee From CIA
  .o_fbr1_csa_en        (fbr1_csa_en          ),
  .o_fbr1_pwr_mode      (fbr1_pwr_mode        ),
  .o_fbr1_block_size    (fbr1_block_size      ),

  .o_fbr2_csa_en        (fbr2_csa_en          ),
  .o_fbr2_pwr_mode      (fbr2_pwr_mode        ),
  .o_fbr2_block_size    (fbr2_block_size      ),

  .o_fbr3_csa_en        (fbr3_csa_en          ),
  .o_fbr3_pwr_mode      (fbr3_pwr_mode        ),
  .o_fbr3_block_size    (fbr3_block_size      ),

  .o_fbr4_csa_en        (fbr4_csa_en          ),
  .o_fbr4_pwr_mode      (fbr4_pwr_mode        ),
  .o_fbr4_block_size    (fbr4_block_size      ),

  .o_fbr5_csa_en        (fbr5_csa_en          ),
  .o_fbr5_pwr_mode      (fbr5_pwr_mode        ),
  .o_fbr5_block_size    (fbr5_block_size      ),

  .o_fbr6_csa_en        (fbr6_csa_en          ),
  .o_fbr6_pwr_mode      (fbr6_pwr_mode        ),
  .o_fbr6_block_size    (fbr6_block_size      ),

  .o_fbr7_csa_en        (fbr7_csa_en          ),
  .o_fbr7_pwr_mode      (fbr7_pwr_mode        ),
  .o_fbr7_block_size    (fbr7_block_size      ),

  //Data Interface

  //Function 1 Interface
  .o_func1_wr_stb       (func_wr_stb[1]       ),
  .o_func1_wr_data      (func_wr_data[1]      ),
  .i_func1_rd_stb       (func_rd_stb[1]       ),
  .i_func1_rd_data      (func_rd_data[1]      ),
  .o_func1_hst_rdy      (func_hst_rdy[1]      ),
  .i_func1_com_rdy      (func_com_rdy[1]      ),
  .o_func1_activate     (func_activate[1]     ),

  //Function 2 Interface
  .o_func2_wr_stb       (func_wr_stb[2]       ),
  .o_func2_wr_data      (func_wr_data[2]      ),
  .i_func2_rd_stb       (func_rd_stb[2]       ),
  .i_func2_rd_data      (func_rd_data[2]      ),
  .o_func2_hst_rdy      (func_hst_rdy[2]      ),
  .i_func2_com_rdy      (func_com_rdy[2]      ),
  .o_func2_activate     (func_activate[2]     ),

  //Function 3 Interface
  .o_func3_wr_stb       (func_wr_stb[3]       ),
  .o_func3_wr_data      (func_wr_data[3]      ),
  .i_func3_rd_stb       (func_rd_stb[3]       ),
  .i_func3_rd_data      (func_rd_data[3]      ),
  .o_func3_hst_rdy      (func_hst_rdy[3]      ),
  .i_func3_com_rdy      (func_com_rdy[3]      ),
  .o_func3_activate     (func_activate[3]     ),

  //Function 4 Interface
  .o_func4_wr_stb       (func_wr_stb[4]       ),
  .o_func4_wr_data      (func_wr_data[4]      ),
  .i_func4_rd_stb       (func_rd_stb[4]       ),
  .i_func4_rd_data      (func_rd_data[4]      ),
  .o_func4_hst_rdy      (func_hst_rdy[4]      ),
  .i_func4_com_rdy      (func_com_rdy[4]      ),
  .o_func4_activate     (func_activate[4]     ),

  //Function 5 Interface
  .o_func5_wr_stb       (func_wr_stb[5]       ),
  .o_func5_wr_data      (func_wr_data[5]      ),
  .i_func5_rd_stb       (func_rd_stb[5]       ),
  .i_func5_rd_data      (func_rd_data[5]      ),
  .o_func5_hst_rdy      (func_hst_rdy[5]      ),
  .i_func5_com_rdy      (func_com_rdy[5]      ),
  .o_func5_activate     (func_activate[5]     ),

  //Function 6 Interface
  .o_func6_wr_stb       (func_wr_stb[6]       ),
  .o_func6_wr_data      (func_wr_data[6]      ),
  .i_func6_rd_stb       (func_rd_stb[6]       ),
  .i_func6_rd_data      (func_rd_data[6]      ),
  .o_func6_hst_rdy      (func_hst_rdy[6]      ),
  .i_func6_com_rdy      (func_com_rdy[6]      ),
  .o_func6_activate     (func_activate[6]     ),

  //Function 7 Interface
  .o_func7_wr_stb       (func_wr_stb[7]       ),
  .o_func7_wr_data      (func_wr_data[7]      ),
  .i_func7_rd_stb       (func_rd_stb[7]       ),
  .i_func7_rd_data      (func_rd_data[7]      ),
  .o_func7_hst_rdy      (func_hst_rdy[7]      ),
  .i_func7_com_rdy      (func_com_rdy[7]      ),
  .o_func7_activate     (func_activate[7]     ),

  //Memory Interface
  .o_mem_wr_stb         (func_wr_stb[8]       ),
  .o_mem_wr_data        (func_wr_data[8]      ),
  .i_mem_rd_stb         (func_rd_stb[8]       ),
  .i_mem_rd_data        (func_rd_data[8]      ),
  .o_mem_hst_rdy        (func_hst_rdy[8]      ),
  .i_mem_com_rdy        (func_com_rdy[8]      ),
  .o_mem_activate       (func_activate[8]     ),


  //Cross Function Signals
  .o_func_enable        (function_enable      ),
  .i_func_ready         (function_ready       ),
  .o_func_abort_stb     (function_abort_stb   ),
  .i_func_exec_status   (function_exec_status ),
  .i_func_ready_for_data(function_ready_for_data  ),

  .o_func_inc_addr      (func_inc_addr        ),
  .o_func_block_mode    (func_block_mode      ),
  .o_func_write_flag    (func_write_flag      ),
  .o_func_num           (func_num             ),
  .o_func_rd_after_wr   (func_rd_after_wr     ),
  .o_func_addr          (func_addr            ),
  .o_func_data_count    (func_data_count      ),

  .i_interrupt          (function_interrupt   ),

  //Platform Interface
  .o_sd_cmd_dir         (sd_cmd_dir           ),
  .i_sd_cmd_in          (sd_cmd_in            ),
  .o_sd_cmd_out         (sd_cmd_out           ),

  .o_sd_data_dir        (sd_data_dir          ),
  .o_sd_data_out        (sd_data_out          ),
  .i_sd_data_in         (sd_data_in           )

);

sdio_memory_function #(
  .FUNC_NUM             (1                    ),
  .MEM_EXP              (`BUFFER_EXP          )
)memory_function(
  .clk                  (clk                  ),
  .sdio_clk             (sd_clk               ),
  .rst                  (rst   || !pll_locked ),

  //Boiler Plate SDIO Function Interface
  .i_csa_en             (fbr1_csa_en          ),
  .i_pwr_mode           (fbr1_pwr_mode        ),
  .i_block_size         (fbr1_block_size      ),
  .i_enable             (function_enable[1]   ),
  .o_ready              (sdio_func_ready      ),
  .i_abort              (function_abort_stb[1]),
  .o_busy               (sdio_func_busy       ),
  .o_execution_status   (sdio_func_exec_sts   ),
  .o_ready_for_data     (sdio_func_ready_for_data),

  .i_activate           (func_activate[1]     ),
  .o_finished           (sdio_func_finished   ),
  .i_inc_addr           (func_inc_addr        ),
  .i_block_mode         (func_block_mode      ),

  .i_write_flag         (func_write_flag      ),
  .i_rd_after_wr        (func_rd_after_wr     ),
  .i_addr               (func_addr            ),
  .i_write_data         (func_wr_data[1]      ),
  .o_read_data          (func_rd_data[1]      ),
  .o_data_rdy           (func_com_rdy[1]      ),
  .i_data_stb           (func_wr_stb[1]       ),
  .i_host_rdy           (func_hst_rdy[1]      ),
  .i_data_count         (func_data_count      ),
  .o_data_stb           (func_rd_stb[1]       ),

  .o_interrupt          (sdio_func_interrupt  ),

  //User Interface
  .i_en_in_interrupts   (enable_interrupts    ),

  //Memory
  .i_user_write_en      (mem_write_en         ),
  .i_user_address       (local_buffer_addr    ),
  .i_user_data_in       (mem_data_in          ),
  .o_user_data_out      (mem_data_out         ),


  //Control
  .i_request_interrupt  (request_interrupt    )
);

//Asynchronous Logic
assign  function_ready          = {6'b000000, sdio_func_ready,          1'b0};
assign  function_exec_status    = {6'b000000, sdio_func_exec_sts,       1'b0};
assign  function_ready_for_data = {6'b000000, sdio_func_ready_for_data, 1'b0};
assign  function_interrupt      = {6'b000000, sdio_func_interrupt,      1'b0};


assign  local_buffer_en         = ((i_wbs_adr >= `BUFFER_OFFSET) &&
                                    (i_wbs_adr < (`BUFFER_OFFSET + (`BUFFER_SIZE))));
assign  local_buffer_addr       = local_buffer_en ? (i_wbs_adr - `BUFFER_OFFSET) : 10'h000;
assign  posedge_stb             = i_wbs_stb && !prev_stb;

assign  enable_sdio             = control[`CNTRL_BIT_ENABLE];
assign  enable_interrupts       = control[`CNTRL_BIT_INTERRUPT];
assign  request_interrupt       = control[`CNTRL_BIT_SEND_INTERRUPT];



//Synchronous Logic
always @ (posedge clk) begin
  if (rst) begin
    o_wbs_dat                 <= 32'h0;
    o_wbs_ack                 <= 0;
    o_wbs_int                 <= 0;
    mem_data_in               <= 0;
    mem_write_en              <= 0;
    control                   <= 0;
    control[`CNTRL_BIT_ENABLE]<=  1;  //Enable SDIO At the beginning
    mem_sleep                 <= 0;
  end
  else begin
    //De-assert Strobes
    //when the master acks our ack, then put our ack down
    if (o_wbs_ack && ~i_wbs_stb)begin
      o_wbs_ack               <= 0;
      mem_write_en            <=  0;
    end

    if (mem_sleep < `MEM_TIMEOUT) begin
      mem_sleep               <=  mem_sleep + 1;
    end

    if (i_wbs_stb && i_wbs_cyc) begin
      //master is requesting somethign
      if (!o_wbs_ack) begin
        if (i_wbs_we) begin
          //write request
          mem_sleep           <=  `MEM_TIMEOUT;
          case (i_wbs_adr)
            CONTROL: begin
              control         <=  i_wbs_dat;
            end
            ADDR_2: begin
            end
            default: begin
              if (local_buffer_en) begin
                mem_write_en  <=  1;
                mem_data_in   <=  i_wbs_dat;
                
              end
            end
          endcase
        end
        else begin
          //read request
          case (i_wbs_adr)
            CONTROL: begin
              o_wbs_dat <= control;
            end
            STATUS: begin
              o_wbs_dat <= STATUS;
            end
            ADDR_2: begin
              o_wbs_dat <= ADDR_2;
            end
            default: begin
              if (local_buffer_en) begin
                if (posedge_stb) begin
                  mem_sleep <=  2'h0;
                end
                o_wbs_dat   <=  mem_data_out;
              end
            end
          endcase
        end
        if (local_buffer_en) begin
          if (!posedge_stb && (mem_sleep == `MEM_TIMEOUT)) begin
            o_wbs_ack         <= 1;
          end
        end
        else begin
          o_wbs_ack         <= 1;
        end
      end
    end
    prev_stb                <=  i_wbs_stb;
  end
end

endmodule
