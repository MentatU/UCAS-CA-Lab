`include "mycpu.h"

module cp0(
    input             clk,
    input             reset,
    input [`WS_TO_CP0_BUS_WD-1:0] ws_to_cp0_bus,
    
    input      [ 5:0] ext_int_in,

    output [`CP0_TO_WS_BUS_WD-1:0] cp0_to_ws_bus,
    output            exception,
    output            eret,
    output [31:0]     cp0_epc,
    output            has_int,
    output [31:0]     cp0_entryhi
);

wire        tlbp_we;
wire [31:0] index_data;
wire        tlbr_we;
wire [31:0] lo0_data;
wire [31:0] lo1_data;
wire [31:0] hi_data;
wire        mtc0_we;
wire        wb_ex;
wire        wb_bd;
wire [31:0] wb_pc;
wire [31:0] wb_badvaddr;
wire [ 4:0] wb_excode;
wire        eret_flush;
wire [ 7:0] c0_addr;
wire [31:0] c0_wdata;
assign {tlbp_we,
        index_data,
        tlbr_we,        //209
        lo0_data,       //208:177
        lo1_data,       //176:145
        hi_data,        //144:113
        mtc0_we,        //112
        wb_ex,          //111
        wb_bd,          //110
        wb_pc,          //109:78
        wb_badvaddr,    //77:46    
        wb_excode,      //45:41
        eret_flush,     //40:40
        c0_addr,        //39:32
        c0_wdata        //31:0
        }=ws_to_cp0_bus;

assign exception = wb_ex;
assign eret = eret_flush;

////count
reg tick;
reg [31:0] c0_count;
always @(posedge clk) begin
    if(reset) tick <= 1'b0;
    else      tick <= ~tick;

    if(mtc0_we && c0_addr==`CR_COUNT)
        c0_count <= c0_wdata;
    else if (tick) 
        c0_count <= c0_count + 1'b1;
end


////compare
reg [31:0] c0_compare;
always @(posedge clk) begin
    if(mtc0_we && c0_addr==`CR_COMPARE)
        c0_compare <= c0_wdata;
end


////status
wire c0_status_bev;
assign c0_status_bev = 1'b1;

reg [ 7:0] c0_status_im;
always @(posedge clk) begin
    if(mtc0_we && c0_addr == `CR_STATUS)
        c0_status_im <= c0_wdata[15:8];
end

reg c0_status_exl;
always @(posedge clk) begin
    if(reset)
        c0_status_exl <= 1'b0;
    else if(wb_ex)
        c0_status_exl <= 1'b1;
    else if(eret_flush)
        c0_status_exl <= 1'b0;
    else if(mtc0_we && c0_addr==`CR_STATUS)
        c0_status_exl <= c0_wdata[1];
end

reg c0_status_ie;
always @(posedge clk) begin
    if(reset)
        c0_status_ie <= 1'b0;
    else if(mtc0_we && c0_addr==`CR_STATUS)
        c0_status_ie <= c0_wdata[0];
end


////cause
reg c0_cause_bd;
always @(posedge clk) begin
    if(reset)
        c0_cause_bd <= 1'b0;
    else if(wb_ex && !c0_status_exl)
        c0_cause_bd <= wb_bd;
end

reg c0_cause_ti;
wire count_eq_compare;
assign count_eq_compare = (c0_count==c0_compare);
always @(posedge clk) begin
    if(reset)
        c0_cause_ti <= 1'b0;
    else if(mtc0_we && c0_addr==`CR_COMPARE)
        c0_cause_ti <= 1'b0;
    else if(count_eq_compare)
        c0_cause_ti <= 1'b1;
end

reg [7:0] c0_cause_ip;
always @(posedge clk) begin
    if(reset)
        c0_cause_ip[7:2] <= 6'b0;
    else begin
        c0_cause_ip[7]   <= ext_int_in[5] | c0_cause_ti;
        c0_cause_ip[6:2] <= ext_int_in[4:0];
    end
end
always @(posedge clk) begin
    if(reset)
        c0_cause_ip[1:0] <= 2'b0;
    else if(mtc0_we && c0_addr==`CR_CAUSE)
        c0_cause_ip[1:0] <= c0_wdata[9:8];
end

reg [4:0] c0_cause_excode;
always @(posedge clk) begin
    if(reset)
        c0_cause_excode <= 5'b0;
    else if(wb_ex)
        c0_cause_excode <= wb_excode;
end


////epc
reg [31:0] c0_epc;
always @(posedge clk) begin
    if(wb_ex && !c0_status_exl)
        c0_epc <= wb_bd ? wb_pc - 3'h4 : wb_pc; 
    else if(mtc0_we && c0_addr==`CR_EPC)
        c0_epc <= c0_wdata;
end
assign cp0_epc = c0_epc;


////badvaddr
reg [31:0] c0_badvaddr;
always @(posedge clk) begin
    if(wb_ex && (wb_excode==`EX_ADEL || wb_excode==`EX_ADES || wb_excode==`EX_TLBL || wb_excode==`EX_TLBS || wb_excode==`EX_MOD))
        c0_badvaddr <= wb_badvaddr;
end


////index
reg c0_index_p;
always @(posedge clk) begin
    if(reset)
        c0_index_p <= 1'b0;
    else if(tlbp_we) 
        c0_index_p <= index_data[31];
end

reg [3:0] c0_index;   //TLBNUM==16
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_INDEX)
        c0_index <= c0_wdata[3:0];
    else if(tlbp_we)
        c0_index <= index_data[3:0];
end 


////entrylo0
reg [19:0] c0_pfn0;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO0)
        c0_pfn0 <= c0_wdata[25:6];
    else if(tlbr_we)
        c0_pfn0 <= lo0_data[25:6];
end 

reg [2:0] c0_c0;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO0)
        c0_c0 <= c0_wdata[5:3];
    else if(tlbr_we)
        c0_c0 <= lo0_data[5:3];
end 

reg c0_d0;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO0)
        c0_d0 <= c0_wdata[2];
    else if(tlbr_we)
        c0_d0 <= lo0_data[2];
end 

reg c0_v0;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO0)
        c0_v0 <= c0_wdata[1];
    else if(tlbr_we)
        c0_v0 <= lo0_data[1];
end 

reg c0_g0;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO0)
        c0_g0 <= c0_wdata[0];
    else if(tlbr_we)
        c0_g0 <= lo0_data[0];
end 


////entrylo1
reg [19:0] c0_pfn1;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO1)
        c0_pfn1 <= c0_wdata[25:6];
    else if(tlbr_we)
        c0_pfn1 <= lo1_data[25:6];
end 

reg [2:0] c0_c1;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO1)
        c0_c1 <= c0_wdata[5:3];
    else if(tlbr_we)
        c0_c1 <= lo1_data[5:3];
end 

reg c0_d1;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO1)
        c0_d1 <= c0_wdata[2];
    else if(tlbr_we)
        c0_d1 <= lo1_data[2];
end 

reg c0_v1;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO1)
        c0_v1 <= c0_wdata[1];
    else if(tlbr_we)
        c0_v1 <= lo1_data[1];
end 

reg c0_g1;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYLO1)
        c0_g1 <= c0_wdata[0];
    else if(tlbr_we)
        c0_g1 <= lo1_data[0];
end 


////entryhi
reg [18:0] c0_vpn2;
always @(posedge clk) begin 
    if(wb_ex && (wb_excode==`EX_TLBL || wb_excode==`EX_TLBS || wb_excode==`EX_MOD))
        c0_vpn2 <= wb_badvaddr[31:13];
    else if(mtc0_we && c0_addr==`CR_ENTRYHI)
        c0_vpn2 <= c0_wdata[31:13];
    else if(tlbr_we)
        c0_vpn2 <= hi_data[31:13];
end 

reg [7:0] c0_asid;
always @(posedge clk) begin 
    if(mtc0_we && c0_addr==`CR_ENTRYHI)
        c0_asid <= c0_wdata[7:0];
    else if(tlbr_we)
        c0_asid <= hi_data[7:0];
end

assign cp0_entryhi = {c0_vpn2,5'b0,c0_asid};


assign cp0_to_ws_bus = {{c0_index_p,27'b0,c0_index},
                        {6'b0,c0_pfn0,c0_c0,c0_d0,c0_v0,c0_g0},
                        {6'b0,c0_pfn1,c0_c1,c0_d1,c0_v1,c0_g1},
                        {c0_vpn2,5'b0,c0_asid},
                        {9'b0,c0_status_bev,6'b0,c0_status_im,6'b0,c0_status_exl,c0_status_ie},
                        {c0_cause_bd,c0_cause_ti,14'b0,c0_cause_ip,1'b0,c0_cause_excode,2'b0},    
                        c0_epc,             //127:96
                        c0_badvaddr,        //95:64
                        c0_count,           //63:32
                        c0_compare          //31:0
                        };

assign has_int = ((c0_cause_ip[7:0] & c0_status_im[7:0])!=8'h00) && c0_status_ie==1'b1 && c0_status_exl==1'b0;  ////& < != 

endmodule
