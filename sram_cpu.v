module sram_cpu(
    input         clk,
    input         resetn,
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

    // data sram interface
    output        data_sram_req,
    output        data_sram_wr,
    output [ 1:0] data_sram_size,
    output [ 3:0] data_sram_wstrb,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input         data_sram_addr_ok,
    input         data_sram_data_ok,
    input  [31:0] data_sram_rdata,

    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);
reg         reset;
always @(posedge clk) reset <= ~resetn;

wire         ds_allowin;
wire         es_allowin;
wire         ms_allowin;
wire         ws_allowin;
wire         fs_to_ds_valid;
wire         ds_to_es_valid;
wire         es_to_ms_valid;
wire         ms_to_ws_valid;
wire [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus;
wire [`BR_BUS_WD       -1:0] br_bus;
wire [`FORWARD_BUS_WD  +1:0] forward_es_to_ds_bus;     //forward_bus
wire [`FORWARD_BUS_WD    :0] forward_ms_to_ds_bus;
wire [`FORWARD_BUS_WD  -1:0] forward_ws_to_ds_bus;

wire [`WS_TO_CP0_BUS_WD-1:0] ws_to_cp0_bus;
wire [`CP0_TO_WS_BUS_WD-1:0] cp0_to_ws_bus;
wire          exception;
wire          eret;
wire [31:0]   cp0_epc;
wire          ws_to_es_ex;
wire          ms_to_es_ex;
wire          has_int;
wire          br_leaving;
wire          es_is_l;
wire          ms_loading;

parameter TLBNUM = 16;
// search port 0
wire [18:0] s0_vpn2;
wire        s0_odd_page;
wire [7:0]  s0_asid;
wire        s0_found;
wire [$clog2(TLBNUM)-1:0]s0_index;
wire [19:0] s0_pfn;
wire [2:0]  s0_c;
wire        s0_d;
wire        s0_v;
// search port 1
wire [18:0] s1_vpn2;
wire        s1_odd_page;
wire [7:0]  s1_asid;
wire        s1_found;
wire [$clog2(TLBNUM)-1:0] s1_index;
wire [19:0] s1_pfn;
wire [2:0]  s1_c;
wire        s1_d;
wire        s1_v;
// write port
wire        we;
wire [$clog2(TLBNUM)-1:0] w_index;
wire [18:0] w_vpn2;
wire [7:0]  w_asid;
wire        w_g;
wire [19:0] w_pfn0;
wire [2:0]  w_c0;
wire        w_d0;
wire        w_v0;
wire [19:0] w_pfn1;
wire [2:0]  w_c1;
wire        w_d1;
wire        w_v1;
// read port
wire [$clog2(TLBNUM)-1:0] r_index;
wire [18:0] r_vpn2;
wire [7:0]  r_asid;
wire        r_g;
wire [19:0] r_pfn0;
wire [2:0]  r_c0;
wire        r_d0;
wire        r_v0;
wire [19:0] r_pfn1;
wire [2:0]  r_c1;
wire        r_d1;
wire        r_v1;

wire [31:0] cp0_entryhi;
wire        ms_mtc0_entryhi;
wire        ws_mtc0_entryhi;
wire        tlbrw;
wire [31:0] refetch_pc;
wire        ws_tlb_refill;

// IF stage
if_stage if_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ds_allowin     (ds_allowin     ),
    //brbus
    .br_bus         (br_bus         ),
    .br_leaving     (br_leaving     ),
    
    .exception      (exception      ),
    .eret           (eret           ),
    .tlbrw          (tlbrw          ),
    .refetch_pc     (refetch_pc     ),    
    .cp0_epc        (cp0_epc        ),
    .has_int        (has_int        ),
    .ws_tlb_refill  (ws_tlb_refill  ),
    //outputs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    // inst sram interface
    .inst_sram_req    (inst_sram_req    ),
    .inst_sram_wr     (inst_sram_wr     ),
    .inst_sram_size   (inst_sram_size   ),
    .inst_sram_wstrb  (inst_sram_wstrb  ),
    .inst_sram_addr   (inst_sram_addr   ),
    .inst_sram_wdata  (inst_sram_wdata  ),
    .inst_sram_addr_ok(inst_sram_addr_ok),
    .inst_sram_data_ok(inst_sram_data_ok),
    .inst_sram_rdata  (inst_sram_rdata  ),

    //TLB search port 0
    .s0_vpn2        (s0_vpn2        ),
    .s0_odd_page    (s0_odd_page    ),
    .s0_asid        (s0_asid        ),
    .s0_found       (s0_found       ),
    .s0_index       (s0_index       ),
    .s0_pfn         (s0_pfn         ),
    .s0_c           (s0_c           ),
    .s0_d           (s0_d           ),
    .s0_v           (s0_v           ),
    .cp0_entryhi    (cp0_entryhi    )
);
// ID stage
id_stage id_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .es_allowin     (es_allowin     ),
    .ds_allowin     (ds_allowin     ),
    //from fs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    //forward_bus
    .forward_es_to_ds_bus(forward_es_to_ds_bus),
    .forward_ms_to_ds_bus(forward_ms_to_ds_bus),
    .forward_ws_to_ds_bus(forward_ws_to_ds_bus),
    .ms_loading          (ms_loading          ),
    
    .exception      (exception      ),
    .eret           (eret           ),
    .tlbrw          (tlbrw          ),
    //to es
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to fs
    .br_bus         (br_bus         ),
    .br_leaving     (br_leaving     ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   )
);
// EXE stage
exe_stage exe_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ms_allowin     (ms_allowin     ),
    .es_allowin     (es_allowin     ),
    //from ds
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    
    .exception      (exception      ),
    .eret           (eret           ),
    .tlbrw          (tlbrw          ),
    .ms_to_es_ex    (ms_to_es_ex    ),
    .ws_to_es_ex    (ws_to_es_ex    ),
    //to ms
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    .es_is_l        (es_is_l        ),
    //forward_bus
    .forward_es_to_ds_bus(forward_es_to_ds_bus),
    // data sram interface
    .data_sram_req    (data_sram_req    ),
    .data_sram_wr     (data_sram_wr     ),
    .data_sram_size   (data_sram_size   ),
    .data_sram_wstrb  (data_sram_wstrb  ),
    .data_sram_addr   (data_sram_addr   ),
    .data_sram_wdata  (data_sram_wdata  ),
    .data_sram_addr_ok(data_sram_addr_ok),

    //TLB search port 1
    .s1_vpn2        (s1_vpn2        ),
    .s1_odd_page    (s1_odd_page    ),
    .s1_asid        (s1_asid        ),
    .s1_found       (s1_found       ),
    .s1_index       (s1_index       ),
    .s1_pfn         (s1_pfn         ),
    .s1_c           (s1_c           ),
    .s1_d           (s1_d           ),
    .s1_v           (s1_v           ),

    .cp0_entryhi    (cp0_entryhi    ),
    .ms_mtc0_entryhi(ms_mtc0_entryhi),
    .ws_mtc0_entryhi(ws_mtc0_entryhi)
);
// MEM stage
mem_stage mem_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    .ms_allowin     (ms_allowin     ),
    //from es
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    .es_is_l        (es_is_l        ),
    
    .exception      (exception      ),
    .eret           (eret           ),
    .tlbrw          (tlbrw          ),
    //to ws
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //forward_bus
    .forward_ms_to_ds_bus(forward_ms_to_ds_bus),
    .ms_loading     (ms_loading     ),
    //from data-sram
    //.data_sram_rdata(data_sram_rdata),
    .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata  (data_sram_rdata  ),

    
    .ms_to_es_ex    (ms_to_es_ex),
    .ms_mtc0_entryhi(ms_mtc0_entryhi)
);
// WB stage
wb_stage wb_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    //from ms
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    
    .cp0_to_ws_bus  (cp0_to_ws_bus),
    
    .exception      (exception      ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    //forward_bus
    .forward_ws_to_ds_bus(forward_ws_to_ds_bus),
    //trace debug interface
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_wen  (debug_wb_rf_wen  ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    
    .ws_to_cp0_bus  (ws_to_cp0_bus),
    .ws_to_es_ex    (ws_to_es_ex),
    .ws_mtc0_entryhi(ws_mtc0_entryhi),

    .tlbrw          (tlbrw),
    .refetch_pc     (refetch_pc),
    .ws_tlb_refill  (ws_tlb_refill),

    //TLB write and read
    .we             (we             ),
    .w_index        (w_index        ),
    .w_vpn2         (w_vpn2         ),
    .w_asid         (w_asid         ),
    .w_g            (w_g            ),
    .w_pfn0         (w_pfn0         ),
    .w_c0           (w_c0           ),
    .w_d0           (w_d0           ),
    .w_v0           (w_v0           ),
    .w_pfn1         (w_pfn1         ),
    .w_c1           (w_c1           ),
    .w_d1           (w_d1           ),
    .w_v1           (w_v1           ),
    .r_index        (r_index        ),
    .r_vpn2         (r_vpn2         ),
    .r_asid         (r_asid         ),
    .r_g            (r_g            ),
    .r_pfn0         (r_pfn0         ),
    .r_c0           (r_c0           ),
    .r_d0           (r_d0           ),
    .r_v0           (r_v0           ),
    .r_pfn1         (r_pfn1         ),
    .r_c1           (r_c1           ),
    .r_d1           (r_d1           ),
    .r_v1           (r_v1           )
);

//cp0     
cp0 cp0(
    .clk            (clk            ),
    .reset          (reset          ),
    .ws_to_cp0_bus  (ws_to_cp0_bus  ),
    .ext_int_in     (6'b0           ),
    .cp0_to_ws_bus  (cp0_to_ws_bus  ),
    .exception      (exception      ),
    .eret           (eret           ),
    .cp0_epc        (cp0_epc        ),
    .has_int        (has_int        ),
    .cp0_entryhi    (cp0_entryhi    )
);

//tlb
tlb #(.TLBNUM(16)) tlb
(
    .clk            (clk            ),
    .s0_vpn2        (s0_vpn2        ),
    .s0_odd_page    (s0_odd_page    ),
    .s0_asid        (s0_asid        ),
    .s0_found       (s0_found       ),
    .s0_index       (s0_index       ),
    .s0_pfn         (s0_pfn         ),
    .s0_c           (s0_c           ),
    .s0_d           (s0_d           ),
    .s0_v           (s0_v           ),
    .s1_vpn2        (s1_vpn2        ),
    .s1_odd_page    (s1_odd_page    ),
    .s1_asid        (s1_asid        ),
    .s1_found       (s1_found       ),
    .s1_index       (s1_index       ),
    .s1_pfn         (s1_pfn         ),
    .s1_c           (s1_c           ),
    .s1_d           (s1_d           ),
    .s1_v           (s1_v           ),
    .we             (we             ),
    .w_index        (w_index        ),
    .w_vpn2         (w_vpn2         ),
    .w_asid         (w_asid         ),
    .w_g            (w_g            ),
    .w_pfn0         (w_pfn0         ),
    .w_c0           (w_c0           ),
    .w_d0           (w_d0           ),
    .w_v0           (w_v0           ),
    .w_pfn1         (w_pfn1         ),
    .w_c1           (w_c1           ),
    .w_d1           (w_d1           ),
    .w_v1           (w_v1           ),
    .r_index        (r_index        ),
    .r_vpn2         (r_vpn2         ),
    .r_asid         (r_asid         ),
    .r_g            (r_g            ),
    .r_pfn0         (r_pfn0         ),
    .r_c0           (r_c0           ),
    .r_d0           (r_d0           ),
    .r_v0           (r_v0           ),
    .r_pfn1         (r_pfn1         ),
    .r_c1           (r_c1           ),
    .r_d1           (r_d1           ),
    .r_v1           (r_v1           )
);

endmodule
