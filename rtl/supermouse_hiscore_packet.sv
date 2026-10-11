// SPDX-License-Identifier: GPL-3.0-or-later
// Super Mouse-only SMHS v1 packet. No The Pit payload or score addresses.
module supermouse_hiscore_packet(
 input wire clk,cold_reset,download,upload,wr,rd,
 input wire [15:0] index,input wire [26:0] address,input wire [7:0] data,
 input wire save_action,restore_lock,restore_done,cancel_capture,
 input wire capture_begin,capture_write,capture_end,
 input wire [1:0] capture_address,input wire [7:0] capture_data,
 output wire [7:0] upload_data,
 output wire [7:0] restore_data,
 input wire [1:0] restore_address,
 output wire pending_load,staging_busy,
 output reg valid=0,local_changed=0,upload_request=0,
 output reg [31:0] generation=0
);
 reg [7:0] staging[0:31],published[0:31],upload_bank[0:31];
 reg [7:0] captured[0:2],completed[0:2];
 reg prev_download=0,prev_upload=0,prev_save=0;
 reg receiving=0,receive_bad=0,checking=0,waiting=0,from_host=0;
 reg [5:0] receive_count=0,check_pos=0;
 reg [31:0] crc=32'hffffffff;
 reg check_ok=0;
 reg capture_active=0,capture_bad=0,capture_pending=0;
 reg [2:0] capture_count=0;
 reg pending=0,dirty=0,request_sent=0,manual_pending=0;
 reg [31:0] uploaded_generation=0;
 reg upload_valid=0,upload_bad=0;
 reg [5:0] delivered=0;
 integer k;
 assign pending_load=pending;
 assign staging_busy=receiving || checking || waiting || capture_active || capture_pending;
 assign restore_data=valid && restore_address<3 ? published[5'd8+{3'd0,restore_address}] : 8'd0;
 // hps_io prefetches address zero before upload becomes visible to this clock;
 // subsequent bytes come from the snapshot taken at the upload rising edge.
 assign upload_data=index==4 && address<32 ?
  ((upload && prev_upload) ? (upload_valid ? upload_bank[address[4:0]] : 8'd0) :
   (valid ? published[address[4:0]] : 8'd0)) : 8'd0;
 function [31:0] crc_byte(input [31:0] c,input [7:0] b);
  integer j;reg [31:0] v;
  begin v=c^{24'd0,b};for(j=0;j<8;j=j+1)
   v=v[0] ? (v>>1)^32'hedb88320 : v>>1;
   crc_byte=v;
  end
 endfunction
 function [7:0] fixed_byte(input [5:0] n);
  begin case(n)
   0:fixed_byte="S";1:fixed_byte="M";2:fixed_byte="H";3:fixed_byte="S";
   4:fixed_byte=1;5:fixed_byte=3;
   28:fixed_byte="D";29:fixed_byte="O";30:fixed_byte="N";31:fixed_byte="E";
   default:fixed_byte=0;
  endcase end
 endfunction
 function bcd(input [7:0] v);
  begin bcd=v[7:4]<=9 && v[3:0]<=9;end
 endfunction
 wire [23:0] candidate={staging[10],staging[9],staging[8]};
 wire [23:0] prior={published[10],published[9],published[8]};
 always @(posedge clk) begin
  prev_download<=download;prev_upload<=upload;prev_save<=save_action;
  upload_request<=0;
  if(cold_reset)begin
   valid<=0;local_changed<=0;generation<=0;pending<=0;dirty<=0;
   receiving<=0;receive_bad<=1;receive_count<=0;checking<=0;waiting<=0;
   capture_active<=0;capture_bad<=0;capture_pending<=0;capture_count<=0;
   request_sent<=0;manual_pending<=0;upload_valid<=0;upload_bad<=1;delivered<=0;
   prev_download<=download;prev_upload<=upload;prev_save<=save_action;
  end else begin
   if(restore_done)pending<=0;
   if(save_action && !prev_save && valid && prior!=0)begin manual_pending<=1;request_sent<=0;end
   if(valid && (dirty || manual_pending) && !request_sent && !upload)begin
    upload_request<=1;request_sent<=1;manual_pending<=0;
   end
   if(upload && !prev_upload)begin
    uploaded_generation<=generation;upload_valid<=valid;
    for(k=0;k<32;k=k+1)upload_bank[k]<=published[k];
    delivered<=0;upload_bad<=index!=4;
   end
   if(upload && index!=4)upload_bad<=1;
   if(upload && rd && address!=0)begin
    if(index==4 && address=={21'd0,delivered}+1 && delivered<32)
     delivered<=delivered+1'b1;
    else upload_bad<=1;
   end
   if(!upload && prev_upload)begin
    request_sent<=0;
    if(upload_valid && !upload_bad && delivered==32 && uploaded_generation==generation)
     dirty<=0;
   end
   if(download && !prev_download)begin
    receiving<=index==4 && !staging_busy && !local_changed;
    receive_bad<=index!=4 || staging_busy || local_changed;
    receive_count<=0;
   end
   if(receiving && download && index!=4)receive_bad<=1;
   if(download && wr && (receiving || (!prev_download && index==4 && !staging_busy && !local_changed)))begin
    if(index!=4 || address!={21'd0,(prev_download ? receive_count : 6'd0)} || address>=32)
     receive_bad<=1;
    else begin staging[address[4:0]]<=data;
     receive_count<=(prev_download ? receive_count : 6'd0)+1'b1;end
   end
   if(!download && prev_download && receiving)begin
    receiving<=0;
    if(!receive_bad && receive_count==32)begin
     checking<=1;check_pos<=0;crc<=32'hffffffff;check_ok<=1;from_host<=1;
    end
   end
   if(capture_begin)begin capture_active<=1;capture_count<=0;capture_bad<=0;end
   if(capture_active && capture_write)begin
    if(capture_address==capture_count[1:0] && capture_count<3)begin
     captured[capture_address]<=capture_data;capture_count<=capture_count+1'b1;
    end else capture_bad<=1;
   end
   if(capture_active && capture_end)begin
    capture_active<=0;
    if(!capture_bad && capture_count==3)begin
     for(k=0;k<3;k=k+1)completed[k]<=captured[k];
     capture_pending<=1;
     // A completed local score supersedes a late host transfer.
     receiving<=0;receive_bad<=1;
     if(from_host)begin checking<=0;waiting<=0;end
    end
   end
   if(capture_pending && !capture_active && !capture_begin && !capture_end &&
      !receiving && !checking && !waiting)begin
    for(k=0;k<32;k=k+1)
     staging[k]<=k>=8 && k<=10 ? completed[k-8] : fixed_byte(k[5:0]);
    capture_pending<=0;checking<=1;check_pos<=0;crc<=32'hffffffff;
    check_ok<=1;from_host<=0;
   end
   if(checking && !(capture_active && capture_end))begin
    if(check_pos<24)crc<=crc_byte(crc,staging[check_pos[4:0]]);
    if((check_pos<8 || (check_pos>=11 && check_pos<=23) || check_pos>=28) &&
       staging[check_pos[4:0]]!=fixed_byte(check_pos))check_ok<=0;
    if(check_pos>=8 && check_pos<=10 && !bcd(staging[check_pos[4:0]]))check_ok<=0;
    if(check_pos==24)begin
     if(from_host)begin
      if({staging[27],staging[26],staging[25],staging[24]}!=~crc)check_ok<=0;
     end else begin
      staging[24]<=~crc[7:0];staging[25]<=~crc[15:8];
      staging[26]<=~crc[23:16];staging[27]<=~crc[31:24];
     end
    end
    if(check_pos==31)begin checking<=0;waiting<=check_ok && staging[31]=="E";
    end else check_pos<=check_pos+1'b1;
   end
   if(waiting && !restore_lock && !(capture_active && capture_end))begin
    waiting<=0;
    if(from_host)begin
     if(!local_changed && (!valid || candidate>prior))begin
      for(k=0;k<32;k=k+1)published[k]<=staging[k];
      valid<=1;pending<=1;generation<=generation+1'b1;
     end
    end else if(candidate!=0 && (!valid || candidate>prior))begin
     for(k=0;k<32;k=k+1)published[k]<=staging[k];
     valid<=1;generation<=generation+1'b1;dirty<=1;
     request_sent<=0;local_changed<=1;
    end
   end
   if(cancel_capture)begin
    capture_active<=0;capture_bad<=1;capture_pending<=0;
    // A launch-time host download may end while the game CPU is still in
    // reset.  Do not let that reset cancel validation started on this edge.
    if(!from_host && !(receiving && !download && prev_download))begin
     checking<=0;waiting<=0;
    end
   end
  end
 end
endmodule
