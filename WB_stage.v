`include "mycpu.h"

module wb_stage(
    input                           clk           ,
    input                           reset         ,
    //allowin
    output                          ws_allowin    ,
    //from ms
    input                           ms_to_ws_valid,
    input  [`MS_TO_WS_BUS_WD -1:0]  ms_to_ws_bus  ,
    
    input [`CP0_TO_WS_BUS_WD-1:0] cp0_to_ws_bus,        //cp0_to_ws_bus
    input         exception,
    //to rf: for write back
    output [`WS_TO_RF_BUS_WD -1:0]  ws_to_rf_bus  ,
    //forward_bus
    output [`FORWARD_BUS_WD  -1:0] forward_ws_to_ds_bus,
    //trace debug interface
    output [31:0] debug_wb_pc     ,
    output [ 3:0] debug_wb_rf_wen ,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata,
    
    output [`WS_TO_CP0_BUS_WD-1:0] ws_to_cp0_bus,        //ws_to_cp0_bus
    output        ws_to_es_ex,
    output        ws_mtc0_entryhi,

    output        tlbrw,
    output [31:0] refetch_pc,
    output        ws_tlb_refill,

    //TLB write and read
    //write port
    output                      we,     //write enable
    output [               3:0] w_index,    //TLBNUM==16
    output [              18:0] w_vpn2,
    output [               7:0] w_asid,
    output                      w_g,
    output [              19:0] w_pfn0,
    output [               2:0] w_c0,
    output                      w_d0,
    output                      w_v0,
    output [              19:0] w_pfn1,
    output [               2:0] w_c1,
    output                      w_d1,
    output                      w_v1,

    //read port
    output [               3:0] r_index,    //TLBNUM==16    
    input  [              18:0] r_vpn2,
    input  [               7:0] r_asid,
    input                       r_g,
    input  [              19:0] r_pfn0,
    input  [               2:0] r_c0,
    input                       r_d0,
    input                       r_v0,
    input  [              19:0] r_pfn1,
    input  [               2:0] r_c1,
    input                       r_d1,
    input                       r_v1
);

reg         ws_valid;
wire        ws_ready_go;

reg [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus_r;
wire        ws_ms_tlb_refill;
wire        ws_tlbp_found ;
wire [ 3:0] ws_tlbp_index ;
wire        ws_tlbr_op    ;       //for tlbr
wire        ws_tlbwi_op   ;       //for tlbwi
wire        ws_tlbp_op    ;       //for tlbp
wire        ws_ms_ex      ;
wire        ws_ms_bd      ;
wire [31:0] ws_ms_badvaddr;       
wire [ 4:0] ws_ms_excode  ;
wire        ws_eret_op    ;       //for eret
wire        ws_mfc0_op    ;       //for mfc0
wire        ws_mtc0_op    ;       //for mtc0
wire [ 7:0] ws_c0_addr    ;       //for mfc0 mtc0
wire [ 3:0] ws_gr_we;
wire [ 4:0] ws_dest;
wire [31:0] ws_final_result;
wire [31:0] ws_pc;
assign {ws_ms_tlb_refill, //131
        ws_tlbp_found  ,  //130
        ws_tlbp_index  ,  //129:126
        ws_tlbr_op     ,  //125
        ws_tlbwi_op    ,  //124
        ws_tlbp_op     ,  //123
        ws_ms_ex       ,  //122
        ws_ms_bd       ,  //121
        ws_ms_badvaddr ,  //120:89     
        ws_ms_excode   ,  //88:84
        ws_eret_op     ,  //83
        ws_mfc0_op     ,  //82
        ws_mtc0_op     ,  //81
        ws_c0_addr     ,  //80:73
        ws_gr_we       ,  //72:69
        ws_dest        ,  //68:64
        ws_final_result,  //63:32
        ws_pc             //31:0
       } = ms_to_ws_bus_r;

wire [3 :0] rf_we;
wire [4 :0] rf_waddr;
wire [31:0] rf_wdata;
assign ws_to_rf_bus = {rf_we   ,  //40:37
                       rf_waddr,  //36:32
                       rf_wdata   //31:0
                      };

assign ws_ready_go = 1'b1;
assign ws_allowin  = !ws_valid || ws_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ws_valid <= 1'b0;
    end
 //   else if (exception | ws_eret_op) begin
 //       ws_valid <= 1'b0;
 //   end
    else if (ws_allowin) begin
        ws_valid <= ms_to_ws_valid;
    end

    if (ms_to_ws_valid && ws_allowin) begin
        ms_to_ws_bus_r <= ms_to_ws_bus;
    end
end

wire [31:0] ws_c0_index;
wire [31:0] ws_c0_entrylo0;
wire [31:0] ws_c0_entrylo1;
wire [31:0] ws_c0_entryhi;
wire [31:0] ws_c0_status;
wire [31:0] ws_c0_cause;
wire [31:0] ws_c0_epc;
wire [31:0] ws_c0_badvaddr;
wire [31:0] ws_c0_count;
wire [31:0] ws_c0_compare;

wire        tlbp_we;
wire [31:0] index_data;
wire        tlbr_we;
wire [31:0] lo0_data;
wire [31:0] lo1_data;
wire [31:0] hi_data;
wire        mtc0_we;
//wire        ws_tlb_refill;
wire        ws_ex;
wire        ws_bd;
wire [31:0] ws_badvaddr;       
wire [ 4:0] ws_excode;  

assign rf_we    = ws_gr_we&{4{ws_valid}} & {4{~ws_ex}};       //&&&~ws_ex
assign rf_waddr = ws_dest;
assign rf_wdata = (ws_mfc0_op && ws_c0_addr==`CR_STATUS)    ? ws_c0_status   :
                  (ws_mfc0_op && ws_c0_addr==`CR_CAUSE)     ? ws_c0_cause    :
                  (ws_mfc0_op && ws_c0_addr==`CR_EPC)       ? ws_c0_epc      :
                  (ws_mfc0_op && ws_c0_addr==`CR_BADVADDR)  ? ws_c0_badvaddr :
                  (ws_mfc0_op && ws_c0_addr==`CR_COUNT)     ? ws_c0_count    :
                  (ws_mfc0_op && ws_c0_addr==`CR_COMPARE)   ? ws_c0_compare  :
                  (ws_mfc0_op && ws_c0_addr==`CR_INDEX)     ? ws_c0_index    :
                  (ws_mfc0_op && ws_c0_addr==`CR_ENTRYLO0)  ? ws_c0_entrylo0 :
                  (ws_mfc0_op && ws_c0_addr==`CR_ENTRYLO1)  ? ws_c0_entrylo1 :
                  (ws_mfc0_op && ws_c0_addr==`CR_ENTRYHI)   ? ws_c0_entryhi  :
                                                              ws_final_result;

//forward
assign forward_ws_to_ds_bus={rf_we&{4{ws_valid}},rf_waddr&{5{ws_valid}},rf_wdata};

assign tlbrw = (ws_tlbr_op | ws_tlbwi_op)&ws_valid;
assign refetch_pc = ws_pc + 32'h4;

//TLB write
assign we = ws_valid && ws_tlbwi_op && !ws_ex;
assign w_index = ws_c0_index[3:0];
assign w_vpn2 = ws_c0_entryhi[31:13];
assign w_asid = ws_c0_entryhi[7:0];
assign w_g = ws_c0_entrylo0[0] & ws_c0_entrylo1[0];
assign w_pfn0 = ws_c0_entrylo0[25:6];
assign w_c0 = ws_c0_entrylo0[5:3];
assign w_d0 = ws_c0_entrylo0[2];
assign w_v0 = ws_c0_entrylo0[1];
assign w_pfn1 = ws_c0_entrylo1[25:6];
assign w_c1 = ws_c0_entrylo1[5:3];
assign w_d1 = ws_c0_entrylo1[2];
assign w_v1 = ws_c0_entrylo1[1];

//TLB read
assign r_index = ws_c0_index[3:0];
assign tlbr_we = ws_valid && ws_tlbr_op && !ws_ex;
assign lo0_data = {6'b0,r_pfn0,r_c0,r_d0,r_v0,r_g};
assign lo1_data = {6'b0,r_pfn1,r_c1,r_d1,r_v1,r_g};
assign hi_data  = {r_vpn2,5'b0,r_asid};

//TLB search
assign tlbp_we = ws_valid && ws_tlbp_op && !ws_ex;
assign index_data = {~ws_tlbp_found,27'b0,ws_tlbp_index};

//ws_to_cp0_bus
assign ws_tlb_refill = ws_ms_tlb_refill&ws_valid;
assign mtc0_we = ws_valid && ws_mtc0_op && !ws_ex;
assign ws_ex = ws_ms_ex;
assign ws_bd = ws_ms_bd;
assign ws_badvaddr = ws_ms_badvaddr;
assign ws_excode = ws_ms_excode;

assign ws_to_es_ex = (ws_ex|ws_eret_op|ws_tlbr_op|ws_tlbwi_op)&ws_valid;  
assign ws_mtc0_entryhi = ws_mtc0_op & (ws_c0_addr==`CR_ENTRYHI) & ws_valid;  

assign ws_to_cp0_bus = {tlbp_we,        //242
                        index_data,     //241:210
                        tlbr_we,        //209
                        lo0_data,       //208:177
                        lo1_data,       //176:145
                        hi_data,        //144:113
                        mtc0_we,        //112
                        ws_ex&ws_valid,          //111
                        ws_bd,          //110
                        ws_pc,          //109:78
                        ws_badvaddr,    //77:46    
                        ws_excode,      //45:41
                        ws_eret_op&ws_valid,     //40:40
                        ws_c0_addr,     //39:32
                        ws_final_result //31:0
                        };

//cp0_to_ws_bus
assign {ws_c0_index,
        ws_c0_entrylo0,
        ws_c0_entrylo1,
        ws_c0_entryhi,
        ws_c0_status,
        ws_c0_cause,
        ws_c0_epc,
        ws_c0_badvaddr,
        ws_c0_count,
        ws_c0_compare
        } = cp0_to_ws_bus;


// debug info generate
assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_wen   = rf_we;
assign debug_wb_rf_wnum  = ws_dest;
assign debug_wb_rf_wdata = rf_wdata; //ws_final_result

endmodule
