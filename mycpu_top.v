module mycpu_top(
//--------------------------------------//
// sram inst interface
    input        inst_sram_req,
    input        inst_sram_wr,
    input [ 1:0] inst_sram_size,
    input [ 3:0] inst_sram_wstrb,
    input [31:0] inst_sram_addr,
    input [31:0] inst_sram_wdata,
    output       inst_sram_addr_ok,
    output       inst_sram_data_ok,
    output[31:0] inst_sram_rdata,
//--------------------------------------//
// sram data interface
    input        data_sram_req,
    input        data_sram_wr,
    input [ 1:0] data_sram_size,
    input [ 3:0] data_sram_wstrb,
    input [31:0] data_sram_addr,
    input [31:0] data_sram_wdata,
    output       data_sram_addr_ok,
    output       data_sram_data_ok,
    output[31:0] data_sram_rdata,
//--------------------------------------//
// axi inst interface
    // AXI clock and reset signal
    input         int,
    input         aclk,
    input         aresetn,
    //read acquire
    output [3:0]  arid,
    output [31:0] araddr,
    output [7:0]  arlen,
    output [2:0]  arsize,
    output [1:0]  arburst,
    output [1:0]  arlock,
    output [3:0]  arcache,
    output [2:0]  arprot,
    output        arvalid,
    input         arready,
    //read response
    input  [3:0]  rid,
    input  [31:0] rdata,
    input  [1:0]  rresp,
    input         rlast,
    input         rvalid,
    output        rready,
    //write acquire
    output [3:0]  awid,
    output [31:0] awaddr,
    output [7:0]  awlen,
    output [2:0]  awsize,
    output [1:0]  awburst,
    output [1:0]  awlock,
    output [3:0]  awcache,
    output [2:0]  awprot,
    output        awvalid,
    input         awready,
    //write data
    output [3:0]  wid,
    output [31:0] wdata,
    output [3:0]  wstrb,
    output        wlast,
    output        wvalid,
    input         wready,
    //write response
    input  [3:0]  bid,
    input  [1:0]  bresp,
    input         bvalid,
    output        bready,
//--------------------------------------//
// trace debug interface
    input  [31:0] wb_pc,
    input  [3:0]  wb_rf_wen,
    input  [4:0]  wb_rf_wnum,
    input  [31:0] wb_rf_wdata,

    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata

);
//--------------------------------------//
//debug signals
assign debug_wb_pc = wb_pc;
assign debug_wb_rf_wen = wb_rf_wen;
assign debug_wb_rf_wnum = wb_rf_wnum;
assign debug_wb_rf_wdata = wb_rf_wdata;

//--------------------------------------//
// finite state machine of read
localparam R_FREE        = 5'b00001; // initial state
localparam R_DATA_ACCEPT = 5'b00010; // accept the acquire of data loading
localparam R_INST_ACCEPT = 5'b00100; // accept the acquire of inst fetch
localparam R_INST_RETURN = 5'b01000; // return the inst
localparam R_DATA_RETURN = 5'b10000; // return the data

reg [4:0] r_state;
reg [4:0] r_next_state;

always @(posedge aclk) begin
    if(!aresetn) begin
        r_state <= R_FREE;
    end 
    else begin
        r_state <= r_next_state;
    end
end

always @(*) begin
    case(r_state)
        R_FREE: begin
            // priority: load > inst fetch
            if(data_sram_req && !data_sram_wr)begin
                r_next_state = R_DATA_ACCEPT;
            end
            else if(inst_sram_req) begin
                r_next_state = R_INST_ACCEPT;
            end
            else begin
                r_next_state = R_FREE;
            end
        end
        R_DATA_ACCEPT: begin
            if(arvalid && arready) begin
                r_next_state = R_DATA_RETURN;
            end
            else begin
                r_next_state = R_DATA_ACCEPT;
            end
        end
        R_INST_ACCEPT: begin
            if(arvalid && arready) begin
                r_next_state = R_INST_RETURN;
            end
            else begin
                r_next_state = R_INST_ACCEPT;
            end
        end
        R_DATA_RETURN: begin
            if(rvalid && rready) begin
                r_next_state = R_FREE;
            end
            else begin
                r_next_state = R_DATA_RETURN;
            end
        end
        R_INST_RETURN: begin
            if(rvalid && rready) begin
                r_next_state = R_FREE;
            end
            else begin
                r_next_state = R_INST_RETURN;
            end
        end
        default: begin
            r_next_state = R_FREE;
        end
    endcase
end

//--------------------------------------//
// finite state machine of write

// no matter awvalid&awready first or wvalid&wready first
// or all valid at the same time, it can handle
localparam W_FREE        = 5'b00001;
localparam W_ACCEPT      = 5'b00010;
localparam W_ADDR_ACCEPT = 5'b00100; // awvalid&awready first
localparam W_DATA_ACCEPT = 5'b01000; // wvalid&wready first
localparam W_DATA_RETURN = 5'b10000;

reg [4:0] w_state;
reg [4:0] w_next_state;

always @(posedge aclk) begin
    if(!aresetn) begin
        w_state <= W_FREE;
    end 
    else begin
        w_state <= w_next_state;
    end
end

always @(*) begin
    case(w_state)
        W_FREE: begin
            if(data_sram_req && data_sram_wr)begin
                w_next_state = W_ACCEPT;
            end
            else begin
                w_next_state = W_FREE;
            end
        end
        W_ACCEPT: begin
            if(awvalid && awready && wvalid && wready) begin
                w_next_state = W_DATA_RETURN;
            end
            else if((awvalid && awready) && !(wvalid && wready))begin
                w_next_state = W_ADDR_ACCEPT;
            end
            else if(!(awvalid && awready) && (wvalid && wready))begin
                w_next_state = W_DATA_ACCEPT;
            end
            else begin
                w_next_state = W_ACCEPT;
            end
        end
        W_ADDR_ACCEPT: begin
            if(wvalid && wready) begin
                w_next_state = W_DATA_RETURN;
            end
            else begin
                w_next_state = W_ADDR_ACCEPT;
            end
        end
        W_DATA_ACCEPT: begin
            if(awvalid && awready) begin
                w_next_state = W_DATA_RETURN;
            end
            else begin
                w_next_state = W_DATA_ACCEPT;
            end
        end
        W_DATA_RETURN: begin
            if(bvalid && bready) begin
                w_next_state = W_FREE;
            end
            else begin
                w_next_state = W_DATA_RETURN;
            end
        end
        default: begin
            w_next_state = W_FREE;
        end
    endcase
end

//--------------------------------------//
//read acquire
assign arlen = 8'b0;
assign arburst = 2'b01;
assign arlock = 2'b0;
assign arcache = 4'b0;
assign arprot = 3'b0;

wire data_read;
wire data_write;
assign data_read = data_sram_req && !data_sram_wr;
assign data_write = data_sram_req && data_sram_wr;
// once arvalid rise, they can NOT be changed !!!
assign arvalid = (r_state == R_DATA_ACCEPT || r_state == R_INST_ACCEPT) ? 1'b1 : 1'b0;
assign arid    = (r_state == R_DATA_ACCEPT) ? 4'b1 : 4'b0;
assign araddr  = (r_state == R_DATA_ACCEPT) ? data_sram_addr : inst_sram_addr;
assign arsize  = (r_state == R_DATA_ACCEPT) ? {1'b0,data_sram_size} : {1'b0,inst_sram_size};

assign inst_sram_addr_ok = (arvalid && arready && arid==4'b0)? 1'b1 : 1'b0;

assign data_sram_addr_ok = ((arvalid && arready && arid==4'b1) ||
                           (w_state == W_DATA_ACCEPT && awvalid && awready) || 
                           (w_state == W_ADDR_ACCEPT && wvalid  && wready ) ||
                           (w_state == W_ACCEPT && awvalid && awready && wvalid && wready)) ?
                            1'b1 : 1'b0;

//--------------------------------------//
//read response
assign rready = (r_state == R_DATA_RETURN || r_state == R_INST_RETURN) ? 1'b1: 1'b0;

assign {data_sram_rdata, inst_sram_rdata} = {2{rdata}};

assign inst_sram_data_ok = (rvalid && rready && rid==4'b0)? 1'b1 : 1'b0;

assign data_sram_data_ok = ((rvalid && rready && rid==4'b1) ||
                           (bvalid && bready && bid==4'b1)) ?
                           1'b1 : 1'b0;

//--------------------------------------//
//write acquire
assign awlen = 8'b0;
assign awburst = 2'b01;
assign awlock = 2'b0;
assign awcache = 4'b0;
assign awprot = 3'b0;
assign awvalid = (w_state == W_ACCEPT || w_state == W_DATA_ACCEPT)? 1'b1 : 1'b0;

reg [3 :0] awid_r;
reg [2 :0] awsize_r;
reg [31:0] awaddr_r;
// in order to save the value of signals
// once awvalid rise, they can NOT be changed
always @(posedge aclk) begin
    if(!aresetn)begin
        awid_r <= 4'b0;
        awsize_r <= 3'b0;
        awaddr_r <= 32'b0;
    end
    else if (data_write) begin
        awid_r <= 4'b1;
        awsize_r <= {1'b0,data_sram_size};
        awaddr_r <= data_sram_addr;
    end
    else if(bvalid && bready) begin
        awid_r <= 4'b0;
        awsize_r <= 3'b0;
        awaddr_r <= 32'b0;
    end
    else begin
        awid_r <= awid_r;
        awsize_r <= awsize_r;
        awaddr_r <= awaddr_r;
    end
end

assign awid = awid_r;
assign awaddr = awaddr_r;
assign awsize = awsize_r;

//--------------------------------------//
//write data
assign wlast = 1'b1;
assign wvalid = (w_state == W_ACCEPT || w_state == W_ADDR_ACCEPT)? 1'b1 : 1'b0;
// in order to save the value of signals
// once wvalid rise, they can NOT be changed
reg [3:0] wid_r;
reg [31:0] wdata_r;
reg [3:0] wstrb_r;

always @(posedge aclk) begin
    if(!aresetn)begin
        wid_r <= 4'b0;
        wdata_r <= 32'b0;
        wstrb_r <= 4'b0;
    end
    else if (data_write) begin
        wid_r <= 4'b1;
        wdata_r <= data_sram_wdata;
        wstrb_r <= data_sram_wstrb;
    end
    else if (bvalid && bready) begin
        wid_r <= 4'b0;
        wdata_r <= 32'b0;
        wstrb_r <= 4'b0;
    end
    else begin
        wid_r <= wid_r;
        wdata_r <= wdata_r;
        wstrb_r <= wstrb_r;
    end
end

assign wid = wid_r;
assign wdata = wdata_r;
assign wstrb = wstrb_r;

//--------------------------------------//
//write response
assign bready = (w_state == W_DATA_RETURN) ? 1'b1 : 1'b0;


sram_cpu sram_cpu(
    .clk              (aclk        ),
    .resetn           (aresetn     ),  //low active
    .inst_sram_req    (inst_sram_req    ),
    .inst_sram_wr     (inst_sram_wr     ),
    .inst_sram_size   (inst_sram_size   ),
    .inst_sram_wstrb  (inst_sram_wstrb  ),
    .inst_sram_addr   (inst_sram_addr   ),
    .inst_sram_wdata  (inst_sram_wdata  ),
    .inst_sram_addr_ok(inst_sram_addr_ok),
    .inst_sram_data_ok(inst_sram_data_ok),
    .inst_sram_rdata  (inst_sram_rdata  ),
    
    .data_sram_req    (data_sram_req    ),
    .data_sram_wr     (data_sram_wr     ),
    .data_sram_size   (data_sram_size   ),
    .data_sram_wstrb  (data_sram_wstrb  ),
    .data_sram_addr   (data_sram_addr   ),
    .data_sram_wdata  (data_sram_wdata  ),
    .data_sram_addr_ok(data_sram_addr_ok),
    .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata  (data_sram_rdata  ),

    //debug interface
    .debug_wb_pc      (wb_pc      ),
    .debug_wb_rf_wen  (wb_rf_wen  ),
    .debug_wb_rf_wnum (wb_rf_wnum ),
    .debug_wb_rf_wdata(wb_rf_wdata)
);




endmodule
