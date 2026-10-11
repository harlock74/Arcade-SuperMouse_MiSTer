// SPDX-License-Identifier: GPL-3.0-or-later
// Super Mouse original-program witnesses and exclusive CPU-port transactions.
module supermouse_hiscore_manager(
 input wire clk,reset,qualified,
 input wire [15:0] cpu_a,input wire [7:0] cpu_di,cpu_do,
 input wire m1_n,mreq_n,rd_n,wr_n,rfsh_n,busak_n,
 input wire published_valid,pending_load,
 input wire [7:0] restore_data,
 output wire [1:0] restore_address,
 output reg capture_begin=0,capture_write=0,capture_end=0,restore_done=0,
 output reg [1:0] capture_address=0,
 output reg [7:0] capture_data=0,
 output wire busrq_n,owns,restore_lock,
 output wire [15:0] manager_a,
 output wire [7:0] manager_do,
 output wire manager_rd_n,manager_wr_n,
 output reg fault=0
);
 wire reading=!mreq_n && !rd_n && wr_n && rfsh_n;
 wire writing=!mreq_n && !wr_n && rd_n && rfsh_n;
 reg was_read=0,was_write=0;
 reg [15:0] read_address=0;
 reg read_opcode=0;
 // First opcode byte emits the instruction event; DD/FD, CB and ED
 // continuation bytes do not masquerade as a new instruction entry.
 reg [2:0] prefix=0;
 reg init_return=0;
 reg [2:0] boot_clear=0;
 reg [5:0] boot_hud=0,copy_hud=0;
 reg [2:0] copy_hud_count=0;
 reg initialized=0;
 reg [2:0] copy_phase=0;
 reg [4:0] state=0;
 reg restoring=0;
 reg [3:0] pos=0;
 reg significant_seen=0;
 reg [5:0] hud_blank_mask=0;
 reg [9:0] budget=0;
 localparam IDLE=0,GRANT=1,DRAIN1=2,DRAIN2=3,BEGIN=4,
  READ1=5,READ2=6,READ3=7,READ4=8,
  WRITE1=9,WRITE2=10,WRITE3=11,
  CHECK1=12,CHECK2=13,CHECK3=14,CHECK4=15,
  END1=16,END2=17,END3=18;
 assign busrq_n=state==IDLE;
 assign owns=state>=BEGIN && state<=END1;
 assign restore_lock=state!=IDLE && restoring;
 function [1:0] hud_score_byte(input [3:0] n);
  begin case(n)
   3,4:hud_score_byte=2;5,6:hud_score_byte=1;
   default:hud_score_byte=0;
  endcase end
 endfunction
 function [2:0] hud_index(input [3:0] n);
  begin case(n)
   3:hud_index=0;4:hud_index=1;5:hud_index=2;
   6:hud_index=3;7:hud_index=4;8:hud_index=5;
   default:hud_index=0;
  endcase end
 endfunction
 assign restore_address=pos<3 ? pos[1:0] : hud_score_byte(pos);
 function [15:0] hud_address(input [3:0] n);
  begin case(n)
   0:hud_address=16'h9221;1:hud_address=16'h9201;
   2:hud_address=16'h91e1;3:hud_address=16'h91c1;
   4:hud_address=16'h91a1;default:hud_address=16'h9181;
  endcase end
 endfunction
 function [5:0] hud_bit(input [15:0] a);
  begin case(a)
   16'h9221:hud_bit=6'b000001;16'h9201:hud_bit=6'b000010;
   16'h91e1:hud_bit=6'b000100;16'h91c1:hud_bit=6'b001000;
   16'h91a1:hud_bit=6'b010000;16'h9181:hud_bit=6'b100000;
   default:hud_bit=0;
  endcase end
 endfunction
 assign manager_a=restoring && pos>=3 ? hud_address(pos-4'd3) :
                  16'h804a+{12'd0,pos};
 wire [7:0] hud_digit=pos[0] ? {4'd0,restore_data[7:4]} :
                               {4'd0,restore_data[3:0]};
 wire hud_write_blank=pos<8 && hud_digit==0 && !significant_seen;
 wire hud_check_blank=hud_blank_mask[hud_index(pos)];
 assign manager_do=!restoring || pos<3 ? restore_data :
                   ((state>=CHECK1 && state<=CHECK4 ? hud_check_blank : hud_write_blank)
                    ? 8'h24 : hud_digit);
 assign manager_rd_n=!(state==READ1 || state==READ2 ||
                       state==CHECK1 || state==CHECK2);
 assign manager_wr_n=state!=WRITE1;
 always @(posedge clk)begin
  capture_begin<=0;capture_write<=0;capture_end<=0;restore_done<=0;
  was_read<=reading;was_write<=writing;
  if(reset || !qualified)begin
   was_read<=0;was_write<=0;prefix<=0;state<=IDLE;budget<=0;
  boot_clear<=0;boot_hud<=0;copy_hud<=0;copy_hud_count<=0;copy_phase<=0;
   init_return<=0;initialized<=0;fault<=0;restoring<=0;
   significant_seen<=0;hud_blank_mask<=0;
  end else begin
   if(state!=IDLE)begin
    budget<=budget+1'b1;
    if(budget==1023)begin fault<=1;state<=IDLE;end
   end else budget<=0;
   if(!owns && busak_n)begin
    if(reading && !was_read)begin read_address<=cpu_a;read_opcode<=!m1_n;end
    if(!reading && was_read && read_opcode)begin
     if(prefix==0)begin
      if(read_address==16'h000e && !initialized) init_return<=1;
      if(read_address==16'h29de && !initialized)begin
       if(init_return && boot_clear==3'b111 && boot_hud==6'b111111)begin
        initialized<=1;
        if(published_valid && state==IDLE)begin
         restoring<=1;state<=GRANT;pos<=0;
        end
       end else fault<=1;
      end
      if(initialized && state==IDLE && read_address==16'h2b4c)begin
       copy_phase<=1;copy_hud<=0;copy_hud_count<=0;
      end
      if(read_address==16'h2b63 && copy_phase==1)copy_phase<=2;
      if(read_address==16'h2b7f)begin
       if(copy_phase==6 && copy_hud==6'b111111 && state==IDLE)begin
        restoring<=0;state<=GRANT;pos<=0;
        copy_phase<=0;
       end
      end
     end
     if(prefix==2)prefix<=0;
     else if(cpu_di==8'hdd || cpu_di==8'hfd)prefix<=1;
     else if(cpu_di==8'hcb && prefix==1)prefix<=3;
     else if(cpu_di==8'hcb || cpu_di==8'hed)prefix<=2;
     else prefix<=0;
    end else if(!reading && was_read && prefix==3)prefix<=4;
    else if(!reading && was_read && prefix==4)prefix<=0;
    if(writing && !was_write)begin
     if(!initialized)begin
      if(init_return)begin
       if(cpu_do==0)begin
        case(cpu_a)
         16'h804a:boot_clear[0]<=1;
         16'h804b:boot_clear[1]<=1;
         16'h804c:boot_clear[2]<=1;
         default:;
        endcase
       end
       boot_hud<=boot_hud | hud_bit(cpu_a);
      end
     end
     if(copy_phase>=2)begin
      if(cpu_a>=16'h804a && cpu_a<=16'h804c)begin
       if(copy_phase<6 && cpu_a==16'h804e-{13'd0,copy_phase})
        copy_phase<=copy_phase+1'b1;
       else copy_phase<=0;
      end
      if(copy_phase==5 && hud_bit(cpu_a)!=0)begin
       if((copy_hud & hud_bit(cpu_a))==0)begin
        copy_hud<=copy_hud | hud_bit(cpu_a);
        copy_hud_count<=copy_hud_count+1'b1;
        if(copy_hud_count==5)copy_phase<=6;
       end else copy_phase<=0;
      end
     end
    end
   end
   // A file validated after the first 29DE window waits for ordinary Reset.
   // Never apply it to live game RAM or overwrite a newer completed score.
   if(!fault)case(state)
    IDLE:;
    GRANT:if(!busak_n && rd_n && wr_n && mreq_n)state<=DRAIN1;
    DRAIN1:if(!busak_n && rd_n && wr_n && mreq_n)state<=DRAIN2;
           else begin fault<=1;state<=IDLE;end
    DRAIN2:if(!busak_n && rd_n && wr_n && mreq_n)state<=BEGIN;
           else begin fault<=1;state<=IDLE;end
    BEGIN:begin if(!restoring)capture_begin<=1;
     else begin significant_seen<=0;hud_blank_mask<=0;end
     state<=restoring ? WRITE1 : READ1;end
    READ1:state<=READ2;
    READ2:state<=READ3;
    READ3:begin capture_write<=1;capture_address<=pos[1:0];
     capture_data<=cpu_di;state<=READ4;end
    READ4:if(pos==2)begin pos<=0;state<=END1;end
          else begin pos<=pos+1'b1;state<=READ1;end
    WRITE1:begin
     if(pos>=3)begin
      hud_blank_mask[hud_index(pos)]<=hud_write_blank;
      if(hud_digit!=0)significant_seen<=1;
     end
     state<=WRITE2;
    end
    WRITE2:state<=WRITE3;
    WRITE3:if(pos==8)begin pos<=0;state<=CHECK1;end
           else begin pos<=pos+1'b1;state<=WRITE1;end
    CHECK1:state<=CHECK2;
    CHECK2:state<=CHECK3;
    CHECK3:begin
     if(cpu_di!=manager_do)begin fault<=1;state<=IDLE;end
     else state<=CHECK4;
    end
    CHECK4:if(pos==8)state<=END1;
           else begin pos<=pos+1'b1;state<=CHECK1;end
    END1:begin if(restoring)begin restore_done<=1;end
     else capture_end<=1;
     state<=END2;end
    END2:state<=END3;
    END3:state<=IDLE;
    default:begin fault<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
