
`timescale 1ns/1ps

module tb_apb_slave;

    logic        PCLK;
    logic        PRESETn;
    logic [31:0] PADDR;
    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PWDATA;
    logic [3:0]  PSTRB;
    logic [2:0]  PPROT;

    logic [31:0] PRDATA;
    logic        PREADY;
    logic        PSLVERR;

    integer wait_cycles;

    // -----------------------------------------------
    // DUT
    // -----------------------------------------------
    apb_slave dut (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PADDR   (PADDR),
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PWDATA  (PWDATA),
        .PSTRB   (PSTRB),
        .PPROT   (PPROT),
        .PRDATA  (PRDATA),
        .PREADY  (PREADY),
        .PSLVERR (PSLVERR)
    );

    // 100 MHz clock: period = 10 ns
    initial PCLK = 1'b0;
    always #5 PCLK = ~PCLK;

    // -----------------------------------------------
    // APB WRITE TASK
    // -----------------------------------------------
    task automatic apb_write(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [3:0]  strb,
        input logic        expect_error
    );
        begin
            // Setup phase
            @(negedge PCLK);
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b1;
            PADDR   = addr;
            PWDATA  = data;
            PSTRB   = strb;

            // Access phase
            @(negedge PCLK);
            PENABLE = 1'b1;

            wait_cycles = 0;
            #1;

            // Wait dynamically until slave is ready.
            while (PREADY !== 1'b1) begin
                wait_cycles = wait_cycles + 1;
                @(negedge PCLK);
                #1;
            end

            if (PSLVERR !== expect_error)
                $fatal(1,
                    "WRITE ERROR mismatch: addr=%h err=%b expected=%b",
                    addr, PSLVERR, expect_error);

            // Transfer completes at this rising edge.
            @(posedge PCLK);
            @(negedge PCLK);

            // Return bus to idle.
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PSTRB   = 4'b0000;

            $display(
                "[WRITE] addr=%h data=%h strb=%b err=%b waits=%0d",
                addr, data, strb, expect_error, wait_cycles
            );
        end
    endtask

    // -----------------------------------------------
    // APB READ TASK
    // -----------------------------------------------
    task automatic apb_read(
        input logic [31:0] addr,
        input logic [31:0] expected_data,
        input logic        expect_error
    );
        begin
            // Setup phase
            @(negedge PCLK);
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PADDR   = addr;
            PWDATA  = 32'h0000_0000;
            PSTRB   = 4'b0000;

            // Access phase
            @(negedge PCLK);
            PENABLE = 1'b1;

            wait_cycles = 0;
            #1;

            // Remain in access until PREADY is asserted.
            while (PREADY !== 1'b1) begin
                wait_cycles = wait_cycles + 1;
                @(negedge PCLK);
                #1;
            end

            if (PSLVERR !== expect_error)
                $fatal(1,
                    "READ ERROR mismatch: addr=%h err=%b expected=%b",
                    addr, PSLVERR, expect_error);

            if (PRDATA !== expected_data)
                $fatal(1,
                    "READ DATA mismatch: addr=%h got=%h expected=%h",
                    addr, PRDATA, expected_data);

            // Complete the transfer.
            @(posedge PCLK);
            @(negedge PCLK);

            // Return bus to idle.
            PSEL    = 1'b0;
            PENABLE = 1'b0;

            $display(
                "[READ ] addr=%h data=%h err=%b waits=%0d",
                addr, PRDATA, expect_error, wait_cycles
            );
        end
    endtask

    // -----------------------------------------------
    // TEST SEQUENCE
    // -----------------------------------------------
    initial begin
        PRESETn = 1'b0;
        PADDR   = 32'h0;
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PWDATA  = 32'h0;
        PSTRB   = 4'h0;
        PPROT   = 3'b000;

        $display("----------------------------------");
        $display(" APB4 REGISTER SLAVE TEST START");
        $display("----------------------------------");

        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_apb_slave);

        // Synchronous reset
        repeat (3) @(posedge PCLK);
        @(negedge PCLK);
        PRESETn = 1'b1;

        // -------------------------------------------
        // Test 1: CTRL full-word write/read
        // -------------------------------------------
        apb_write(32'h00, 32'h1234_5678, 4'hF, 1'b0);
        apb_read (32'h00, 32'h1234_5678, 1'b0);

        // -------------------------------------------
        // Test 2: Partial byte write
        // 0x12345678 -> 0x1234AA78
        // -------------------------------------------
        apb_write(32'h00, 32'h0000_AA00, 4'b0010, 1'b0);
        apb_read (32'h00, 32'h1234_AA78, 1'b0);

        // -------------------------------------------
        // Test 3: Scratch register
        // -------------------------------------------
        apb_write(32'h08, 32'hDEAD_BEEF, 4'hF, 1'b0);
        apb_read (32'h08, 32'hDEAD_BEEF, 1'b0);

        // -------------------------------------------
        // Test 4: Read-only ID register
        // -------------------------------------------
        apb_read (32'h0C, 32'h4150_4234, 1'b0);
        apb_write(32'h0C, 32'h0000_0000, 4'hF, 1'b1);
        apb_read (32'h0C, 32'h4150_4234, 1'b0);

        // -------------------------------------------
        // Test 5: Read-only STATUS register
        // -------------------------------------------
        apb_write(32'h04, 32'hFFFF_FFFF, 4'hF, 1'b1);
        apb_read (32'h04, 32'h0000_0000, 1'b0);

        // -------------------------------------------
        // Test 6: Invalid and unaligned addresses
        // -------------------------------------------
        apb_read (32'h10_0000, 32'h0000_0000, 1'b1);
        apb_write(32'h02, 32'hFFFF_FFFF, 4'hF, 1'b1);

        // -------------------------------------------
        // Test 7: Dynamic wait states
        // -------------------------------------------
        // Program operation duration = 3 cycles.
        apb_write(32'h18, 32'd3, 4'hF, 1'b0);

        // Start the operation.
        apb_write(32'h10, 32'h0000_0001, 4'b0001, 1'b0);

        // RESULT must wait until the operation finishes.
        apb_read(32'h14, 32'h1234_5678, 1'b0);

        if (wait_cycles < 1)
            $fatal(1,
                "Expected RESULT read to have wait cycles");

        $display(
            "PASS: RESULT read waited %0d cycles",
            wait_cycles
        );

        // -------------------------------------------
        // Test 8: Different operation duration
        // -------------------------------------------
        // Program a longer operation.
        apb_write(32'h18, 32'd8, 4'hF, 1'b0);
        apb_write(32'h10, 32'h0000_0001, 4'b0001, 1'b0);

        apb_read(32'h14, 32'h1234_5678, 1'b0);

        if (wait_cycles < 5)
            $fatal(1,
                "Long operation did not produce enough wait cycles");

        $display(
            "PASS: Longer operation waited %0d cycles",
            wait_cycles
        );

        $display("----------------------------------");
        $display(" ALL APB4 TESTS PASSED");
        $display("----------------------------------");

        $finish;
    end

    // Global timeout to catch a stuck transaction.
    initial begin
        #10000;
        $fatal(1, "TIMEOUT: APB transaction did not complete");
    end

endmodule
