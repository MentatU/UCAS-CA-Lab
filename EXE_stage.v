`include "mycpu.h"

module exe_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ms_allowin    ,
    output                         es_allowin    ,
    //from ds
    input                          ds_to_es_valid,
    input  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    
    input         exception,
    input         eret,
    input         tlbrw,
    input         ms_to_es_ex,
    input         ws_to_es_ex,
    //to ms
    output                         es_to_ms_valid,
    output [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    output                         es_is_l,
    //forward_bus
    output [`FORWARD_BUS_WD  +1:0] forward_es_to_ds_bus,

    output        data_sram_req,
    output        data_sram_wr,
    output [ 1:0] data_sram_size,
    output [ 3:0] data_sram_wstrb,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input         data_sram_addr_ok,
    
    //search port 1
    output [              18:0] s1_vpn2,
    output                      s1_odd_page,
    output [               7:0] s1_asid,
    input                       s1_found,
    input  [               3:0] s1_index,       //TLBNUM=16
    input  [              19:0] s1_pfn,
    input  [               2:0] s1_c,
    input                       s1_d,
    input                       s1_v,

    input  [              31:0] cp0_entryhi,
    input                       ms_mtc0_entryhi,
    input                       ws_mtc0_entryhi
);

reg  [31:0] hi;       //HI
reg  [31:0] lo;       //LO
wire [63:0] mult_result;
wire [63:0] multu_result;
wire [63:0] div_result;
wire [63:0] divu_result;
reg  div_tvalid;
reg  divu_tvalid;
wire div_divisor_tready;
wire div_dividend_tready;
wire divu_divisor_tready;
wire divu_dividend_tready;
wire div_out_tvalid;
wire divu_out_tvalid;


reg         es_valid      ;
wire        es_ready_go   ;

wire        es_tlbp_found;
wire [ 3:0] es_tlbp_index;

reg  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus_r;
wire        es_ds_tlb_refill;
wire        es_tlbr_op    ;       //for tlbr
wire        es_tlbwi_op   ;       //for tlbwi
wire        es_tlbp_op    ;       //for tlbp
wire        es_ov_op      ;
wire        es_ds_ex      ;
wire        es_ds_bd      ;
wire [31:0] es_ds_badvaddr;       
wire [ 4:0] es_ds_excode  ;
wire        es_eret_op    ;       //for eret
wire        es_mfc0_op    ;       //for mfc0
wire        es_mtc0_op    ;       //for mtc0
wire [ 7:0] es_c0_addr    ;       //for mfc0 mtc0
wire [11:0] es_alu_op     ;
wire [ 4:0] es_store_op   ;       //for sw sb sh swl swr
wire [ 6:0] es_load_op    ;       //for lw lb lbu lh lhu lwl lwr
wire        es_mult_op    ;       //for mult
wire        es_multu_op   ;       //for multu
wire        es_div_op     ;       //for div
wire        es_divu_op    ;       //for divu
wire        es_mthi_op    ;       //for mthi
wire        es_mtlo_op    ;       //for mtlo
wire        es_mfhi_op    ;       //for mfhi
wire        es_mflo_op    ;       //for mflo
wire        es_src1_is_sa ;  
wire        es_src1_is_pc ;
wire        es_src2_is_imm; 
wire        es_src2_is_zimm;
wire        es_src2_is_8  ;
wire        es_gr_we      ;
wire        es_mem_we     ;
wire [ 4:0] es_dest       ;
wire [15:0] es_imm        ;
wire [31:0] es_rs_value   ;
wire [31:0] es_rt_value   ;
wire [31:0] es_pc         ;
assign {es_ds_tlb_refill, //210
        es_tlbr_op     ,  //209
        es_tlbwi_op    ,  //208
        es_tlbp_op     ,  //207
        es_ov_op       ,  //206
        es_ds_ex       ,  //205
        es_ds_bd       ,  //204
        es_ds_badvaddr ,  //203:172       
        es_ds_excode   ,  //171:167 
        es_eret_op     ,  //166
        es_mfc0_op     ,  //165
        es_mtc0_op     ,  //164
        es_c0_addr     ,  //163:156
        es_alu_op      ,  //155:144
        es_store_op    ,  //143:139
        es_load_op     ,  //138:132
        es_mult_op     ,  //131
        es_multu_op    ,  //130
        es_div_op      ,  //129
        es_divu_op     ,  //128
        es_mthi_op     ,  //127
        es_mtlo_op     ,  //126
        es_mfhi_op     ,  //125
        es_mflo_op     ,  //124
        es_src1_is_sa  ,  //123:123
        es_src1_is_pc  ,  //122:122
        es_src2_is_imm ,  //121:121
        es_src2_is_zimm,  //120:120
        es_src2_is_8   ,  //119:119
        es_gr_we       ,  //118:118
        es_mem_we      ,  //117:117
        es_dest        ,  //116:112
        es_imm         ,  //111:96
        es_rs_value    ,  //95 :64
        es_rt_value    ,  //63 :32
        es_pc             //31 :0
       } = ds_to_es_bus_r;

wire [31:0] es_alu_src1   ;
wire [31:0] es_alu_src2   ;
wire [31:0] es_alu_result ;
wire [31:0] es_result     ;     //for mfhi mflo

assign es_result = (es_mfhi_op) ? hi :
                   (es_mflo_op) ? lo :
                   (es_mtc0_op) ? es_rt_value :      //c0_wdata
                                  es_alu_result;


wire        es_res_from_mem;
wire        es_is_load;
wire        es_is_store;

wire        mapped;
wire [31:0] vaddr;

wire        es_tlb_refill;
wire        overflow   ;
wire        ades       ;
wire        adel       ;
wire        es_ex      ;
wire        es_bd      ;
wire [31:0] es_badvaddr;       
wire [ 4:0] es_excode  ;
assign es_tlb_refill = (es_ds_tlb_refill!=1'b0) ? es_ds_tlb_refill :
                       (s1_found==1'b0&&mapped==1'b1);            
assign es_ex = (es_ds_ex!=1'b0) ? es_ds_ex :
               (es_ov_op & overflow) ? 1'b1 :
               (s1_found==1'b0&&mapped==1'b1) ? 1'b1 :
               (s1_found==1'b1&&s1_v==1'b0&&mapped==1'b1) ? 1'b1 :
               (s1_found==1'b1&&s1_v==1'b1&&s1_d==1'b0&&mapped==1'b1&&es_is_store==1'b1) ? 1'b1 :
               (ades|adel)? 1'b1 : 1'b0 ;
assign es_bd = es_ds_bd;
assign es_badvaddr = (es_ds_ex!=1'b0) ? es_ds_badvaddr :
                     (s1_found==1'b0&&mapped==1'b1) ? es_result :
                     (s1_found==1'b1&&s1_v==1'b0&&mapped==1'b1) ? es_result :
                     (s1_found==1'b1&&s1_v==1'b1&&s1_d==1'b0&&mapped==1'b1&&es_is_store==1'b1) ? es_result :
                     (ades|adel) ? es_result : 32'b0 ;                
assign es_excode = (es_ds_ex!=1'b0) ? es_ds_excode :
                   (es_ov_op & overflow) ? `EX_OV :
                   (s1_found==1'b0&&mapped==1'b1&&es_is_load==1'b1) ? `EX_TLBL :
                   (s1_found==1'b0&&mapped==1'b1&&es_is_store==1'b1) ? `EX_TLBS :
                   (s1_found==1'b1&&s1_v==1'b0&&mapped==1'b1&&es_is_load==1'b1) ? `EX_TLBL :
                   (s1_found==1'b1&&s1_v==1'b0&&mapped==1'b1&&es_is_store==1'b1) ? `EX_TLBS :
                   (s1_found==1'b1&&s1_v==1'b1&&s1_d==1'b0&&mapped==1'b1&&es_is_store==1'b1) ? `EX_MOD :
                   (ades) ? `EX_ADES :
                   (adel) ? `EX_ADEL : 5'b0;

wire        in_exception;
assign in_exception = es_ex | ms_to_es_ex | ws_to_es_ex;


assign es_is_store = es_store_op[0] | es_store_op[1] | es_store_op[2] | es_store_op[3] | es_store_op[4];
assign es_is_load = es_load_op[0] | es_load_op[1] | es_load_op[2] | es_load_op[3] | es_load_op[4] | es_load_op[5] | es_load_op[6];
assign es_is_l = (es_is_load|es_is_store);        //es is load or store
assign es_res_from_mem = es_is_load;
assign es_to_ms_bus = {es_tlb_refill  ,  //138
                       es_tlbp_found  ,  //137
                       es_tlbp_index  ,  //136:133
                       es_tlbr_op     ,  //132
                       es_tlbwi_op    ,  //131
                       es_tlbp_op     ,  //130
                       es_is_load     ,  //129
                       es_is_store    ,  //128
                       es_ex          ,  //127
                       es_bd          ,  //126
                       es_badvaddr    ,  //125:94     
                       es_excode      ,  //93:89
                       es_eret_op     ,  //88
                       es_mfc0_op     ,  //87
                       es_mtc0_op     ,  //86
                       es_c0_addr     ,  //85:78
                       es_load_op     ,  //77:71
                       es_res_from_mem,  //70:70
                       es_gr_we       ,  //69:69
                       es_dest        ,  //68:64
                       es_result      ,  //63:32
                       es_pc             //31:0
                      };

assign es_ready_go    = (exception | eret | tlbrw) ? 1'b1 :
                        (es_div_op)  ? div_out_tvalid  :        //wait for div divu
                        (es_divu_op) ? divu_out_tvalid :
                        (es_tlbp_op&(ms_mtc0_entryhi|ws_mtc0_entryhi)) ? 1'b0 :
                        (es_is_load|es_is_store) ? (data_sram_req & data_sram_addr_ok) :
                        1'b1;  //
assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid =  (exception | eret |tlbrw)?1'b0:  es_valid && es_ready_go;
always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
 //  else if (exception | eret) begin
 //       es_valid <= 1'b0;
 //  end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end

    if (ds_to_es_valid && es_allowin) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
end

assign es_alu_src1 = es_src1_is_sa  ? {27'b0, es_imm[10:6]} : 
                     es_src1_is_pc  ? es_pc[31:0] :
                                      es_rs_value;
assign es_alu_src2 = es_src2_is_imm ? {{16{es_imm[15]}}, es_imm[15:0]} : 
                     es_src2_is_zimm? {{16{1'b0}},es_imm[15:0]} :
                     es_src2_is_8   ? 32'd8 :
                                      es_rt_value;

alu u_alu(
    .alu_op     (es_alu_op    ),
    .alu_src1   (es_alu_src1  ),     //bug3 es_alu_src2
    .alu_src2   (es_alu_src2  ),
    .alu_result (es_alu_result),
    .overflow   (overflow     )
    );

//mult
assign mult_result = $signed(es_rs_value) * $signed(es_rt_value);
//multu
assign multu_result = es_rs_value * es_rt_value;
//div
always @(posedge clk) begin
    if (reset) begin
        div_tvalid<=1'b0;
    end
    else if(ds_to_es_valid & es_allowin) begin
        div_tvalid<=ds_to_es_bus[129:129];
    end
    else if(div_tvalid & div_divisor_tready & div_dividend_tready)begin
        div_tvalid<=1'b0;
    end
end

mydiv mydiv(
    .aclk                   (clk),
    .s_axis_divisor_tvalid  (div_tvalid),
    .s_axis_divisor_tready  (div_divisor_tready),
    .s_axis_divisor_tdata   (es_rt_value),
    .s_axis_dividend_tvalid (div_tvalid),
    .s_axis_dividend_tready (div_dividend_tready),
    .s_axis_dividend_tdata  (es_rs_value),
    .m_axis_dout_tvalid     (div_out_tvalid),
    .m_axis_dout_tdata      (div_result)
);
//divu
always @(posedge clk) begin
    if (reset) begin
        divu_tvalid<=1'b0;
    end
    else if(ds_to_es_valid & es_allowin) begin
        divu_tvalid<=ds_to_es_bus[128:128];
    end
    else if(divu_tvalid & divu_divisor_tready & divu_dividend_tready)begin
        divu_tvalid<=1'b0;
    end
end


mydivu mydivu(
    .aclk                   (clk),
    .s_axis_divisor_tvalid  (divu_tvalid),
    .s_axis_divisor_tready  (divu_divisor_tready),
    .s_axis_divisor_tdata   (es_rt_value),
    .s_axis_dividend_tvalid (divu_tvalid),
    .s_axis_dividend_tready (divu_dividend_tready),
    .s_axis_dividend_tdata  (es_rs_value),
    .m_axis_dout_tvalid     (divu_out_tvalid),
    .m_axis_dout_tdata      (divu_result)
);

//HI
always @(posedge clk) begin
    if (reset) begin
        hi<=32'b0;
    end
    else if(in_exception)begin
        hi<=hi;
    end
    else if(es_mult_op & es_valid) begin
        hi<=mult_result[63:32];
    end
    else if(es_multu_op & es_valid) begin
        hi<=multu_result[63:32];
    end
    else if(es_div_op & div_out_tvalid & es_valid) begin
        hi<=div_result[31:0];
    end
    else if(es_divu_op & divu_out_tvalid & es_valid) begin
        hi<=divu_result[31:0];
    end
    else if(es_mthi_op & es_valid) begin
        hi<=es_rs_value;
    end
end
//LO
always @(posedge clk) begin
    if (reset) begin
        lo<=32'b0;
    end
    else if(in_exception) begin
        lo<=lo;
    end
    else if(es_mult_op & es_valid) begin
        lo<=mult_result[31:0];
    end
    else if(es_multu_op & es_valid) begin
        lo<=multu_result[31:0];
    end
    else if(es_div_op & div_out_tvalid & es_valid) begin
        lo<=div_result[63:32];
    end
    else if(es_divu_op & divu_out_tvalid & es_valid) begin
        lo<=divu_result[63:32];
    end
    else if(es_mtlo_op & es_valid) begin
        lo<=es_rs_value;
    end
end

//forward
assign forward_es_to_ds_bus={{4{es_gr_we}}&{4{es_valid}},es_is_load&es_valid,es_mfc0_op&es_valid,es_dest&{5{es_valid}},es_result};

wire [31:0] store_data;
wire [ 3:0] store_wen;
wire [ 1:0] store_addr;   //the least 2-bit of address

assign store_addr = es_result[1:0];
assign store_data = ({32{(es_store_op[0])}}&es_rt_value)|                                                       //sw
                    ({32{(es_store_op[1])}}&{4{es_rt_value[ 7:0]}})|                                            //sb
                    ({32{(es_store_op[2])}}&{2{es_rt_value[15:0]}})|                                            //sh
					({32{(es_store_op[4])}}&{32{(store_addr==2'b00)}}&es_rt_value[31:0])|                       //swr
					({32{(es_store_op[4])}}&{32{(store_addr==2'b01)}}&{es_rt_value[23:0],{8{1'b0}}})|
					({32{(es_store_op[4])}}&{32{(store_addr==2'b10)}}&{es_rt_value[15:0],{16{1'b0}}})|
					({32{(es_store_op[4])}}&{32{(store_addr==2'b11)}}&{es_rt_value[7:0],{24{1'b0}}})|
					({32{(es_store_op[3])}}&{32{(store_addr==2'b00)}}&{{24{1'b0}},es_rt_value[31:24]})|         //swl
					({32{(es_store_op[3])}}&{32{(store_addr==2'b01)}}&{{16{1'b0}},es_rt_value[31:16]})|
					({32{(es_store_op[3])}}&{32{(store_addr==2'b10)}}&{{8{1'b0}},es_rt_value[31:8]})|
					({32{(es_store_op[3])}}&{32{(store_addr==2'b11)}}&es_rt_value[31:0]);
assign store_wen  = ({4{(es_store_op[1])}}&{4{(store_addr==2'b00)}}&4'b0001)|                                   //sb
					({4{(es_store_op[1])}}&{4{(store_addr==2'b01)}}&4'b0010)|
					({4{(es_store_op[1])}}&{4{(store_addr==2'b10)}}&4'b0100)|
					({4{(es_store_op[1])}}&{4{(store_addr==2'b11)}}&4'b1000)|
					({4{(es_store_op[2])}}&{4{(store_addr==2'b00)}}&4'b0011)|                                   //sh
					({4{(es_store_op[2])}}&{4{(store_addr==2'b10)}}&4'b1100)|
					({4{(es_store_op[0])}}&{4{(store_addr==2'b00)}}&4'b1111)|                                   //sw
					({4{(es_store_op[4])}}&{4{(store_addr==2'b00)}}&4'b1111)|                                   //swr
					({4{(es_store_op[4])}}&{4{(store_addr==2'b01)}}&4'b1110)|
					({4{(es_store_op[4])}}&{4{(store_addr==2'b10)}}&4'b1100)|
					({4{(es_store_op[4])}}&{4{(store_addr==2'b11)}}&4'b1000)|
					({4{(es_store_op[3])}}&{4{(store_addr==2'b00)}}&4'b0001)|                                   //swl
					({4{(es_store_op[3])}}&{4{(store_addr==2'b01)}}&4'b0011)|
					({4{(es_store_op[3])}}&{4{(store_addr==2'b10)}}&4'b0111)|
					({4{(es_store_op[3])}}&{4{(store_addr==2'b11)}}&4'b1111);

assign ades = (es_store_op[0] & (store_addr!=2'b00)) | (es_store_op[2] & (store_addr[0]!=1'b0));
assign adel = (es_load_op[0] & (store_addr!=2'b00)) | (es_load_op[3] & (store_addr[0]!=1'b0)) | (es_load_op[4] & (store_addr[0]!=1'b0));


assign data_sram_req = es_valid & ms_allowin & (es_is_load|es_is_store);
assign data_sram_wr = (es_valid & es_is_load) ? 1'b0 : 
                      (es_valid & es_is_store);
assign data_sram_size = (({2{(es_load_op[0]|es_store_op[0])}}&2'd2)|                              //lw sw
                        ({2{(es_load_op[3]|es_load_op[4]|es_store_op[2])}}&2'd1)|                //lh lhu sh
                        ({2{(es_load_op[1]|es_load_op[2]|es_store_op[1])}}&2'd0)|                //lb lbu sb
                        ({2{(es_load_op[5]|es_store_op[3])}}&{2{(store_addr==2'b00)}}&2'd0)|                 //lwl swl
                        ({2{(es_load_op[5]|es_store_op[3])}}&{2{(store_addr==2'b01)}}&2'd1)|
                        ({2{(es_load_op[5]|es_store_op[3])}}&{2{(store_addr==2'b10)}}&2'd2)|
                        ({2{(es_load_op[5]|es_store_op[3])}}&{2{(store_addr==2'b11)}}&2'd2)|
                        ({2{(es_load_op[6]|es_store_op[4])}}&{2{(store_addr==2'b00)}}&2'd2)|                 //lwr swr
                        ({2{(es_load_op[6]|es_store_op[4])}}&{2{(store_addr==2'b01)}}&2'd2)|
                        ({2{(es_load_op[6]|es_store_op[4])}}&{2{(store_addr==2'b10)}}&2'd1)|
                        ({2{(es_load_op[6]|es_store_op[4])}}&{2{(store_addr==2'b11)}}&2'd0))
                        & {2{es_valid}};

//TLB
assign s1_vpn2 = (es_tlbp_op) ? cp0_entryhi[31:13] : vaddr[31:13];
assign s1_odd_page = (es_tlbp_op) ? cp0_entryhi[12] : vaddr[12];
assign s1_asid = cp0_entryhi[7:0];
assign es_tlbp_found = s1_found;
assign es_tlbp_index = s1_index;

assign data_sram_wstrb = es_mem_we&&es_valid&&(!in_exception) ? store_wen : 4'h0;
assign vaddr = (es_store_op[3]|es_load_op[5]) ? {es_result[31:2],2'b0} : es_result;                         //attention no lwl swl then vaddr==es_result for futher debug
assign mapped = (vaddr[31:28]==4'h8 || vaddr[31:28]==4'h9 || vaddr[31:28]==4'ha || vaddr[31:28]==4'hb) ? 1'b0 :
                (es_is_l==1'b1) ? 1'b1 : 1'b0;
assign data_sram_addr = (mapped==1'b0) ? vaddr : {s1_pfn,vaddr[11:0]};
assign data_sram_wdata = store_data & {32{es_valid}};

endmodule
