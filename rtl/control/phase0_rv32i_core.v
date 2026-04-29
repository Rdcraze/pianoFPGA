`timescale 1ns / 1ps

module phase0_rv32i_core (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    output wire [31:0] instr_addr,
    input  wire [31:0] instr_rdata,
    output reg         data_req,
    output reg         data_we,
    output reg  [3:0]  data_wstrb,
    output reg  [31:0] data_addr,
    output reg  [31:0] data_wdata,
    input  wire [31:0] data_rdata,
    output reg  [31:0] pc,
    output reg         firmware_started,
    output reg         illegal_insn_seen,
    output reg         load_seen,
    output reg         store_seen,
    output reg         branch_taken_seen
);

localparam [6:0] OPCODE_LUI     = 7'b0110111;
localparam [6:0] OPCODE_AUIPC   = 7'b0010111;
localparam [6:0] OPCODE_JAL     = 7'b1101111;
localparam [6:0] OPCODE_JALR    = 7'b1100111;
localparam [6:0] OPCODE_BRANCH  = 7'b1100011;
localparam [6:0] OPCODE_LOAD    = 7'b0000011;
localparam [6:0] OPCODE_STORE   = 7'b0100011;
localparam [6:0] OPCODE_OP_IMM  = 7'b0010011;
localparam [6:0] OPCODE_OP      = 7'b0110011;
localparam [6:0] OPCODE_MISCMEM = 7'b0001111;

localparam [2:0] STATE_FETCH_REQ     = 3'd0;
localparam [2:0] STATE_FETCH_CAPTURE = 3'd1;
localparam [2:0] STATE_DECODE        = 3'd2;
localparam [2:0] STATE_EXEC          = 3'd3;
localparam [2:0] STATE_LOAD          = 3'd4;
localparam [2:0] STATE_WRITEBACK     = 3'd5;

reg [2:0]  state;
reg [31:0] instr_reg;
reg [31:0] regs [0:31];
reg [31:0] rs1_value_q;
reg [31:0] rs2_value_q;
reg [4:0]  load_rd_q;
reg [2:0]  load_funct3_q;
reg [31:0] load_addr_q;
reg [31:0] wb_next_pc_q;
reg [4:0]  wb_rd_q;
reg        wb_writeback_en_q;
reg [31:0] wb_writeback_data_q;
reg        wb_branch_taken_q;
reg        wb_store_q;

wire [31:0] instr = instr_reg;
wire [6:0]  opcode = instr[6:0];
wire [2:0]  funct3 = instr[14:12];
wire [6:0]  funct7 = instr[31:25];
wire [4:0]  rd     = instr[11:7];
wire [4:0]  rs1    = instr[19:15];
wire [4:0]  rs2    = instr[24:20];

wire [31:0] rs1_value = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
wire [31:0] rs2_value = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25],
                     instr[11:8], 1'b0};
wire [31:0] imm_u = {instr[31:12], 12'd0};
wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20],
                     instr[30:21], 1'b0};

wire [7:0] load_byte_value =
    (load_addr_q[1:0] == 2'd0) ? data_rdata[7:0] :
    (load_addr_q[1:0] == 2'd1) ? data_rdata[15:8] :
    (load_addr_q[1:0] == 2'd2) ? data_rdata[23:16] :
                                 data_rdata[31:24];
wire [15:0] load_half_value = load_addr_q[1] ? data_rdata[31:16] : data_rdata[15:0];

reg  [31:0] next_pc;
reg         writeback_en;
reg  [31:0] writeback_data;
reg         illegal_insn;
reg         branch_taken;
reg  [31:0] addr_calc;
reg         issue_load;
reg         issue_store;
reg  [31:0] load_writeback_data;

assign instr_addr = pc;

always @(*) begin
    next_pc        = pc + 32'd4;
    writeback_en   = 1'b0;
    writeback_data = 32'd0;
    illegal_insn   = 1'b0;
    branch_taken   = 1'b0;
    addr_calc      = rs1_value_q + imm_i;
    issue_load     = 1'b0;
    issue_store    = 1'b0;

    data_req       = 1'b0;
    data_we        = 1'b0;
    data_wstrb     = 4'b0000;
    data_addr      = 32'd0;
    data_wdata     = 32'd0;

    if (state == STATE_EXEC) begin
        case (opcode)
            OPCODE_LUI: begin
                writeback_en   = 1'b1;
                writeback_data = imm_u;
            end
            OPCODE_AUIPC: begin
                writeback_en   = 1'b1;
                writeback_data = pc + imm_u;
            end
            OPCODE_JAL: begin
                writeback_en   = 1'b1;
                writeback_data = pc + 32'd4;
                next_pc        = pc + imm_j;
            end
            OPCODE_JALR: begin
                writeback_en   = 1'b1;
                writeback_data = pc + 32'd4;
                next_pc        = (rs1_value_q + imm_i) & 32'hffff_fffe;
            end
            OPCODE_BRANCH: begin
                case (funct3)
                    3'b000: branch_taken = (rs1_value_q == rs2_value_q);
                    3'b001: branch_taken = (rs1_value_q != rs2_value_q);
                    3'b100: branch_taken = ($signed(rs1_value_q) < $signed(rs2_value_q));
                    3'b101: branch_taken = ($signed(rs1_value_q) >= $signed(rs2_value_q));
                    3'b110: branch_taken = (rs1_value_q < rs2_value_q);
                    3'b111: branch_taken = (rs1_value_q >= rs2_value_q);
                    default: illegal_insn = 1'b1;
                endcase

                if (!illegal_insn && branch_taken) begin
                    next_pc = pc + imm_b;
                end
            end
            OPCODE_LOAD: begin
                addr_calc  = rs1_value_q + imm_i;
                data_req   = 1'b1;
                data_addr  = rs1_value_q + imm_i;
                issue_load = !illegal_insn;
                case (funct3)
                    3'b000,
                    3'b001,
                    3'b010,
                    3'b100,
                    3'b101: begin
                    end
                    default: begin
                        illegal_insn = 1'b1;
                        data_req     = 1'b0;
                        issue_load   = 1'b0;
                    end
                endcase
            end
            OPCODE_STORE: begin
                addr_calc = rs1_value_q + imm_s;
                data_req  = 1'b1;
                data_we   = 1'b1;
                data_addr = rs1_value_q + imm_s;

                case (funct3)
                    3'b000: begin
                        data_wstrb = 4'b0001 << addr_calc[1:0];
                        data_wdata = rs2_value_q << ({addr_calc[1:0], 3'b000});
                        issue_store = 1'b1;
                    end
                    3'b001: begin
                        data_wstrb = addr_calc[1] ? 4'b1100 : 4'b0011;
                        data_wdata = rs2_value_q << ({addr_calc[1], 4'b0000});
                        issue_store = 1'b1;
                    end
                    3'b010: begin
                        data_wstrb = 4'b1111;
                        data_wdata = rs2_value_q;
                        issue_store = 1'b1;
                    end
                    default: begin
                        illegal_insn = 1'b1;
                        data_req     = 1'b0;
                        data_we      = 1'b0;
                        data_wstrb   = 4'b0000;
                    end
                endcase
            end
            OPCODE_OP_IMM: begin
                case (funct3)
                    3'b000: writeback_data = rs1_value_q + imm_i;
                    3'b010: writeback_data = ($signed(rs1_value_q) < $signed(imm_i)) ? 32'd1 : 32'd0;
                    3'b011: writeback_data = (rs1_value_q < imm_i) ? 32'd1 : 32'd0;
                    3'b100: writeback_data = rs1_value_q ^ imm_i;
                    3'b110: writeback_data = rs1_value_q | imm_i;
                    3'b111: writeback_data = rs1_value_q & imm_i;
                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = rs1_value_q << instr[24:20];
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = rs1_value_q >> instr[24:20];
                        end else if (funct7 == 7'b0100000) begin
                            writeback_data = $signed(rs1_value_q) >>> instr[24:20];
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    default: illegal_insn = 1'b1;
                endcase

                if (!illegal_insn) begin
                    writeback_en = 1'b1;
                end
            end
            OPCODE_OP: begin
                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = rs1_value_q + rs2_value_q;
                        end else if (funct7 == 7'b0100000) begin
                            writeback_data = rs1_value_q - rs2_value_q;
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = rs1_value_q << rs2_value_q[4:0];
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    3'b010: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = ($signed(rs1_value_q) < $signed(rs2_value_q)) ? 32'd1 : 32'd0;
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    3'b011: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = (rs1_value_q < rs2_value_q) ? 32'd1 : 32'd0;
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    3'b100: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = rs1_value_q ^ rs2_value_q;
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = rs1_value_q >> rs2_value_q[4:0];
                        end else if (funct7 == 7'b0100000) begin
                            writeback_data = $signed(rs1_value_q) >>> rs2_value_q[4:0];
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    3'b110: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = rs1_value_q | rs2_value_q;
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    3'b111: begin
                        if (funct7 == 7'b0000000) begin
                            writeback_data = rs1_value_q & rs2_value_q;
                        end else begin
                            illegal_insn = 1'b1;
                        end
                    end
                    default: illegal_insn = 1'b1;
                endcase

                if (!illegal_insn) begin
                    writeback_en = 1'b1;
                end
            end
            OPCODE_MISCMEM: begin
                // FENCE/FENCE.I are treated as no-ops in this tiny in-order core.
            end
            default: begin
                illegal_insn = 1'b1;
            end
        endcase
    end else if (state == STATE_LOAD) begin
        data_req  = 1'b1;
        data_addr = load_addr_q;
    end
end

always @(*) begin
    case (load_funct3_q)
        3'b000: load_writeback_data = {{24{load_byte_value[7]}}, load_byte_value};
        3'b001: load_writeback_data = {{16{load_half_value[15]}}, load_half_value};
        3'b010: load_writeback_data = data_rdata;
        3'b100: load_writeback_data = {24'd0, load_byte_value};
        default: load_writeback_data = {16'd0, load_half_value};
    endcase
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        state             <= STATE_FETCH_REQ;
        pc                <= 32'd0;
        instr_reg         <= 32'd0;
        rs1_value_q       <= 32'd0;
        rs2_value_q       <= 32'd0;
        load_rd_q         <= 5'd0;
        load_funct3_q     <= 3'd0;
        load_addr_q       <= 32'd0;
        wb_next_pc_q      <= 32'd0;
        wb_rd_q           <= 5'd0;
        wb_writeback_en_q <= 1'b0;
        wb_writeback_data_q <= 32'd0;
        wb_branch_taken_q <= 1'b0;
        wb_store_q        <= 1'b0;
        firmware_started  <= 1'b0;
        illegal_insn_seen <= 1'b0;
        load_seen         <= 1'b0;
        store_seen        <= 1'b0;
        branch_taken_seen <= 1'b0;

        regs[0]  <= 32'd0;
        regs[1]  <= 32'd0;
        regs[2]  <= 32'd0;
        regs[3]  <= 32'd0;
        regs[4]  <= 32'd0;
        regs[5]  <= 32'd0;
        regs[6]  <= 32'd0;
        regs[7]  <= 32'd0;
        regs[8]  <= 32'd0;
        regs[9]  <= 32'd0;
        regs[10] <= 32'd0;
        regs[11] <= 32'd0;
        regs[12] <= 32'd0;
        regs[13] <= 32'd0;
        regs[14] <= 32'd0;
        regs[15] <= 32'd0;
        regs[16] <= 32'd0;
        regs[17] <= 32'd0;
        regs[18] <= 32'd0;
        regs[19] <= 32'd0;
        regs[20] <= 32'd0;
        regs[21] <= 32'd0;
        regs[22] <= 32'd0;
        regs[23] <= 32'd0;
        regs[24] <= 32'd0;
        regs[25] <= 32'd0;
        regs[26] <= 32'd0;
        regs[27] <= 32'd0;
        regs[28] <= 32'd0;
        regs[29] <= 32'd0;
        regs[30] <= 32'd0;
        regs[31] <= 32'd0;
    end else begin
        case (state)
            STATE_FETCH_REQ: begin
                state <= STATE_FETCH_CAPTURE;
            end
            STATE_FETCH_CAPTURE: begin
                instr_reg        <= instr_rdata;
                firmware_started <= firmware_started | (instr_rdata != 32'd0);
                state            <= STATE_DECODE;
            end
            STATE_DECODE: begin
                rs1_value_q      <= rs1_value;
                rs2_value_q      <= rs2_value;
                state            <= STATE_EXEC;
            end
            STATE_EXEC: begin
                if (illegal_insn) begin
                    illegal_insn_seen <= 1'b1;
                    state             <= STATE_FETCH_REQ;
                end else if (issue_load) begin
                    load_seen         <= 1'b1;
                    load_rd_q         <= rd;
                    load_funct3_q     <= funct3;
                    load_addr_q       <= addr_calc;
                    wb_next_pc_q      <= next_pc;
                    wb_branch_taken_q <= 1'b0;
                    wb_store_q        <= 1'b0;
                    state             <= STATE_LOAD;
                end else begin
                    wb_next_pc_q        <= next_pc;
                    wb_rd_q             <= rd;
                    wb_writeback_en_q   <= writeback_en;
                    wb_writeback_data_q <= writeback_data;
                    wb_branch_taken_q   <= branch_taken;
                    wb_store_q          <= issue_store;
                    state               <= STATE_WRITEBACK;
                end
            end
            STATE_LOAD: begin
                wb_rd_q             <= load_rd_q;
                wb_writeback_en_q   <= (load_rd_q != 5'd0);
                wb_writeback_data_q <= load_writeback_data;
                state               <= STATE_WRITEBACK;
            end
            STATE_WRITEBACK: begin
                pc                <= wb_next_pc_q;
                store_seen        <= store_seen | wb_store_q;
                branch_taken_seen <= branch_taken_seen | wb_branch_taken_q;
                state             <= STATE_FETCH_REQ;
                if (wb_writeback_en_q && (wb_rd_q != 5'd0)) begin
                    regs[wb_rd_q] <= wb_writeback_data_q;
                end
            end
            default: begin
                state <= STATE_FETCH_REQ;
            end
        endcase
    end
end

endmodule
