
module apb_slave (
    input logic PCLK,
    input logic PRESETn,

    input logic [31:0] PADDR,
    input logic PSEL,
    input logic PENABLE,
    input logic PWRITE,
    input logic [31:0] PWDATA,
    input logic [3:0] PSTRB,
    input logic [2:0] PPROT,

    output logic [31:0] PRDATA,
    output logic PREADY,
    output logic PSLVERR
);

    // Register map
    localparam logic [7:0] ADDR_CTRL = 8'h00;
    localparam logic [7:0] ADDR_STATUS = 8'h04;
    localparam logic [7:0] ADDR_SCRATCH = 8'h08;
    localparam logic [7:0] ADDR_ID = 8'h0C;
    localparam logic [7:0] ADDR_CMD = 8'h10;
    localparam logic [7:0] ADDR_RESULT = 8'h14;
    localparam logic [7:0] ADDR_DELAY = 8'h18;

    localparam logic [31:0] ID_VALUE = 32'h4150_4234;

    // Register storage
    logic [31:0] ctrl_reg;
    logic [31:0] scratch_reg;
    logic [31:0] delay_reg;
    logic [31:0] result_reg;

    // Internal operation state
    logic busy;
    logic [31:0] work_count;

    // Address and transaction checks
    logic access_phase;
    logic addr_aligned;
    logic addr_in_range;
    logic addr_valid;
    logic read_only_addr;
    logic result_read;
    logic cmd_start;
    logic cmd_busy_error;

    // APB phase and address decoding
    assign access_phase = PSEL && PENABLE;

    assign addr_aligned = (PADDR[1:0] == 2'b00);

    assign addr_in_range = (PADDR[31:8] == 24'h0) && (PADDR[7:0] <= ADDR_DELAY);

    assign addr_valid = addr_aligned && addr_in_range;

    assign read_only_addr =
        (PADDR[7:0] == ADDR_STATUS) ||
        (PADDR[7:0] == ADDR_ID)     ||
        (PADDR[7:0] == ADDR_RESULT);

    assign result_read = (PADDR[7:0] == ADDR_RESULT) && !PWRITE;

    // CMD bit 0 starts an operation when byte lane 0
    // is enabled. Starting while busy is an error.
    assign cmd_start =
        (PADDR[7:0] == ADDR_CMD) &&
        PWRITE &&
        PSTRB[0] &&
        PWDATA[0];

    assign cmd_busy_error = cmd_start && busy;

    // APB handshake and error response
    // Only RESULT reads wait for the internal operation.
    // All other valid accesses complete immediately.
    always_comb begin
        PREADY = 1'b0;

        if (access_phase) begin
            if (result_read && busy)
                PREADY = 1'b0;
            else
                PREADY = 1'b1;
        end
    end

    // Errors are meaningful during the access phase.
    always_comb begin
        PSLVERR = 1'b0;

        if (access_phase) begin
            if (!addr_valid)
                PSLVERR = 1'b1;
            else if (PWRITE && read_only_addr)
                PSLVERR = 1'b1;
            else if (cmd_busy_error)
                PSLVERR = 1'b1;
        end
    end

    // Read data mux
    always_comb begin
        PRDATA = 32'h0000_0000;

        if (addr_valid) begin
            case (PADDR[7:0])
                ADDR_CTRL:
                    PRDATA = ctrl_reg;

                ADDR_STATUS:
                    PRDATA = 32'h0000_0000;

                ADDR_SCRATCH:
                    PRDATA = scratch_reg;

                ADDR_ID:
                    PRDATA = ID_VALUE;

                ADDR_CMD:
                    PRDATA = 32'h0000_0000;

                ADDR_RESULT:
                    PRDATA = result_reg;

                ADDR_DELAY:
                    PRDATA = delay_reg;

                default:
                    PRDATA = 32'h0000_0000;
            endcase
        end
    end

    // Sequential logic: registers and internal engine
    // Synchronous active-low reset.
    always_ff @(posedge PCLK) begin
        if (!PRESETn) begin
            ctrl_reg <= 32'h0000_0000;
            scratch_reg <= 32'h0000_0000;
            delay_reg <= 32'd5;
            result_reg <= 32'h0000_0000;

            busy <= 1'b0;
            work_count <= 32'd0;
        end
        else begin

            // Internal operation progresses every clock
            // independently of APB bus activity
            if (busy) begin
                if (work_count <= 32'd1) begin
                    work_count <= 32'd0;
                    result_reg <= 32'h1234_5678;
                    busy <= 1'b0;
                end
                else begin
                    work_count <= work_count - 1'b1;
                end
            end

            // Register writes occur only on a completed
            // successful APB access.
            if (access_phase && PREADY &&
                !PSLVERR && PWRITE) begin

                case (PADDR[7:0])

                    ADDR_CTRL: begin
                        for (int i = 0; i < 4; i++) begin
                            if (PSTRB[i])
                                ctrl_reg[i*8 +: 8] <= PWDATA[i*8 +: 8];
                        end
                    end

                    ADDR_SCRATCH: begin
                        for (int i = 0; i < 4; i++) begin
                            if (PSTRB[i])
                                scratch_reg[i*8 +: 8] <= PWDATA[i*8 +: 8];
                        end
                    end

                    ADDR_DELAY: begin
                        for (int i = 0; i < 4; i++) begin
                            if (PSTRB[i])
                                delay_reg[i*8 +: 8] <= PWDATA[i*8 +: 8];
                        end
                    end

                    ADDR_CMD: begin
                        // Start the internal operation.
                        // CMD bit 0 must be written as 1.
                        if (PSTRB[0] && PWDATA[0] && !busy) begin
                            busy <= 1'b1;

                            // A zero delay still takes one
                            // internal processing cycle.
                            if (delay_reg == 32'd0)
                                work_count <= 32'd1;
                            else
                                work_count <= delay_reg;
                        end
                    end

                    default: begin
                        // No writable register selected.
                    end

                endcase
            end
        end
    end

    // PPROT is reserved for future protection checks.

endmodule
