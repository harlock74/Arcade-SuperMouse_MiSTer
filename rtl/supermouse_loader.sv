// Super Mouse selected-set 0x9040 packed stream, isolated from accepted cores.
// SPDX-License-Identifier: GPL-3.0-or-later
// Main five, sound one, graphics planes three, palette PROMs two.
module supermouse_loader(
    input wire clk, reset,
    input wire download, wr,
    input wire [15:0] index,
    input wire [26:0] address,
    input wire [7:0] data,
    output reg ready = 0, error = 0,
    output wire [6:0] bank_we,
    output wire [14:0] bank_address,
    output wire [7:0] bank_data,
    output reg [26:0] next_address = 0
);
    reg selected_previous = 0;
    wire selected = download && (index == 16'd0);
    wire starting = selected && !selected_previous;
    wire [26:0] expected_address = starting ? 27'd0 : next_address;
    wire accepting = !reset && selected && wr && (!error || starting)
                     && address == expected_address && address < 27'h09040;
    assign bank_we[0] = accepting && address < 27'h05000;
    assign bank_we[1] = accepting && address >= 27'h05000 && address < 27'h06000;
    assign bank_we[2] = accepting && address >= 27'h06000 && address < 27'h07000;
    assign bank_we[3] = accepting && address >= 27'h07000 && address < 27'h08000;
    assign bank_we[4] = accepting && address >= 27'h08000 && address < 27'h09000;
    assign bank_we[5] = accepting && address >= 27'h09000 && address < 27'h09020;
    assign bank_we[6] = accepting && address >= 27'h09020;
    wire [26:0] local_address = address < 27'h05000 ? address :
                        address < 27'h06000 ? address - 27'h05000 :
                        address < 27'h07000 ? address - 27'h06000 :
                        address < 27'h08000 ? address - 27'h07000 :
                        address < 27'h09000 ? address - 27'h08000 :
                        address < 27'h09020 ? address - 27'h09000 : address - 27'h09020;
    // Narrow only after the full-width range predicate enables a destination.
    assign bank_address = accepting ? local_address[14:0] : 15'd0;
    assign bank_data = data;
    always @(posedge clk) begin
        if (reset) begin
            ready <= 0; error <= 0; next_address <= 0; selected_previous <= 0;
        end else begin
            selected_previous <= selected;
            if (starting) begin ready <= 0; error <= 0; next_address <= 0; end
            if (selected && wr) begin
                if (accepting) next_address <= expected_address + 27'd1;
                else begin ready <= 0; error <= 1; end
            end
            // Complete only on real download end. Index switching cannot complete a session.
            if (selected_previous && !selected) begin
                if (!download && !error && next_address == 27'h09040) ready <= 1;
                else begin ready <= 0; error <= 1; end
            end
        end
    end
endmodule
