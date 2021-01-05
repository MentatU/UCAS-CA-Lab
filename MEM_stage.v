`include "mycpu.h"

module mem_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ws_allowin    ,
    output                         ms_allowin    ,
    //from es
    input                          es_to_ms_valid,
    input  [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    input                          es_is_l       ,
    
    input         exception,
    input         eret,
    input         tlbrw,
    //to ws
    output                         ms_to_ws_valid,
    output [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus  ,
    //forward_bus
    output [`FORWARD_BUS_WD    :0] forward_ms_to_ds_bus,
    output                         ms_loading,
    //from data-sram
    //input  [31                 :0] data_sram_rdata,
    input         data_sram_data_ok,
    input  [31:0] data_sram_rdata,
    
    output        ms_to_es_ex,
    output        ms_mtc0_entryhi
);

reg         ms_valid;
wire        ms_ready_go;

reg [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus_r;
wire        ms_es_tlb_refill;
wire        ms_tlbp_found ;
wire [ 3:0] ms_tlbp_index ;
wire        ms_tlbr_op    ;       //for tlbr
wire        ms_tlbwi_op   ;       //for tlbwi
wire        ms_tlbp_op    ;       //fot tlbp
wire        ms_is_load    ;
wire        ms_is_store   ;
wire        ms_es_ex      ;
wire        ms_es_bd      ;
wire [31:0] ms_es_badvaddr;       
wire [ 4:0] ms_es_excode  ;
wire        ms_eret_op    ;       //for eret
wire        ms_mfc0_op    ;       //for mfc0
wire        ms_mtc0_op    ;       //for mtc0
wire [ 7:0] ms_c0_addr    ;       //for mfc0 mtc0
wire [ 6:0] ms_load_op;
wire        ms_res_from_mem;
wire        ms_gr_we;
wire [ 4:0] ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;
assign {ms_es_tlb_refill, //138
        ms_tlbp_found  ,  //137
        ms_tlbp_index  ,  //136:133
        ms_tlbr_op     ,  //132
        ms_tlbwi_op    ,  //131
        ms_tlbp_op     ,  //130
        ms_is_load     ,  //129
        ms_is_store    ,  //128
        ms_es_ex       ,  //127
        ms_es_bd       ,  //126
        ms_es_badvaddr ,  //125:94      
        ms_es_excode   ,  //93:89
        ms_eret_op     ,  //88
        ms_mfc0_op     ,  //87
        ms_mtc0_op     ,  //86
        ms_c0_addr     ,  //85:78
        ms_load_op     ,  //77:71
        ms_res_from_mem,  //70:70
        ms_gr_we       ,  //69:69
        ms_dest        ,  //68:64
        ms_alu_result  ,  //63:32
        ms_pc             //31:0
       } = es_to_ms_bus_r;

wire [31:0] mem_result;
wire [31:0] ms_final_result;
wire [ 1:0] load_addr;                  //the least 2-bit of address
wire [ 3:0] load_we;                    //load 4-bit rf_wen
wire [ 3:0] ms_rf_we;                   //4-bit rf_wen

assign load_addr = ms_alu_result[1:0];

wire        ms_tlb_refill;
wire        ms_ex      ;
wire        ms_bd      ;
wire [31:0] ms_badvaddr;       
wire [ 4:0] ms_excode  ;
assign ms_tlb_refill = ms_es_tlb_refill;
assign ms_ex = ms_es_ex;
assign ms_bd = ms_es_bd;
assign ms_badvaddr = ms_es_badvaddr;
assign ms_excode = ms_es_excode;

assign ms_to_es_ex = (ms_ex|ms_eret_op|ms_tlbr_op|ms_tlbwi_op)&ms_valid;
assign ms_mtc0_entryhi = ms_mtc0_op & (ms_c0_addr==`CR_ENTRYHI) & ms_valid;     

assign ms_to_ws_bus = {ms_tlb_refill  ,  //131
                       ms_tlbp_found  ,  //130
                       ms_tlbp_index  ,  //129:126
                       ms_tlbr_op     ,  //125
                       ms_tlbwi_op    ,  //124
                       ms_tlbp_op     ,  //123
                       ms_ex          ,  //122
                       ms_bd          ,  //121
                       ms_badvaddr    ,  //120:89    
                       ms_excode      ,  //88:84
                       ms_eret_op     ,  //83
                       ms_mfc0_op     ,  //82
                       ms_mtc0_op     ,  //81
                       ms_c0_addr     ,  //80:73
                       ms_rf_we       ,  //72:69
                       ms_dest        ,  //68:64
                       ms_final_result,  //63:32
                       ms_pc             //31:0
                      };

reg ms_cancel_d; //ms cancel delete

assign ms_ready_go    = (exception|eret|tlbrw) ? 1'b1 :
                        (ms_cancel_d==1'b1 && (ms_is_load|ms_is_store)) ? 1'b0 :
                        (ms_is_load|ms_is_store) ? data_sram_data_ok : 
                        1'b1;  //
assign ms_allowin     = !ms_valid || ms_ready_go && ws_allowin;
assign ms_to_ws_valid = (exception | eret |tlbrw)?1'b0:  ms_valid && ms_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ms_valid <= 1'b0;
    end
//    else if (exception | eret) begin
//        ms_valid <= 1'b0;
//    end
    else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end

    if (es_to_ms_valid && ms_allowin) begin
        es_to_ms_bus_r  <= es_to_ms_bus;             //bug7 =
    end
end

//ms cancel delete
always @(posedge clk) begin
    if(reset) begin
        ms_cancel_d <= 1'b0;
    end
    else if((exception|eret|tlbrw)&&((es_to_ms_valid==1'b1 && es_is_l==1'b1) || (ms_allowin==1'b0&&ms_ready_go==1'b0&&(ms_is_load==1'b1||ms_is_store)))) begin
        ms_cancel_d <= 1'b1;
    end
    else if(data_sram_data_ok) begin
        ms_cancel_d <= 1'b0;
    end
end

assign mem_result = ({32{(ms_load_op[1])}}&{32{load_addr==2'b00}}&{{24{data_sram_rdata[7]}},data_sram_rdata[7:0]})|         //lb
				    ({32{(ms_load_op[1])}}&{32{load_addr==2'b01}}&{{24{data_sram_rdata[15]}},data_sram_rdata[15:8]})|       
				    ({32{(ms_load_op[1])}}&{32{load_addr==2'b10}}&{{24{data_sram_rdata[23]}},data_sram_rdata[23:16]})|
				    ({32{(ms_load_op[1])}}&{32{load_addr==2'b11}}&{{24{data_sram_rdata[31]}},data_sram_rdata[31:24]})|
			 	    ({32{(ms_load_op[3])}}&{32{load_addr==2'b00}}&{{16{data_sram_rdata[15]}},data_sram_rdata[15:0]})|       //lh
				    ({32{(ms_load_op[3])}}&{32{load_addr==2'b10}}&{{16{data_sram_rdata[31]}},data_sram_rdata[31:16]})|
				    ({32{(ms_load_op[0])}}&data_sram_rdata[31:0])|                                                          //lw
				    ({32{(ms_load_op[2])}}&{32{load_addr==2'b00}}&{{24{1'b0}},data_sram_rdata[7:0]})|                       //lbu
				    ({32{(ms_load_op[2])}}&{32{load_addr==2'b01}}&{{24{1'b0}},data_sram_rdata[15:8]})|
				    ({32{(ms_load_op[2])}}&{32{load_addr==2'b10}}&{{24{1'b0}},data_sram_rdata[23:16]})|
				    ({32{(ms_load_op[2])}}&{32{load_addr==2'b11}}&{{24{1'b0}},data_sram_rdata[31:24]})|
				    ({32{(ms_load_op[4])}}&{32{load_addr==2'b00}}&{{16{1'b0}},data_sram_rdata[15:0]})|                      //lhu
				    ({32{(ms_load_op[4])}}&{32{load_addr==2'b10}}&{{16{1'b0}},data_sram_rdata[31:16]})|
					({32{(ms_load_op[6])}}&{32{load_addr==2'b00}}&data_sram_rdata[31:0])|                                   //lwr
					({32{(ms_load_op[6])}}&{32{load_addr==2'b01}}&{{8'b0},data_sram_rdata[31:8]})|
					({32{(ms_load_op[6])}}&{32{load_addr==2'b10}}&{{16'b0},data_sram_rdata[31:16]})|
					({32{(ms_load_op[6])}}&{32{load_addr==2'b11}}&{{24'b0},data_sram_rdata[31:24]})|
					({32{(ms_load_op[5])}}&{32{load_addr==2'b00}}&{data_sram_rdata[7:0],{24'b0}})|                          //lwl
					({32{(ms_load_op[5])}}&{32{load_addr==2'b01}}&{data_sram_rdata[15:0],{16'b0}})|
					({32{(ms_load_op[5])}}&{32{load_addr==2'b10}}&{data_sram_rdata[23:0],{8'b0}})|
					({32{(ms_load_op[5])}}&{32{load_addr==2'b11}}&data_sram_rdata[31:0]);
assign load_we =    ({4{(ms_load_op[6])}}&{4{load_addr==2'b00}}&4'b1111)|                                                //lwr
					({4{(ms_load_op[6])}}&{4{load_addr==2'b01}}&4'b0111)|
					({4{(ms_load_op[6])}}&{4{load_addr==2'b10}}&4'b0011)|
					({4{(ms_load_op[6])}}&{4{load_addr==2'b11}}&4'b0001)|
					({4{(ms_load_op[5])}}&{4{load_addr==2'b00}}&4'b1000)|                                                //lwl
					({4{(ms_load_op[5])}}&{4{load_addr==2'b01}}&4'b1100)|
					({4{(ms_load_op[5])}}&{4{load_addr==2'b10}}&4'b1110)|
					({4{(ms_load_op[5])}}&{4{load_addr==2'b11}}&4'b1111)|
					({4{(ms_load_op[0]|ms_load_op[1]|ms_load_op[2]|ms_load_op[3]|ms_load_op[4])}}&{4{ms_gr_we}});         //otherwise

assign ms_rf_we = ms_res_from_mem ? load_we : {4{ms_gr_we}};
assign ms_final_result = ms_res_from_mem ? mem_result
                                         : ms_alu_result;
assign ms_loading = ms_is_load & ms_valid; 
                                         
//forward
assign forward_ms_to_ds_bus={ms_rf_we&{4{ms_to_ws_valid}},ms_mfc0_op&ms_to_ws_valid,ms_dest&{5{ms_to_ws_valid}},ms_final_result}; //

endmodule
