// SPDX-License-Identifier: GPL-3.0-or-later
// Super Mouse input byte and all eight MAME-functional DIP bits.
module supermouse_controls(
 input wire [31:0] joystick_0, joystick_1,
 input wire [7:0] options,
 input wire coin_unlocked,
 output wire [7:0] player0, player1, inputs1, dips
);
 wire [7:0] cabinet_inputs;
 thepit_controls common_controls(
  .joystick_0(joystick_0),.joystick_1(joystick_1),.dip_options(8'd0),
  .player0(player0),.player1(player1),.inputs1(cabinet_inputs),.dips());
 // MAME Q2 callback sends !Q2 to coin_lockout_w: Q2=0 locks coin 1.
 // Start2 moves from Round-Up A800[1] to Super Mouse A800[3].
 // Coin/start OR across controllers is a MiSTer cabinet convenience.
 assign inputs1={4'b0000,cabinet_inputs[1],cabinet_inputs[2],1'b0,
                 cabinet_inputs[0] && coin_unlocked};
 // Fresh MiSTer status is zero. Translate menu ordinal values into the
 // selected set's DSW byte; all-zero options must read 0x01 at B000.
 wire [2:0] coin=options[2:0]==3'd0 ? 3'd1 :
                 options[2:0]==3'd1 ? 3'd0 : options[2:0];
 assign dips={options[7:5],options[4:3],coin};
endmodule
