`timescale 1ns/1ps

module tb_timer;

    localparam int WIDTH = 8;

    logic             clk;
    logic             reset_n;
    logic             timer_enable;
    logic [WIDTH-1:0] prescaler_divider;
    logic [WIDTH-1:0] timer_reload_value;
    logic             periodic_mode;
    logic             clear_expiry_status;

    logic [WIDTH-1:0] timer_counter;
    logic             timer_active;
    logic             expiry_pulse;
    logic             expiry_pending;

    int tests_passed;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    timer #(
        .WIDTH(WIDTH)
    ) dut (
        .clk                  (clk),
        .reset_n              (reset_n),
        .timer_enable         (timer_enable),
        .prescaler_divider    (prescaler_divider),
        .timer_reload_value   (timer_reload_value),
        .periodic_mode        (periodic_mode),
        .clear_expiry_status  (clear_expiry_status),
        .timer_counter        (timer_counter),
        .timer_active         (timer_active),
        .expiry_pulse         (expiry_pulse),
        .expiry_pending       (expiry_pending)
    );

    // ------------------------------------------------------------
    // Clock: 10 ns period
    // ------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Advance simulation by one clock cycle.
    // Sample after sequential logic and nonblocking assignments.
    // ------------------------------------------------------------
    task automatic step;
        @(posedge clk);
        #1;
    endtask

    // ------------------------------------------------------------
    // Check helper
    // ------------------------------------------------------------
    task automatic check(
        input logic condition,
        input string message
    );
        if (condition !== 1'b1) begin
            $error(
                "FAIL at time %0t: %s",
                $time, message
            );
            $fatal(1, "Testbench failed");
        end else begin
            $display(
                "PASS at time %0t: %s",
                $time, message
            );
            tests_passed++;
        end
    endtask

    // ------------------------------------------------------------
    // Reset helper
    // ------------------------------------------------------------
    task automatic reset_dut;
        @(negedge clk);
        reset_n             = 1'b0;
        timer_enable        = 1'b0;
        prescaler_divider   = 1;
        timer_reload_value  = 0;
        periodic_mode       = 1'b0;
        clear_expiry_status = 1'b0;

        repeat (2) step();

        check(timer_counter == 0, "Reset clears timer_counter");
        check(timer_active == 0, "Reset clears timer_active");
        check(expiry_pulse == 0, "Reset clears expiry_pulse");
        check(expiry_pending == 0, "Reset clears expiry_pending");

        @(negedge clk);
        reset_n = 1'b1;
        step();
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        tests_passed         = 0;
        reset_n              = 1'b0;
        timer_enable         = 1'b0;
        prescaler_divider    = 1;
        timer_reload_value   = 0;
        periodic_mode        = 1'b0;
        clear_expiry_status  = 1'b0;

        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_timer);

        $display("");
        $display("========================================");
        $display(" TIMER TESTBENCH START");
        $display("========================================");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        $display("");
        $display("TEST 1: Reset");
        reset_dut();

        // ========================================================
        // TEST 2: One-shot countdown and expiry
        // ========================================================
        $display("");
        $display("TEST 2: One-shot countdown");

        @(negedge clk);
        timer_enable       = 1'b1;
        prescaler_divider  = 1;
        timer_reload_value = 3;
        periodic_mode      = 1'b0;

        // Timer starts and loads the reload value.
        step();

        check(timer_active == 1, "Timer becomes active");
        check(timer_counter == 3, "Counter loads value 3");
        check(expiry_pulse == 0, "No expiry on initial load");

        // Divider = 1: one countdown step per clock.
        step();
        check(timer_counter == 2, "Countdown: 3 -> 2");

        step();
        check(timer_counter == 1, "Countdown: 2 -> 1");

        step();
        check(timer_counter == 0, "Countdown: 1 -> 0");
        check(expiry_pulse == 0, "Expiry waits until next tick");

        step();
        check(expiry_pulse == 1, "Expiry pulse asserted");
        check(expiry_pending == 1, "Expiry status becomes pending");
        check(timer_active == 0, "One-shot timer stops");

        step();
        check(expiry_pulse == 0, "Expiry pulse lasts one cycle");
        check(expiry_pending == 1, "Pending status remains set");

        // ========================================================
        // TEST 3: Clear expiry status
        // ========================================================
        $display("");
        $display("TEST 3: Clear expiry status");

        @(negedge clk);
        clear_expiry_status = 1'b1;

        step();
        check(expiry_pending == 0, "Pending status clears");

        @(negedge clk);
        clear_expiry_status = 1'b0;

        // ========================================================
        // TEST 4: Periodic mode
        // ========================================================
        $display("");
        $display("TEST 4: Periodic mode");

        reset_dut();

        @(negedge clk);
        timer_enable       = 1'b1;
        prescaler_divider  = 1;
        timer_reload_value = 2;
        periodic_mode      = 1'b1;

        step();
        check(timer_active == 1, "Periodic timer starts");
        check(timer_counter == 2, "Initial periodic load");

        step();
        check(timer_counter == 1, "Periodic countdown: 2 -> 1");

        step();
        check(timer_counter == 0, "Periodic countdown: 1 -> 0");

        step();
        check(expiry_pulse == 1, "First periodic expiry");
        check(expiry_pending == 1, "First expiry sets pending");
        check(timer_active == 1, "Periodic timer stays active");
        check(timer_counter == 2, "Counter reloads after expiry");

        step();
        check(expiry_pulse == 0, "First pulse deasserts");
        check(timer_counter == 1, "Second periodic countdown starts");

        step();
        check(timer_counter == 0, "Second countdown reaches zero");

        step();
        check(expiry_pulse == 1, "Second periodic expiry");
        check(timer_counter == 2, "Second periodic reload");

        // ========================================================
        // TEST 5: Prescaler timing
        // ========================================================
        $display("");
        $display("TEST 5: Prescaler divider");

        reset_dut();

        @(negedge clk);
        timer_enable       = 1'b1;
        prescaler_divider  = 3;
        timer_reload_value = 1;
        periodic_mode      = 1'b0;

        step();
        check(timer_counter == 1, "Prescaler test initial load");

        // The first two active clocks must not decrement.
        step();
        check(timer_counter == 1, "Divider 3: no early decrement");

        step();
        check(timer_counter == 1, "Divider 3: still waiting");

        // Third active clock produces the tick.
        step();
        check(timer_counter == 0, "Divider 3: countdown tick");

        // The next tick occurs three clocks later and expires.
        step();
        check(expiry_pulse == 0, "No early expiry after zero");

        step();
        check(expiry_pulse == 0, "Still waiting for next tick");

        step();
        check(expiry_pulse == 1, "Expiry on the next prescaled tick");
        check(timer_active == 0, "One-shot timer stops after expiry");

        // ========================================================
        // TEST 6: Disable and re-enable
        // ========================================================
        $display("");
        $display("TEST 6: Disable and re-enable");

        reset_dut();

        @(negedge clk);
        timer_enable       = 1'b1;
        prescaler_divider  = 1;
        timer_reload_value = 5;
        periodic_mode      = 1'b0;

        step();
        check(timer_active == 1, "Timer starts for disable test");
        check(timer_counter == 5, "Reload value is 5");

        step();
        check(timer_counter == 4, "Counter decrements to 4");

        @(negedge clk);
        timer_enable = 1'b0;

        step();
        check(timer_active == 0, "Disabling timer stops it");
        check(timer_counter == 4, "Disable preserves counter value");

        @(negedge clk);
        timer_enable = 1'b1;

        step();
        check(timer_active == 1, "Timer reactivates");
        check(timer_counter == 5, "Reactivation reloads counter");

        // ========================================================
        // TEST 7: Divider values 0 and 1
        // ========================================================
        $display("");
        $display("TEST 7: Divider boundary values");

        reset_dut();

        @(negedge clk);
        timer_enable       = 1'b1;
        prescaler_divider  = 0;
        timer_reload_value = 2;
        periodic_mode      = 1'b0;

        step();
        check(timer_counter == 2, "Divider 0 initial load");

        step();
        check(timer_counter == 1, "Divider 0 ticks every clock");

        @(negedge clk);
        timer_enable = 1'b0;

        step();

        reset_dut();

        @(negedge clk);
        timer_enable       = 1'b1;
        prescaler_divider  = 1;
        timer_reload_value = 2;
        periodic_mode      = 1'b0;

        step();
        step();
        check(timer_counter == 1, "Divider 1 ticks every clock");

        // ========================================================
        // Summary
        // ========================================================
        $display("");
        $display("========================================");
        $display(" ALL TESTS PASSED");
        $display(" Checks passed: %0d", tests_passed);
        $display("========================================");

        $finish;
    end

    // ------------------------------------------------------------
    // Watchdog: prevent a hung simulation
    // ------------------------------------------------------------
    initial begin
        #100000;
        $fatal(1, "Watchdog timeout");
    end

endmodule
