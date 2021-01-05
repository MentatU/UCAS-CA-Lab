module cache
(
    input         clk_g     ,
    input         resetn    ,
    /*with CPU              */
    input         valid     ,
    input         op        ,
    input  [ 7:0] index     ,
    input  [19:0] tag       ,
    input  [ 3:0] offset    ,
    input  [ 3:0] wstrb     ,
    input  [31:0] wdata     ,

    output        addr_ok   ,
    output        data_ok   ,
    output [31:0] rdata     ,
    /*with AXI              */
    output        rd_req    ,
    output [ 2:0] rd_type   ,
    output [31:0] rd_addr   ,
    input         rd_rdy    ,
    input         ret_valid ,
    input         ret_last  ,
    input  [31:0] ret_data  ,

    output        wr_req    ,
    output [ 2:0] wr_type   ,
    output [31:0] wr_addr   ,
    output [ 3:0] wr_wstrb  ,
    output [127:0]wr_data   ,
    input         wr_rdy    
);

// load clash with write hit
wire        collided   ;
//cache controller
//way0_tagv_ram
wire        way0_tagv_wea;
wire [ 7:0] way0_tagv_addr;
wire [20:0] way0_tagv_in;
wire [20:0] way0_tagv_out;
//way1_tagv_ram
wire        way1_tagv_wea;
wire [ 7:0] way1_tagv_addr;
wire [20:0] way1_tagv_in;
wire [20:0] way1_tagv_out;
//way0_bank0_ram
wire [ 3:0] way0_bank0_wea;
wire [ 7:0] way0_bank0_addr;
wire [31:0] way0_bank0_in;
wire [31:0] way0_bank0_out;
//way0_bank1_ram
wire [ 3:0] way0_bank1_wea;
wire [ 7:0] way0_bank1_addr;
wire [31:0] way0_bank1_in;
wire [31:0] way0_bank1_out;
//way0_bank2_ram
wire [ 3:0] way0_bank2_wea;
wire [ 7:0] way0_bank2_addr;
wire [31:0] way0_bank2_in;
wire [31:0] way0_bank2_out;
//way0_bank3_ram
wire [ 3:0] way0_bank3_wea;
wire [ 7:0] way0_bank3_addr;
wire [31:0] way0_bank3_in;
wire [31:0] way0_bank3_out;
//way1_bank0_ram
wire [ 3:0] way1_bank0_wea;
wire [ 7:0] way1_bank0_addr;
wire [31:0] way1_bank0_in;
wire [31:0] way1_bank0_out;
//way1_bank1_ram
wire [ 3:0] way1_bank1_wea;
wire [ 7:0] way1_bank1_addr;
wire [31:0] way1_bank1_in;
wire [31:0] way1_bank1_out;
//way1_bank2_ram
wire [ 3:0] way1_bank2_wea;
wire [ 7:0] way1_bank2_addr;
wire [31:0] way1_bank2_in;
wire [31:0] way1_bank2_out;
//way1_bank3_ram
wire [ 3:0] way1_bank3_wea;
wire [ 7:0] way1_bank3_addr;
wire [31:0] way1_bank3_in;
wire [31:0] way1_bank3_out;
//way0_dirty regfile
reg [255:0] way0_dirty;
wire        way0_dirty_wea;
wire [ 7:0] way0_dirty_addr;
wire        way0_dirty_in;
wire        way0_dirty_out;
//way1_dirty regfile
reg [255:0] way1_dirty;
wire        way1_dirty_wea;
wire [ 7:0] way1_dirty_addr;
wire        way1_dirty_in;
wire        way1_dirty_out;
//request buffer
reg         reg_op     ;
reg  [ 7:0] reg_index  ;
reg  [19:0] reg_tag    ;
reg  [ 3:0] reg_offset ;
reg  [ 3:0] reg_wstrb  ;
reg  [31:0] reg_wdata  ;
//tag compare
wire        way0_v     ;
wire [19:0] way0_tag   ;
wire        way1_v     ;
wire [19:0] way1_tag   ;  
wire        way0_hit   ;
wire        way1_hit   ;
wire        cache_hit  ;
//data select
wire [ 3:0] pa         ;
wire [127:0] way0_data ;
wire [127:0] way1_data ;
wire [31:0] way0_load_word;
wire [31:0] way1_load_word;
wire [31:0] load_res   ;
wire [127:0] replace_data ;
//miss buffer
reg         replace_way;
reg  [ 2:0] ret_cnt    ; //max=4
//LFSR
reg  [ 3:1] r_lfsr     ;
wire        r_xnor     ;
//write buffer
reg  [ 7:0] reg_s_index ;
reg         reg_s_way   ;
reg  [ 3:0] reg_s_wstrb ;
reg  [31:0] reg_s_wdata ;
reg  [ 3:0] reg_s_offset;
//interface with AXI
reg         wr_req_d;


/*MAIN FSM                  */
parameter IDLE    = 5'b00001;
parameter LOOKUP  = 5'b00010;
parameter MISS    = 5'b00100;
parameter REPLACE = 5'b01000;
parameter REFILL  = 5'b10000;
reg [4:0] m_state_c;    //main FSM current state
reg [4:0] m_state_n;    //main FSM next state

always @(posedge clk_g)begin 
    if(!resetn) m_state_c <= IDLE;
    else m_state_c <= m_state_n;
end 

always @(*)begin 
    case(m_state_c)
        IDLE:begin 
            if(collided==1'b1)begin 
                m_state_n <= IDLE;
            end 
            else if(valid==1'b1)begin 
                m_state_n <= LOOKUP;
            end
            else begin  //else if(valid==1'b0)
                m_state_n <= IDLE;
            end 
        end
        LOOKUP:begin 
            if(cache_hit==1'b1 && (valid==1'b0 || collided==1'b1))begin 
                m_state_n <= IDLE;
            end 
            else if(cache_hit==1'b1 && valid==1'b1)begin 
                m_state_n <= LOOKUP;
            end
            else if(cache_hit==1'b0)begin
                m_state_n <= MISS;
            end  //no else
        end
        MISS:begin 
            if(wr_rdy==1'b0)begin 
                m_state_n <= MISS;
            end 
            else if(wr_rdy==1'b1)begin
                m_state_n <= REPLACE;
            end //no else
        end 
        REPLACE:begin 
            if(rd_rdy==1'b0)begin
                m_state_n <= REPLACE;
            end 
            else if(rd_rdy==1'b1)begin 
                m_state_n <= REFILL;
            end //no else
        end
        REFILL:begin 
            if(ret_valid==1'b0 || ret_last==1'b0)begin
                m_state_n <= REFILL;
            end 
            else if(ret_valid==1'b1 && ret_last==1'b1)begin 
                m_state_n <= IDLE;
            end 
        end 
        default: m_state_n <= IDLE;
    endcase
end 

/*Write Buffer FSM          */
parameter WIDLE = 2'b01;
parameter WRITE = 2'b10;
reg [1:0] w_state_c;    //write FSM current state
reg [1:0] w_state_n;    //write FSM next state

always @(posedge clk_g)begin 
    if(!resetn) w_state_c <= WIDLE;
    else w_state_c <= w_state_n;
end 

always @(*)begin 
    case(w_state_c)
        WIDLE:begin 
            if(m_state_c==LOOKUP && reg_op==1'b1 && cache_hit==1'b1)begin 
                w_state_n <= WRITE;
            end 
            else begin 
                w_state_n <= WIDLE;
            end 
        end
        WRITE:begin 
            if(m_state_c==LOOKUP && reg_op==1'b1 && cache_hit==1'b1)begin 
                w_state_n <= WRITE;
            end 
            else begin 
                w_state_n <= WIDLE;
            end 
        end 
        default: w_state_n <= WIDLE;
    endcase
end 

/*load clash with hit write*/
assign collided = (m_state_c==LOOKUP && reg_op==1'b1 /*&& cache_hit==1'b1*/ && valid==1'b1 && op==1'b0 && offset[3:2]==reg_offset[3:2]) |
                  (w_state_c==WRITE && valid==1'b1 && op==1'b0 && offset[3:2]==reg_offset[3:2]);

/*cache controller              */
//way0_tagv_ram
assign way0_tagv_wea = (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b0) ? 1'b1 : 1'b0;
assign way0_tagv_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                        (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b0) ? reg_index : 8'b0;
assign way0_tagv_in = (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b0) ? {reg_tag,1'b1} : 20'b0;
//way1_tagv_ram
assign way1_tagv_wea = (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b1) ? 1'b1 : 1'b0;
assign way1_tagv_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                        (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b1) ? reg_index : 8'b0;
assign way1_tagv_in = (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b1) ? {reg_tag,1'b1} : 20'b0;
//way0_bank0_ram
assign way0_bank0_wea = (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd0) ? reg_s_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b0 && reg_op==1'b1 && reg_offset[3:2]==2'd0) ? reg_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b0) ? 4'b1111 : 4'b0;
assign way0_bank0_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                         (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                         (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd0) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b0) ? reg_index : 8'b0;
assign way0_bank0_in = (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd0) ? reg_s_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b0 && reg_op==1'b1 && reg_offset[3:2]==2'd0) ? reg_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b0) ? ret_data : 32'b0;
//way0_bank1_ram
assign way0_bank1_wea = (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd1) ? reg_s_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b0 && reg_op==1'b1 && reg_offset[3:2]==2'd1) ? reg_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b0) ? 4'b1111 : 4'b0;
assign way0_bank1_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                         (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                         (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd1) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b0) ? reg_index : 8'b0;
assign way0_bank1_in = (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd1) ? reg_s_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b0 && reg_op==1'b1 && reg_offset[3:2]==2'd1) ? reg_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b0) ? ret_data : 32'b0;
//way0_bank2_ram
assign way0_bank2_wea = (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd2) ? reg_s_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b0 && reg_op==1'b1 && reg_offset[3:2]==2'd2) ? reg_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b0) ? 4'b1111 : 4'b0;
assign way0_bank2_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                         (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                         (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd2) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b0) ? reg_index : 8'b0;
assign way0_bank2_in = (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd2) ? reg_s_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b0 && reg_op==1'b1 && reg_offset[3:2]==2'd2) ? reg_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b0) ? ret_data : 32'b0;
//way0_bank3_ram
assign way0_bank3_wea = (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd3) ? reg_s_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b0 && reg_op==1'b1 && reg_offset[3:2]==2'd3) ? reg_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b0) ? 4'b1111 : 4'b0;
assign way0_bank3_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                         (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                         (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd3) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b0) ? reg_index : 8'b0;
assign way0_bank3_in = (w_state_c==WRITE && reg_s_way==1'b0 && reg_s_offset[3:2]==2'd3) ? reg_s_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b0 && reg_op==1'b1 && reg_offset[3:2]==2'd3) ? reg_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b0) ? ret_data : 32'b0;
//way1_bank0_ram
assign way1_bank0_wea = (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd0) ? reg_s_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b1 && reg_op==1'b1 && reg_offset[3:2]==2'd0) ? reg_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b1) ? 4'b1111 : 4'b0;
assign way1_bank0_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                         (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                         (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd0) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b1) ? reg_index : 8'b0;
assign way1_bank0_in = (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd0) ? reg_s_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b1 && reg_op==1'b1 && reg_offset[3:2]==2'd0) ? reg_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd0 && replace_way==1'b1) ? ret_data : 32'b0;
//way1_bank1_ram
assign way1_bank1_wea = (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd1) ? reg_s_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b1 && reg_op==1'b1 && reg_offset[3:2]==2'd1) ? reg_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b1) ? 4'b1111 : 4'b0;
assign way1_bank1_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                         (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                         (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd1) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b1) ? reg_index : 8'b0;
assign way1_bank1_in = (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd1) ? reg_s_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b1 && reg_op==1'b1 && reg_offset[3:2]==2'd1) ? reg_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd1 && replace_way==1'b1) ? ret_data : 32'b0;
//way1_bank2_ram
assign way1_bank2_wea = (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd2) ? reg_s_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b1 && reg_op==1'b1 && reg_offset[3:2]==2'd2) ? reg_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b1) ? 4'b1111 : 4'b0;
assign way1_bank2_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                         (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                         (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd2) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b1) ? reg_index : 8'b0;
assign way1_bank2_in = (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd2) ? reg_s_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b1 && reg_op==1'b1 && reg_offset[3:2]==2'd2) ? reg_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd2 && replace_way==1'b1) ? ret_data : 32'b0;
//way1_bank3_ram
assign way1_bank3_wea = (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd3) ? reg_s_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b1 && reg_op==1'b1 && reg_offset[3:2]==2'd3) ? reg_wstrb : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b1) ? 4'b1111 : 4'b0;
assign way1_bank3_addr = ((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0)) ? index : 
                         (m_state_c==MISS && wr_rdy==1'b1) ? reg_index : 
                         (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd3) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b1) ? reg_index : 8'b0;
assign way1_bank3_in = (w_state_c==WRITE && reg_s_way==1'b1 && reg_s_offset[3:2]==2'd3) ? reg_s_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b1 && reg_op==1'b1 && reg_offset[3:2]==2'd3) ? reg_wdata : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==3'd3 && replace_way==1'b1) ? ret_data : 32'b0;
//way0_dirty regfile
assign way0_dirty_wea = (w_state_c==WRITE && reg_s_way==1'b0) ? 1'b1 : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b0) ? 1'b1 : 1'b0;
assign way0_dirty_addr = (m_state_c==REPLACE) ? reg_index : //next clk of (m_state_c==MISS && wr_rdy==1'b1)
                         (w_state_c==WRITE && reg_s_way==1'b0) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b0) ? reg_index : 8'b0;
assign way0_dirty_in = (w_state_c==WRITE && reg_s_way==1'b0) ? 1'b1 : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b0 && reg_op==1'b1) ? 1'b1 : 1'b0;
//way1_dirty regfile
assign way1_dirty_wea = (w_state_c==WRITE && reg_s_way==1'b1) ? 1'b1 : 
                        (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b1) ? 1'b1 : 1'b0;
assign way1_dirty_addr = (m_state_c==REPLACE) ? reg_index : //next clk of (m_state_c==MISS && wr_rdy==1'b1)
                         (w_state_c==WRITE && reg_s_way==1'b1) ? reg_s_index : 
                         (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b1) ? reg_index : 8'b0;
assign way1_dirty_in = (w_state_c==WRITE && reg_s_way==1'b1) ? 1'b1 : 
                       (m_state_c==REFILL && ret_valid==1'b1 && ret_last==1'b1 && replace_way==1'b1 && reg_op==1'b1) ? 1'b1 : 1'b0;
/*way0_tagv_ram             */
way0_tagv way0_tagv(
    .clka (clk_g         ),
    .wea  (way0_tagv_wea ),
    .addra(way0_tagv_addr),
    .dina (way0_tagv_in  ),
    .douta(way0_tagv_out )
);
/*way1_tagv_ram             */
way1_tagv way1_tagv(
    .clka (clk_g         ),
    .wea  (way1_tagv_wea ),
    .addra(way1_tagv_addr),
    .dina (way1_tagv_in  ),
    .douta(way1_tagv_out )
);
/*way0_bank0_ram             */
way0_bank0 way0_bank0(
    .clka (clk_g          ),
    .wea  (way0_bank0_wea ),
    .addra(way0_bank0_addr),
    .dina (way0_bank0_in  ),
    .douta(way0_bank0_out )
);
/*way0_bank1_ram             */
way0_bank1 way0_bank1(
    .clka (clk_g          ),
    .wea  (way0_bank1_wea ),
    .addra(way0_bank1_addr),
    .dina (way0_bank1_in  ),
    .douta(way0_bank1_out )
);
/*way0_bank2_ram             */
way0_bank2 way0_bank2(
    .clka (clk_g          ),
    .wea  (way0_bank2_wea ),
    .addra(way0_bank2_addr),
    .dina (way0_bank2_in  ),
    .douta(way0_bank2_out )
);
/*way0_bank3_ram             */
way0_bank3 way0_bank3(
    .clka (clk_g          ),
    .wea  (way0_bank3_wea ),
    .addra(way0_bank3_addr),
    .dina (way0_bank3_in  ),
    .douta(way0_bank3_out )
);
/*way1_bank0_ram             */
way1_bank0 way1_bank0(
    .clka (clk_g          ),
    .wea  (way1_bank0_wea ),
    .addra(way1_bank0_addr),
    .dina (way1_bank0_in  ),
    .douta(way1_bank0_out )
);
/*way1_bank1_ram             */
way1_bank1 way1_bank1(
    .clka (clk_g          ),
    .wea  (way1_bank1_wea ),
    .addra(way1_bank1_addr),
    .dina (way1_bank1_in  ),
    .douta(way1_bank1_out )
);
/*way1_bank2_ram             */
way1_bank2 way1_bank2(
    .clka (clk_g          ),
    .wea  (way1_bank2_wea ),
    .addra(way1_bank2_addr),
    .dina (way1_bank2_in  ),
    .douta(way1_bank2_out )
);
/*way1_bank3_ram             */
way1_bank3 way1_bank3(
    .clka (clk_g          ),
    .wea  (way1_bank3_wea ),
    .addra(way1_bank3_addr),
    .dina (way1_bank3_in  ),
    .douta(way1_bank3_out )
);
/*way0_dirty regfile        */
//WRITE
always @(posedge clk_g)begin 
    if(!resetn)begin 
        way0_dirty <= 256'b0; 
    end 
    else if(way0_dirty_wea)begin 
        way0_dirty[way0_dirty_addr+:1] <= way0_dirty_in;
    end 
end 
//READ
assign way0_dirty_out = way0_dirty[way0_dirty_addr+:1];
/*way1_ditry regfile        */
//WRITE
always @(posedge clk_g)begin 
    if(!resetn)begin 
        way1_dirty <= 256'b0; 
    end 
    else if(way1_dirty_wea)begin 
        way1_dirty[way1_dirty_addr+:1] <= way1_dirty_in;
    end 
end 
//READ
assign way1_dirty_out = way1_dirty[way1_dirty_addr+:1];


/*data path                     */
/*Request Buffer            */
always @(posedge clk_g)begin                
    if((m_state_c==IDLE && valid==1'b1) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0))begin 
        reg_op <= op;
        reg_index <= index;
        reg_tag <= tag;
        reg_offset <= offset;
        reg_wstrb <= wstrb;
        reg_wdata <= wdata;
    end 
    else begin
        reg_op <= reg_op;
        reg_index <= reg_index;
        reg_tag <= reg_tag;
        reg_offset <= reg_offset;
        reg_wstrb <= reg_wstrb;
        reg_wdata <= reg_wdata;
    end 
end 
/*Tag Compare               */  //unconsider uncache
assign way0_v = way0_tagv_out[0];
assign way0_tag = way0_tagv_out[20:1];
assign way1_v = way1_tagv_out[0];
assign way1_tag = way1_tagv_out[20:1];
assign way0_hit = way0_v && (way0_tag == reg_tag);
assign way1_hit = way1_v && (way1_tag == reg_tag);
assign cache_hit = way0_hit || way1_hit;
/*Data Select               */
assign pa = reg_offset;
assign way0_data = {way0_bank3_out,way0_bank2_out,way0_bank1_out,way0_bank0_out};
assign way1_data = {way1_bank3_out,way1_bank2_out,way1_bank1_out,way1_bank0_out};
assign way0_load_word = way0_data[pa[3:2]*32 +: 32];
assign way1_load_word = way1_data[pa[3:2]*32 +: 32];
assign load_res = {{32{way0_hit}} & way0_load_word} | 
                  {{32{way1_hit}} & way1_load_word} | 
                  {{32{ret_valid}}& ret_data      } ;
assign replace_data = replace_way ? way1_data : way0_data;
/*Miss Buffer               */
always @(posedge clk_g)begin 
    if(m_state_c==MISS && wr_rdy==1'b1)begin 
        replace_way <= r_lfsr[1]; //p(0)=4/7,p(1)=3/7
    end 
    else begin 
        replace_way <= replace_way;
    end 
end 
always @(posedge clk_g)begin 
    if(m_state_c==REPLACE && rd_rdy==1'b1)begin 
        ret_cnt <= 3'b0;
    end 
    else if(ret_valid==1'b1)begin
        ret_cnt <= ret_cnt + 3'b1;
    end 
end 
/*LFSR                      */
always @(posedge clk_g)begin 
    if(!resetn)begin 
        r_lfsr <= 3'b0;
    end 
    else begin 
        r_lfsr <= {r_lfsr[2:1],r_xnor};
    end 
end 
assign r_xnor = r_lfsr[3] ^~ r_lfsr[2];
/*Write Buffer              */
always @(posedge clk_g)begin 
    if(m_state_c==LOOKUP && reg_op==1'b1 && cache_hit==1'b1)begin 
        reg_s_index <= reg_index;
        reg_s_way <= way0_hit ? 1'b0 : 1'b1;
        reg_s_wstrb <= reg_wstrb;
        reg_s_wdata <= reg_wdata;
        reg_s_offset <= reg_offset;
    end 
    else begin 
        reg_s_index <= reg_s_index;
        reg_s_way <= reg_s_way;
        reg_s_wstrb <= reg_s_wstrb;
        reg_s_wdata <= reg_s_wdata;
        reg_s_offset <= reg_s_offset;
    end 
end 

/*interface                     */
/*interface with CPU        */
assign addr_ok = (m_state_c==IDLE) || (m_state_c==LOOKUP && cache_hit==1'b1 && valid==1'b1 && collided==1'b0);
assign data_ok = (m_state_c==LOOKUP && cache_hit==1'b1) /*|| (m_state_c==LOOKUP && reg_op==1'b1)*/ || (m_state_c==REFILL && ret_valid==1'b1 && ret_cnt==reg_offset[3:2]);
assign rdata = load_res;
/*interface with AXI        */
assign rd_req = (m_state_c==REPLACE);
assign rd_type = 3'b100; //unconsider uncache
assign rd_addr = {reg_tag,reg_index,4'b0};

always @(posedge clk_g)begin 
    if(!resetn)begin 
        wr_req_d<= 1'b0;
    end 
    else if(m_state_c==MISS && wr_rdy==1'b1)begin 
        wr_req_d<= 1'b1;
    end 
    else if(wr_rdy==1'b1)begin 
        wr_req_d<= 1'b0;
    end 
end 
assign wr_req = (wr_req_d==1'b1) && ((replace_way==1'b0 && way0_v==1'b1 && way0_dirty_out==1'b1) || (replace_way==1'b1 && way1_v==1'b1 && way1_dirty_out==1'b1));
assign wr_type = 3'b100; //unconsider uncache
assign wr_addr = (replace_way==1'b0) ? {way0_tag,reg_index,4'b0} : {way1_tag,reg_index,4'b0};
assign wr_wstrb = 4'b1111; //meaningless
assign wr_data = replace_data;

endmodule