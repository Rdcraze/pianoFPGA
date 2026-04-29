`timescale 1ns / 1ps

module phase0_sample_gen (
    input  wire               sys_clk,
    input  wire               sys_rst_n,
    input  wire               sample_tick,
    input  wire               enable,
    input  wire               tone_enable,
    input  wire               trigger_strobe,
    input  wire [1:0]         wave_sel,
    input  wire [23:0]        phase_step,
    input  wire [15:0]        gain,
    input  wire [15:0]        decay_step,
    output reg  signed [15:0] sample_data,
    output reg                sample_valid,
    output reg                active
);

reg [23:0] phase_accum;
reg [15:0] env_level;

wire signed [15:0] env_signed;
wire signed [15:0] saw_signed;
wire signed [31:0] saw_scaled;

assign env_signed = {1'b0, env_level[14:0]};
assign saw_signed = {phase_accum[23], phase_accum[22:8]};
assign saw_scaled = $signed(saw_signed) * $signed(env_signed);

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        phase_accum  <= 24'd0;
        env_level    <= 16'd0;
        sample_data  <= 16'sd0;
        sample_valid <= 1'b0;
        active       <= 1'b0;
    end else begin
        sample_valid <= 1'b0;

        if (sample_tick) begin
            sample_valid <= 1'b1;

            if (enable && tone_enable) begin
                if (trigger_strobe || !active) begin
                    active     <= 1'b1;
                    env_level  <= gain;
                    phase_accum <= 24'd0;
                end else begin
                    phase_accum <= phase_accum + phase_step;
                    if (decay_step != 16'd0) begin
                        if (env_level > decay_step) begin
                            env_level <= env_level - decay_step;
                        end else begin
                            env_level <= 16'd0;
                            active    <= 1'b0;
                        end
                    end else begin
                        env_level <= gain;
                    end
                end

                case (wave_sel)
                    2'b00: begin
                        sample_data <= phase_accum[23] ? env_signed : -env_signed;
                    end
                    2'b01: begin
                        sample_data <= saw_scaled[30:15];
                    end
                    2'b10: begin
                        sample_data <= env_signed;
                    end
                    default: begin
                        sample_data <= 16'sd0;
                    end
                endcase
            end else begin
                active      <= 1'b0;
                env_level   <= 16'd0;
                sample_data <= 16'sd0;
            end
        end
    end
end

endmodule
