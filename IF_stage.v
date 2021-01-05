`include "mycpu.h"

module if_stage(
    input                          clk            ,
    input                          reset          ,
    //allwoin
    input                          ds_allowin     ,
    //brbus
    input  [`BR_BUS_WD       -1:0] br_bus         ,
    input                          br_leaving     ,
    
    input         exception,
    input         eret,
    input         tlbrw,
    input [31:0]  refetch_pc, 
    input [31:0]  cp0_epc,
    input         has_int,
    input         ws_tlb_refill,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // inst sram interface
    output        inst_sram_req,
    output        inst_sram_wr,
    output [ 1:0] inst_sram_size,
    output [ 3:0] inst_sram_wstrb,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input         inst_sram_addr_ok,
    input         inst_sram_data_ok,
    input  [31:0] inst_sram_rdata,

    //TLB search port 0
    output [              18:0] s0_vpn2,
    output                      s0_odd_page,
    output [               7:0] s0_asid,
    input                       s0_found,
    input  [               3:0] s0_index,       //TLBNUM=16
    input  [              19:0] s0_pfn,
    input  [               2:0] s0_c,
    input                       s0_d,
    input                       s0_v,
    input  [              31:0] cp0_entryhi
);

reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;
wire        to_fs_ready_go; //pre-IF ready_go

wire        mapped;

wire [31:0] seq_pc;
wire [31:0] nextpc;

wire [31:0] fs_inst;
reg  [31:0] fs_pc;
reg  [31:0] fs_inst_reg;    //
reg         fs_inst_reg_v;  // fs inst reg valid
reg         fs_cancel_d;    // fs cancel delete inst
reg  [34:0] br_bus_r;       //br_bus regs
reg         br_bus_r_v;     //br_bus regs valid
reg         bd_done;

assign mapped = (nextpc[31:28]==4'h8 || nextpc[31:28]==4'h9 || nextpc[31:28]==4'ha || nextpc[31:28]==4'hb) ? 1'b0 : 1'b1;

wire        pre_fs_tlb_refill;
wire        pre_fs_ex;
//wire        pre_fs_bd;
wire [31:0] pre_fs_badvaddr;       
wire [ 4:0] pre_fs_excode;

assign inst_sram_wr = 1'b0;
assign inst_sram_size = 2'd2;
assign inst_sram_wstrb = 4'b0;
assign inst_sram_addr = (pre_fs_ex) ? 32'h0 : 
                        (mapped==1'b0) ? nextpc : {s0_pfn,nextpc[11:0]};
assign inst_sram_wdata = 32'b0;


assign pre_fs_tlb_refill = (s0_found==1'b0&&mapped==1'b1);
assign pre_fs_ex = (has_int) | (nextpc[1:0]!=2'b00) | (s0_found==1'b0&&mapped==1'b1) | (s0_found==1'b1&&s0_v==1'b0&&mapped==1'b1);                 
assign pre_fs_badvaddr = nextpc;
assign pre_fs_excode = (has_int) ? `EX_INT :
                   (fs_pc[1:0]!=2'b00) ? `EX_ADEL :
                   (s0_found==1'b0&&mapped==1'b1) ? `EX_TLBL :
                   (s0_found==1'b1&&s0_v==1'b0&&mapped==1'b1) ? `EX_TLBL 
                                    : 5'b0 ;        
wire [39:0]  pre_to_fs_bus;
assign pre_to_fs_bus = {pre_fs_tlb_refill,
                        pre_fs_ex,
                        pre_fs_badvaddr,
                        pre_fs_excode};

reg  [39:0]  pre_to_fs_bus_r;
wire        fs_tlb_refill;
wire        fs_ex;
wire        fs_bd;
wire [31:0] fs_badvaddr;       
wire [ 4:0] fs_excode;
assign {fs_tlb_refill,
        fs_ex,
        fs_badvaddr,
        fs_excode
        }= pre_to_fs_bus_r;

wire         br_stall;
wire         br_taken;
wire [ 31:0] br_target;
assign {br_stall,fs_bd,br_taken,br_target} = (br_bus_r_v==1'b1) ? br_bus_r :
                                             br_bus;    //


assign fs_to_ds_bus = {fs_tlb_refill,
                       fs_ex,
                       fs_bd,
                       fs_badvaddr,      
                       fs_excode,
                       fs_inst ,
                       fs_pc   };

//TLB
assign s0_vpn2 = nextpc[31:13];
assign s0_odd_page = nextpc[12];
assign s0_asid = cp0_entryhi[7:0];

// pre-IF stage
assign to_fs_valid  = //(exception|eret) ? 1'b0 :     //perhaps?
                      ~reset && to_fs_ready_go; //
assign seq_pc       = fs_pc + 3'h4;
assign nextpc       = ws_tlb_refill ? 32'hbfc00200 :
                      exception ? 32'hbfc00380 :
                      eret ? cp0_epc :
                      tlbrw ? refetch_pc :
                      (br_bus_r_v==1'b1 && br_taken==1'b1 && bd_done==1'b1) ? br_target :
                      (fs_bd==1'b1 && fs_valid==1'b0) ? seq_pc :
                      br_taken ? br_target : seq_pc; 
assign to_fs_ready_go = inst_sram_req & inst_sram_addr_ok;  //
assign inst_sram_req = (br_stall==1'b1) ? 1'b0 :
                        fs_allowin;      //

//br_bus regs
always @(posedge clk) begin
    if(reset) begin
        br_bus_r <= 35'b0;
        br_bus_r_v <= 1'b0;
    end
    else if(exception|eret |tlbrw) begin
        br_bus_r <= 35'b0;
        br_bus_r_v <= 1'b0;
    end
    else if(nextpc==br_target && to_fs_ready_go==1'b1 && fs_allowin==1'b1) begin
        br_bus_r_v <= 1'b0;
    end
    else if(br_leaving==1'b1) begin
        br_bus_r <= br_bus;
        br_bus_r_v <= 1'b1;
    end
end

//bd_done
always @(posedge clk) begin
    if(reset) begin
        bd_done <= 1'b0;
    end
    else if(br_leaving==1'b1 && fs_valid==1'b0) begin
        bd_done <= 1'b0;
    end
    else if(fs_bd==1'b1 && fs_valid==1'b1) begin
        bd_done <= 1'b1;
    end
end

// IF stage
assign fs_ready_go    = //(exception|eret) ? 1'b1 :
                        //(br_bus_r_v==1'b1 && to_fs_ready_go==1'b0) ? 1'b0 :
                        (fs_cancel_d==1'b1) ? 1'b0 :
                        (inst_sram_data_ok || fs_inst_reg_v);      //
assign fs_allowin     = !fs_valid || fs_ready_go && ds_allowin;
assign fs_to_ds_valid = (exception | eret |tlbrw)?1'b0: fs_valid && fs_ready_go;
always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else if (exception | eret |tlbrw) begin
       fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
    end

    if (reset) begin
        fs_pc <= 32'hbfbffffc;  //trick: to make nextpc be 0xbfc00000 during reset 
    end
    else if(ws_tlb_refill) begin 
        fs_pc <= 32'hbfc001fc;
    end 
    else if (exception) begin
        fs_pc <= 32'hbfc0037c;
    end
    else if (eret) begin
        fs_pc <= cp0_epc-32'h4;
    end
    else if(tlbrw) begin 
        fs_pc <= refetch_pc - 32'h4;
    end 
    else if (to_fs_valid && fs_allowin) begin
        fs_pc <= nextpc;
    end
    
    if (to_fs_valid && fs_allowin) begin
        pre_to_fs_bus_r <= pre_to_fs_bus;
    end
end

//fs inst reg
always @(posedge clk) begin
    if(reset) begin
        fs_inst_reg <= 32'b0;
        fs_inst_reg_v <= 1'b0;
    end
    else if(exception | eret |tlbrw) begin
        fs_inst_reg_v <= 1'b0;
    end
    else if(inst_sram_data_ok==1'b1 && ds_allowin==1'b0) begin
        fs_inst_reg <= inst_sram_rdata;
        fs_inst_reg_v <= 1'b1;
    end
    else if(fs_ready_go==1'b1 && ds_allowin==1'b1) begin
        fs_inst_reg_v <= 1'b0;
    end
end

//fs cancel delete
always @(posedge clk)begin
    if(reset) begin
        fs_cancel_d <= 1'b0;
    end
    else if((exception|eret |tlbrw) && (to_fs_valid==1'b1||(fs_allowin==1'b0&&fs_ready_go==1'b0))) begin
        fs_cancel_d <= 1'b1;
    end
    else if(inst_sram_data_ok==1'b1) begin
        fs_cancel_d <= 1'b0;
    end
end


assign fs_inst = (fs_inst_reg_v==1'b1) ? fs_inst_reg :
                 (inst_sram_data_ok) ? inst_sram_rdata : 32'b0; //

endmodule
