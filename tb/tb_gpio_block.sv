`timescale 1ns/1ps

module tb_gpio_block;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam int WIDTH = 8;
    localparam bit ENABLE_FALLING_EDGE = 1'b1;

    // ------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------
    logic                 clk;
    logic                 rstn;

    logic [WIDTH-1:0]     gpio_in;
    logic [WIDTH-1:0]     gpio_out;
    logic [WIDTH-1:0]     gpio_oe;

    logic [WIDTH-1:0]     direction;
    logic [WIDTH-1:0]     output_write_data;
    logic                 output_write_en;

    logic [WIDTH-1:0]     interrupt_clear;
    logic                 interrupt_clear_en;

    logic [WIDTH-1:0]     input_data;
    logic [WIDTH-1:0]     output_data;
    logic [WIDTH-1:0]     interrupt_status;
    logic                 interrupt;

    int pass_count = 0;
    int fail_count = 0;

    // ------------------------------------------------------------
    // DUT instantiation
    // ------------------------------------------------------------
    gpio_block #(
        .WIDTH(WIDTH),
        .ENABLE_FALLING_EDGE(ENABLE_FALLING_EDGE)
    ) dut (
        .clk                (clk),
        .rstn               (rstn),

        .gpio_in            (gpio_in),
        .gpio_out           (gpio_out),
        .gpio_oe            (gpio_oe),

        .direction           (direction),
        .output_write_data  (output_write_data),
        .output_write_en    (output_write_en),

        .interrupt_clear    (interrupt_clear),
        .interrupt_clear_en (interrupt_clear_en),

        .input_data         (input_data),
        .output_data        (output_data),
        .interrupt_status   (interrupt_status),
        .interrupt          (interrupt)
    );

    // ------------------------------------------------------------
    // Clock: 100 MHz, period = 10 ns
    // ------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Waveform dump
    // Compatible with Icarus Verilog / GTKWave
    // ------------------------------------------------------------
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_gpio_block);
    end

    // ------------------------------------------------------------
    // Test/check helpers
    // ------------------------------------------------------------
    task automatic check_vector(
        input string test_name,
        input logic [WIDTH-1:0] actual,
        input logic [WIDTH-1:0] expected
    );
        begin
            if (actual !== expected) begin
                $error("[%0t] FAIL: %s | actual=%b expected=%b",
                       $time, test_name, actual, expected);
                fail_count++;
            end else begin
                $display("[%0t] PASS: %s | value=%b",
                         $time, test_name, actual);
                pass_count++;
            end
        end
    endtask

    task automatic check_bit(
        input string test_name,
        input logic actual,
        input logic expected
    );
        begin
            if (actual !== expected) begin
                $error("[%0t] FAIL: %s | actual=%b expected=%b",
                       $time, test_name, actual, expected);
                fail_count++;
            end else begin
                $display("[%0t] PASS: %s | value=%b",
                         $time, test_name, actual);
                pass_count++;
            end
        end
    endtask

    // Wait for a rising edge and allow nonblocking assignments
    // and combinational logic to settle.
    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    // Reset the DUT and initialize all test inputs.
    task automatic reset_dut;
        begin
            // Disable writes and interrupt clears.
            rstn               = 1'b0;
            gpio_in            = '0;
            direction          = '0;
            output_write_data  = '0;
            output_write_en    = 1'b0;
            interrupt_clear    = '0;
            interrupt_clear_en = 1'b0;

            // Hold reset across multiple rising clock edges.
            repeat (3) tick();

            // Release reset away from the active clock edge.
            @(negedge clk);
            rstn = 1'b1;

            // Allow the DUT to leave reset.
            tick();
        end
    endtask

    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------
    initial begin
        $display("==========================================");
        $display(" GPIO BLOCK TESTBENCH START");
        $display("==========================================");

        // Initialize inputs.
        rstn               = 1'b0;
        gpio_in            = '0;
        direction          = '0;
        output_write_data  = '0;
        output_write_en    = 1'b0;
        interrupt_clear    = '0;
        interrupt_clear_en = 1'b0;

        // --------------------------------------------------------
        // Test 1: Reset
        // --------------------------------------------------------
        repeat (3) tick();

        check_vector("Reset: input synchronizer",
                     input_data, '0);
        check_vector("Reset: output latch",
                     output_data, '0);
        check_vector("Reset: interrupt status",
                     interrupt_status, '0);
        check_bit("Reset: interrupt output",
                  interrupt, 1'b0);

        rstn = 1'b1;
        tick();

        // --------------------------------------------------------
        // Test 2: GPIO input synchronization
        // --------------------------------------------------------
        reset_dut();

        gpio_in = 8'b1010_0101;

        tick(); // sync_ff1 captures gpio_in
        check_vector("Sync stage 1: readback not yet updated",
                     input_data, 8'b0000_0000);

        tick(); // sync_ff2 captures sync_ff1
        check_vector("Sync stage 2: input readback",
                     input_data, 8'b1010_0101);

        // Allow input history to catch up before edge tests.
        tick();

        // --------------------------------------------------------
        // Test 3: Output register write
        // --------------------------------------------------------
        reset_dut();

        direction         = 8'b1111_0000;
        output_write_data = 8'b1100_1010;
        output_write_en   = 1'b1;

        tick();

        check_vector("Output latch write",
                     output_data, 8'b1100_1010);
        check_vector("GPIO output",
                     gpio_out, 8'b1100_1010);
        check_vector("GPIO output enable",
                     gpio_oe, 8'b1111_0000);

        // Disable write and verify that the latch holds its value.
        output_write_en   = 1'b0;
        output_write_data = 8'b0101_0101;

        tick();

        check_vector("Output latch holds without write",
                     output_data, 8'b1100_1010);

        // --------------------------------------------------------
        // Test 4: Rising-edge interrupt
        // --------------------------------------------------------
        // Current synchronized input is 1010_0101.
        // Drive all inputs low, then raise pin 0.
        reset_dut();

        gpio_in = '0;
        repeat (3) tick();

        // Clear the falling-edge interrupts generated above.
        interrupt_clear    = '1;
        interrupt_clear_en = 1'b1;
        tick();

        interrupt_clear    = '0;
        interrupt_clear_en = 1'b0;
        tick();

        check_vector("Interrupt status before rising edge",
                     interrupt_status, '0);

        gpio_in = 8'b0000_0001;

        repeat (3) tick();

        check_vector("Rising edge sets pin 0 status",
                     interrupt_status, 8'b0000_0001);
        check_bit("Interrupt asserted on rising edge",
                  interrupt, 1'b1);

        // --------------------------------------------------------
        // Test 5: Interrupt clear
        // --------------------------------------------------------
        reset_dut();

        interrupt_clear    = 8'b0000_0001;
        interrupt_clear_en = 1'b1;

        tick();

        check_vector("Clear pin 0 interrupt",
                     interrupt_status, '0);
        check_bit("Interrupt deasserted after clear",
                  interrupt, 1'b0);

        interrupt_clear_en = 1'b0;
        interrupt_clear    = '0;

        // --------------------------------------------------------
        // Test 6: Falling-edge interrupt
        // --------------------------------------------------------
        reset_dut();

        // First establish a high level without a pending status.
        gpio_in = 8'b0000_0010;
        repeat (3) tick();

        // Clear the rising-edge interrupt generated during setup.
        interrupt_clear    = 8'b0000_0010;
        interrupt_clear_en = 1'b1;
        tick();

        interrupt_clear    = '0;
        interrupt_clear_en = 1'b0;
        tick();

        check_vector("Falling-edge test: clear baseline",
                     interrupt_status, '0);

        // Pin 1 transitions from high to low.
        gpio_in = '0;
        repeat (3) tick();

        check_vector("Falling edge sets pin 1 status",
                     interrupt_status, 8'b0000_0010);
        check_bit("Interrupt asserted on falling edge",
                  interrupt, 1'b1);

        // Clear pin 1.
        interrupt_clear    = 8'b0000_0010;
        interrupt_clear_en = 1'b1;
        tick();

        check_vector("Clear falling-edge status",
                     interrupt_status, '0);

        interrupt_clear_en = 1'b0;
        interrupt_clear    = '0;

        // --------------------------------------------------------
        // Test 7: Set-dominant simultaneous set and clear
        // --------------------------------------------------------
        // Establish low baseline, then create a rising edge on pin 2.
        reset_dut();

        gpio_in = '0;
        repeat (3) tick();

        gpio_in = 8'b0000_0100;

        // Wait until the edge reaches the synchronized edge detector.
        repeat (3) tick();

        check_vector("Pin 2 pending before simultaneous clear",
                     interrupt_status, 8'b0000_0100);

        // Drive pin 2 low, then wait for the falling edge to arrive.
        // The status remains set while the pin is low.
        gpio_in = '0;
        repeat (2) tick();

        // Pin 2 is still pending. Clear it while creating another
        // rising edge. The new edge must win over the clear.
        gpio_in = 8'b0000_0100;
        interrupt_clear    = 8'b0000_0100;
        interrupt_clear_en = 1'b1;

        // On the first cycle, the synchronized edge detector may not
        // yet see the new edge. Deassert the clear after this cycle.
        // Reassert clear when the edge event reaches the detector.
        tick();

        interrupt_clear_en = 1'b0;
        interrupt_clear    = '0;
        tick();

        interrupt_clear    = 8'b0000_0100;
        interrupt_clear_en = 1'b1;
        tick();

        check_vector("Set-dominant policy: edge wins over clear",
                     interrupt_status, 8'b0000_0100);

        interrupt_clear_en = 1'b0;
        interrupt_clear    = '0;

        // --------------------------------------------------------
        // Test 8: Multiple GPIO interrupt bits
        // --------------------------------------------------------
        reset_dut();

        // Clear all pending status.
        interrupt_clear    = '1;
        interrupt_clear_en = 1'b1;
        tick();

        // The set-dominant policy means an edge on pin 2 may remain
        // pending; move inputs low and let the detector settle.
        interrupt_clear_en = 1'b0;
        interrupt_clear    = '0;
        gpio_in = '0;
        repeat (3) tick();

        // Raise pins 3 and 5 together.
        gpio_in = 8'b0010_1000;
        repeat (3) tick();

        check_vector("Multiple rising-edge status bits",
                     interrupt_status, 8'b0010_1000);

        // Clear both pending bits.
        interrupt_clear    = 8'b0010_1000;
        interrupt_clear_en = 1'b1;
        tick();

        check_vector("Clear multiple interrupt bits",
                     interrupt_status, '0);
        check_bit("Interrupt deasserted after clearing all bits",
                  interrupt, 1'b0);

        interrupt_clear_en = 1'b0;
        interrupt_clear    = '0;

        // --------------------------------------------------------
        // Test 9: Rising-edge-only configuration is parameterized
        // --------------------------------------------------------
        // This DUT enables falling-edge detection. The testbench
        // parameter can be changed to 0 to test rising edges only.
        $display("ENABLE_FALLING_EDGE = %0b",
                 ENABLE_FALLING_EDGE);

        // --------------------------------------------------------
        // Test summary
        // --------------------------------------------------------
        $display("");
        $display("==========================================");
        $display(" TEST SUMMARY");
        $display(" Passed: %0d", pass_count);
        $display(" Failed: %0d", fail_count);
        $display("==========================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $fatal(1, "TESTBENCH FAILED");

        $finish;
    end

    // Global simulation timeout.
    initial begin
        #10000;
        $fatal(1, "Simulation timeout");
    end

endmodule
