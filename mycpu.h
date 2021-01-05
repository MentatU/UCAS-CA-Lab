`ifndef MYCPU_H
    `define MYCPU_H
    
    `define BR_BUS_WD       35   
    `define FS_TO_DS_BUS_WD 104
    `define DS_TO_ES_BUS_WD 211  
    `define ES_TO_MS_BUS_WD 139   
    `define MS_TO_WS_BUS_WD 132 
    `define WS_TO_RF_BUS_WD 41 
    `define FORWARD_BUS_WD 41  
    `define WS_TO_CP0_BUS_WD 243
    `define CP0_TO_WS_BUS_WD 320
    
    `define CR_STATUS 96
    `define CR_CAUSE 104
    `define CR_EPC 112
    `define CR_BADVADDR 64
    `define CR_COUNT 72
    `define CR_COMPARE 88
    `define CR_INDEX 0
    `define CR_ENTRYLO0 16
    `define CR_ENTRYLO1 24
    `define CR_ENTRYHI 80
    
    `define EX_INT 0
    `define EX_ADEL 4    
    `define EX_ADES 5  
    `define EX_OV 12  
    `define EX_SYS 8  
    `define EX_BP 9   
    `define EX_RI 10
    `define EX_TLBL 2
    `define EX_TLBS 3
    `define EX_MOD 1
`endif
