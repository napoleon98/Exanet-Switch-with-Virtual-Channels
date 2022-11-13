`timescale 1ns / 1ps



module haser_for_input_arbiter_before_change_in_has_packet_drop #(

    parameter vc_num   = 3,
    parameter prio_num = 2,
    parameter output_num = 8
)(
  input                                        clk,
  input                                        resetn,
  input                                        last,
  input                                        fixed_vcs_enable,
  input [(vc_num*prio_num)-1:0]                fixed_vcs,
  input                                        initialize,
  input [$clog2(vc_num*prio_num)-1:0]          selected_vc,
  input                                        cts,
    
  output [vc_num*prio_num-1:0]                 o_has_packet,
  output  logic [$clog2(output_num)-1 :0]      dest_i [prio_num*vc_num-1 :0],
  output  logic [$clog2(vc_num*prio_num)-1:0]  output_vc_i [vc_num*prio_num-1:0]

);
 reg [$clog2(vc_num*prio_num)-1 :0] rand_vc_dest   = 0;
 reg [$clog2(output_num)-1 :0]      rand_dest      = 0;
 reg [$clog2(vc_num*prio_num)-1 :0] rand_vc_2      = 0;
 genvar i; 
 /* ***************************************************** TASK DESTER ************************************************************/
   task dester(input fixed_dest_enable, input [$clog2(output_num)-1 :0] fixed_dest, input fixed_vc_enable, input[$clog2(prio_num*vc_num)-1 :0] fixed_vc,input initialize );begin
     if(initialize) begin
       for(int i=0;i<prio_num*vc_num;i++)begin
         dest_i[i]        = 0;
       end
     end
     else begin
       if(fixed_dest_enable & !fixed_vc_enable ) begin
         rand_vc_dest = $urandom() % (prio_num*vc_num);
         dest_i[rand_vc_dest]    = fixed_dest;
      
       
       end
       if(fixed_vc_enable & !fixed_dest_enable ) begin
         rand_dest = $urandom() % (output_num);
         dest_i[fixed_vc]   = rand_dest;
       
       end
       if(fixed_dest_enable & fixed_vc_enable )begin
         dest_i[fixed_vc]   = fixed_dest;
       
       end  
       if(!fixed_dest_enable & !fixed_vc_enable )begin
         rand_dest = $urandom() % (output_num);
         rand_vc_dest = $urandom() % (prio_num*vc_num);
         dest_i[rand_vc_dest]    = rand_dest;
       
       end 
     end  
   end
   endtask
 
 
  /* ***************************************************** TASK output_vcer ************************************************************/
  task output_vcer(input fixed_vc_enable, input[$clog2(prio_num*vc_num)-1 :0] fixed_vc, input initialize);begin
    if(initialize) begin
      for(int i=0;i<prio_num*vc_num;i++)begin
        output_vc_i[i]     = 0;
      end
   end
   else begin
     if(fixed_vc_enable)begin
       output_vc_i[fixed_vc] = fixed_vc; //same input and output vc
       
     end
     else begin
       rand_vc_2 = $urandom() % (prio_num*vc_num);
       output_vc_i[rand_vc_2]  = rand_vc_2;
       
     end  
   end    
  end 
  endtask
  








  
  reg [1:0]                    state_q [vc_num*prio_num -1:0];
  reg [(vc_num*prio_num)-1 :0] rand_vc;
  
  logic [1:0]                  state_d [vc_num*prio_num -1:0]; 
  logic [vc_num*prio_num-1:0]  has_packet; 
  logic [vc_num*prio_num-1:0]  fixed_has_packets;
  logic flag = 0;
  
  localparam HAS_HIGH = 2'b01,
             HAS_LOW  = 2'b00,
             GRANTED  = 2'b10;
  
  
  
  //genvar i; 
  generate
    for(i=0;i<prio_num*vc_num;i++)begin  
      always @(posedge clk) begin
        if (~resetn) 
          state_q[i] <=  HAS_LOW;
        else
          state_q[i] <=  state_d[i];
      end
    end
  endgenerate
   
  always_ff @(posedge clk) begin
    if(!resetn)
      rand_vc <= 0;
    else
      rand_vc <= $urandom();
  end
  //Generate as many fsms as the number of VCs(prio_num*vc_num) 
  generate
  for(i=0;i<prio_num*vc_num;i++)begin  
    always_comb begin
      state_d[i] = state_q[i];
      case(state_q[i])
        HAS_LOW:
          if(!initialize & (rand_vc[i] != 0))
            state_d[i] = HAS_HIGH;
          else
            state_d[i] = HAS_LOW;
        HAS_HIGH:
          if(cts & (selected_vc == i))begin
            state_d[i] = GRANTED;
          end
          else
            state_d[i] = HAS_HIGH;
             
        GRANTED:
          if(last)
            state_d[i] = HAS_LOW;
          else
            state_d[i] = GRANTED; 
        default:
          state_d[i] = HAS_LOW;
      endcase
    end
  end
  endgenerate
  
  // generate one controller for each VC
  generate 
    for(i=0;i<prio_num*vc_num;i++)begin
      always_comb begin 
        if(state_q[i] == HAS_LOW)begin
          has_packet[i] = 0;
          if(!fixed_vcs_enable) // ! is wrong?
            fixed_has_packets[i] = fixed_vcs[i];
        end      
        if(state_q[i] == HAS_HIGH)begin
          has_packet[i] = 1;
          /*generate a destination and an output vc*/
          dester(.fixed_dest_enable(0),.fixed_dest(0),.fixed_vc_enable(1),.fixed_vc(i),.initialize(0)); //****** CHANGE******
          output_vcer(.fixed_vc_enable(1), .fixed_vc(i), .initialize(0));//****** CHANGE******
        end
        if(state_q == GRANTED) begin
          if(!fixed_vcs_enable)begin
            if(last)
              has_packet[i] = 0;
            else begin
              has_packet[i] = 1;
              /* Dest and output_vc are lost after the first cycle, that's why the below tasks are called again with 0 as argument of fixed values*/
              dester(.fixed_dest_enable(1),.fixed_dest(0),.fixed_vc_enable(1),.fixed_vc(i),.initialize(0));//****** CHANGE******
              output_vcer(.fixed_vc_enable(1), .fixed_vc(0), .initialize(0));//****** CHANGE******
            end
          end 
          else begin
            if(last)
              fixed_has_packets[i] = 0;
            else
              fixed_has_packets[i] = 1;
          end
        end
      end
    end 
  endgenerate 
  
    assign o_has_packet = (fixed_vcs_enable) ?  fixed_has_packets : has_packet; 
    
    
    
    
    
    
    
endmodule
