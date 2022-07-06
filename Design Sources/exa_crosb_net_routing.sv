//---------------------------------------------------------------------------
// File net_routing.v
//---------------------------------------------------------------------------
//
`timescale 1ns/1ns

import exanet_pkg::*;
import exanet_crosb_pkg::*;

`define DST_X_RANGE 	24:21
`define DST_Y_RANGE 	28:25 
`define DST_Z_RANGE 	32:29 
`define DST_OFF_RANGE 	34:33
`define PATH_RANGE 	    111:109


module exa_crosb_net_routing #(
	parameter TDEST_WIDTH       = 3,
    parameter REG_DQ            = 1,
    parameter INPUT_PORT_NUMBER = 0,
    parameter output_num        = 4,
    parameter max_ports         = 32,
	parameter [41:0] PORTx_LOW_ADDR  [max_ports] = {0} ,
    parameter [41:0] PORTx_HIGH_ADDR [max_ports] = {0} ,
    parameter reg_enable           = 0                  ,
    parameter DEBUG                = "false"     
	)( 
	input                        	Clk,
	input                        	Reset,
	input      [127:0]           	i_header,
	output     [127:0]           	o_header,    //modified header with the bit indicating if packet has been multipathed.
	input                        	i_hdr_valid,
	input      [ 21:0]           	i_src_coord,
	output  wire                    o_prio,
	output  [TDEST_WIDTH-1:0] 	    o_tdest,
	output reg 		      	        o_dec_error,
	input  cntrl_info_t             i_cntrl_info,
	output                          o_dest_valid
);
  `include "switch_packet.h"
	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  logic [TDEST_WIDTH-1:0] 	tdest_d;	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  logic                 	dec_err_d;

	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [3:0] local_x  = i_src_coord[3:0]; 	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [3:0] local_y  = i_src_coord[7:4]; 	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [3:0] local_z  = i_src_coord[11:8]; 	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [1:0] local_off= i_src_coord[13:12]; 	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [5:0] local_tor= i_src_coord[21:14];  
	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [3:0] dst_x    = i_header[`DST_X_RANGE];	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
    wire [3:0] dst_y    = i_header[`DST_Y_RANGE];	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [3:0] dst_z    = i_header[`DST_Z_RANGE];	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [1:0] dst_off  = i_header[`DST_OFF_RANGE];

  //bits indicating what path this packet should follow. if "0" then its the minimal path.	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [2:0] path     = i_header[`PATH_RANGE];   

  //if the switch has multipathing enabled, then the header is going to be modified regardless
  assign o_header = ((i_cntrl_info.multipath_enable != 0)&(i_cntrl_info.is_inter_router)) ? {i_header[127:112],3'b000,i_header[108:0]} : i_header;
	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [ 4:0] pkt_type = i_header[`PKT_TYPE_RANGE];	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [13:0] pkt_size = i_header[`PKT_SIZE_RANGE];
	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [9:0]  small_addr   = i_header[71:62] ; 	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [41:0] big_addr     = i_header[`PKT_DST_VA_RANGE] ;	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire [41:0] exa_addr	   = (pkt_type >= 10) ? {3'b111,29'b0,small_addr} : big_addr ; 

	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  wire prio_d = (pkt_type > 16); // assign high priority to packets with high pkat type number	
  (* KEEP = DEBUG *) (* MARK_DEBUG = DEBUG *)
  reg prio_q;  
  assign o_prio = (o_dest_valid)? prio_d : prio_q  ;   
  
  always @(posedge Clk) begin
    if (Reset)
      prio_q <= 0;
    else begin
      if (o_dest_valid)
        prio_q <= prio_d;
    end    
  end
  
  integer i;   
  always_comb begin  
    tdest_d   = 0;
    dec_err_d = 1;
    for (i = 0; i< output_num ; i = i + 1) begin
      if ( (exa_addr >= PORTx_LOW_ADDR[i])&&(exa_addr <= PORTx_HIGH_ADDR[i]) ) begin
        tdest_d    = i; 
        dec_err_d  = 0;
      end
    end
  end     
  
  
   
  logic  [TDEST_WIDTH-1:0]   tdest_var;
  logic                      dec_error_var;    
  
  always_comb begin        
    tdest_var     = 0;
    dec_error_var = 0;
    if (i_hdr_valid) begin
      /*-----------------------------------------------*/
      /*IF this is the Network FPGA Router (INTER-QFDB)*/
      if (i_cntrl_info.is_inter_router) begin
        /*first see if its for this QFDB*/
        if ((dst_y == local_y) & (dst_x == local_x)) begin
          /*if yes, then route to the apropriate port based on dest FPGA*/
          if (dst_off == 0)
            tdest_var      =  i_cntrl_info.local_port;   //f1
          else if (dst_off == 1)
            tdest_var      =  i_cntrl_info.local_port+1; //f2
          else if (dst_off == 2)
            tdest_var      =  i_cntrl_info.local_port+2; //f3
          else
            tdest_var      =  i_cntrl_info.local_port+3; //f4
          dec_error_var  =  0;
        end
        /*otherwise route on the correct mezz*/
        /*do multipathing if enabled and if set*/
        else if ((i_cntrl_info.multipath_enable !=0)&(path!=0)) begin
          dec_error_var  =  0;
          if (path == 1) //has to go thgrough A (x0)
            tdest_var  =  i_cntrl_info.dest_x0_port;
          if (path == 2) //has to go thgrough B (x1)
            tdest_var  =  i_cntrl_info.dest_x1_port;
          if (path == 3) //has to go thgrough D (x2)
            tdest_var  =  i_cntrl_info.dest_x2_port;
          if (path == 4) //has to go thgrough C (x3)
            tdest_var  =  i_cntrl_info.dest_x3_port;
        end
        /*else do the normal routing*/
        else if (dst_y != local_y) begin               
          tdest_var  =  i_cntrl_info.dest_y_port;
          dec_error_var <=  0;
        end
        /*otherwise, route on the correct QFDB*/
        else if (dst_x == 0) begin
          tdest_var     =  i_cntrl_info.dest_x0_port;
          dec_error_var =  0;
        end else if (dst_x == 1) begin 
          tdest_var     =  i_cntrl_info.dest_x1_port;
          dec_error_var =  0;
        end else if (dst_x == 2) begin
          tdest_var     =  i_cntrl_info.dest_x2_port;
          dec_error_var =  0;
        end else if (dst_x == 3) begin
          tdest_var     =  i_cntrl_info.dest_x3_port;
          dec_error_var =  0;
        end else begin
          tdest_var     =  15;
          dec_error_var =  1;
        end
      end
      /*----------------------------*/
      /*else, if this a Central FPGA*/
      else if (i_cntrl_info.is_central_router) begin
        dec_error_var = 0;
        tdest_var     = dst_y;
      end 
      /*------------------------------------------*/
      /*Else, this is the NI crossbar  */            
      else begin               
        /*first see if the packet is for enother qfdb or mezz*/
        if ((local_x != dst_x) | (local_y != dst_y)) begin
          /* Send to F1  by using port 0. In F1, port 0 should be connected to the
          inter router.*/
          tdest_var     =  0;
          dec_error_var =  0;
        /*then see if the packet is for enother FPGA within this Q*/
        end else if (local_off != dst_off) begin
          if (local_off==0) begin //this is a F1 so again go to the inter router.
            tdest_var     =  0;
            dec_error_var =  0;
          end else begin          
            tdest_var      =  dst_off ;
            dec_error_var  =  0;
          end        
        /*finaly, if none of the above, then route it localy*/
        end else begin
          tdest_var     =  tdest_d;
          dec_error_var =  dec_err_d;  
        end 
      end            
    end
  end
   
    
    
  generate
  if (reg_enable) begin 
    reg  [TDEST_WIDTH-1:0] 	tdest_q;
    reg                     dec_error_q;
    reg                     dest_valid_q;

    assign o_tdest     = tdest_q;

    always_ff @(posedge Clk) begin
      if (Reset) begin
        tdest_q      <= 0;
      end else begin
        tdest_q     <= tdest_var; 
      end
    end
    
    always_ff @(posedge Clk) begin
      if (Reset) 
        dest_valid_q <= 0;
      else
        if (~dest_valid_q & i_hdr_valid)  //if this is the first time, then raise the ready 
          dest_valid_q <= 1;
        else if (~i_hdr_valid)            // and keep it like that untill header valid drops
          dest_valid_q <= 0;  
    end  
    
    assign o_dest_valid = (dest_valid_q & i_hdr_valid) & (!o_dec_error) & (!dec_error_var);
    assign o_tdest      = tdest_q;
  end else begin// I'm here, with reg_eneble = 0
     assign o_dest_valid = i_hdr_valid & (!o_dec_error) & (!dec_error_var) ;
     assign o_tdest      = tdest_var;
  end
  
  always_ff @(posedge Clk) begin
    if (Reset) 
      o_dec_error <= 0;
    else
      if (dec_error_var)   
        o_dec_error <= 1 ;
  end  
  
  
  endgenerate     
 
    
    
    
endmodule
