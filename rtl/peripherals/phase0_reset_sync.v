`timescale 1ns / 1ps

module phase0_reset_sync (
    input  wire clk,
    input  wire arst_n,
    output wire srst_n
);

reg [1:0] reset_pipe;

always @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
        reset_pipe <= 2'b00;
    end else begin
        reset_pipe <= {reset_pipe[0], 1'b1};
    end
end

assign srst_n = reset_pipe[1];

endmodule
