`timescale 1ns/1ps

module tb_apb_slave;
    localparam int GPIO_WIDTH  = 8;
    localparam int TIMER_WIDTH = 32;

    logic PCLK = 1'b0;
    logic PRESETn = 1'b1;
    always #5 PCLK = ~PCLK;

    logic [31:0] PADDR;
    logic PSEL, PENABLE, PWRITE;
    logic [31:0] PWDATA;
    logic [3:0] PSTRB;
    logic [2:0] PPROT;
    logic [31:0] PRDATA;
    logic PREADY, PSLVERR;

    logic [GPIO_WIDTH-1:0] gpio_direction, gpio_irq_enable;
    logic timer_enable, timer_periodic_mode, timer_irq_enable;
    logic [TIMER_WIDTH-1:0] timer_reload_value, timer_prescaler_divider;

    logic [GPIO_WIDTH-1:0] gpio_input_data, gpio_output_data, gpio_irq_status;
    logic [GPIO_WIDTH-1:0] gpio_output_write_data, gpio_irq_clear_data;
    logic gpio_output_write_en, gpio_irq_clear_en;

    logic [TIMER_WIDTH-1:0] timer_count;
    logic timer_active, timer_expiry_pending, timer_clear_expiry;
    logic timer_irq_level, gpio_irq_level;

    int tests_passed = 0;

    apb_slave #(.GPIO_WIDTH(GPIO_WIDTH), .TIMER_WIDTH(TIMER_WIDTH)) dut (

        .PCLK(PCLK), 
        .PRESETn(PRESETn),
        .PADDR(PADDR), 
        .PSEL(PSEL), 
        .PENABLE(PENABLE), 
        .PWRITE(PWRITE),
        .PWDATA(PWDATA), 
        .PSTRB(PSTRB), 
        .PPROT(PPROT),
        .PRDATA(PRDATA), 
        .PREADY(PREADY), 
        .PSLVERR(PSLVERR),

        .gpio_direction(gpio_direction), 
        .gpio_irq_enable(gpio_irq_enable),
        .timer_enable(timer_enable),
        .timer_periodic_mode(timer_periodic_mode),
        .timer_irq_enable(timer_irq_enable), 
        .timer_reload_value(timer_reload_value),
        .timer_prescaler_divider(timer_prescaler_divider),

        .gpio_input_data(gpio_input_data), 
        .gpio_output_data(gpio_output_data),
        .gpio_irq_status(gpio_irq_status),
        .gpio_output_write_data(gpio_output_write_data),
        .gpio_output_write_en(gpio_output_write_en),
        .gpio_irq_clear_data(gpio_irq_clear_data), 
        .gpio_irq_clear_en(gpio_irq_clear_en),

        .timer_count(timer_count), 
        .timer_active(timer_active),
        .timer_expiry_pending(timer_expiry_pending), 
        .timer_clear_expiry(timer_clear_expiry),

        .timer_irq_level(timer_irq_level), 
        .gpio_irq_level(gpio_irq_level)
    );

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1) begin
            $error("FAIL: %s", message);
            $fatal(1);
        end
        tests_passed++;
        $display("PASS: %s", message);
    endtask

    task automatic idle_bus;
        @(negedge PCLK);
        PSEL = 0; PENABLE = 0; PWRITE = 0;
        PADDR = '0; PWDATA = '0; PSTRB = '0; PPROT = '0;
    endtask

    // APB transfer: drive SETUP, then ACCESS; check response before the
    // completing rising edge. A transfer with an error must not commit.
    task automatic apb_transfer(
        input logic write_transfer,
        input logic [31:0] address,
        input logic [31:0] write_data,
        input logic [3:0] strobe,
        input logic expect_error,
        output logic [31:0] read_data
    );
        @(negedge PCLK);
        PSEL = 1; PENABLE = 0; PWRITE = write_transfer;
        PADDR = address; PWDATA = write_data; PSTRB = strobe; PPROT = 3'b000;
        @(negedge PCLK);
        PENABLE = 1;
        #1;
        check(PREADY === 1'b1, "PREADY asserted in APB access phase");
        check(PSLVERR === expect_error, "PSLVERR matches expected response");
        if (write_transfer && !expect_error && address == 32'h08) begin
            check(gpio_output_write_en === 1'b1, "GPIO output write strobe asserted during APB access");
            check(gpio_output_write_data[7:0] == ((gpio_output_data & ~({8{strobe[0]}})) | (write_data[7:0] & {8{strobe[0]}})), "GPIO output write data merges enabled byte lane");
        end
        if (write_transfer && !expect_error && address == 32'h10) begin
            check(gpio_irq_clear_en === 1'b1, "GPIO IRQ clear strobe asserted during APB access");
            check(gpio_irq_clear_data[7:0] == write_data[7:0], "GPIO IRQ clear data follows write data");
        end
        if (write_transfer && !expect_error && address == 32'h28 && strobe[0] && write_data[1])
            check(timer_clear_expiry === 1'b1, "timer expiry clear asserted for W1C write");
        read_data = PRDATA;
        @(posedge PCLK);
        #1;
        @(negedge PCLK);
        PSEL = 0; PENABLE = 0; PWRITE = 0;
        PADDR = '0; PWDATA = '0; PSTRB = '0;
    endtask

    logic [31:0] rd;
    initial begin
        PADDR = '0; PSEL = 0; PENABLE = 0; PWRITE = 0;
        PWDATA = '0; PSTRB = '0; PPROT = '0;
        gpio_input_data = 8'hA5;
        gpio_output_data = 8'h3C;
        gpio_irq_status = 8'h12;
        timer_count = 32'h1234_5678;
        timer_active = 1'b1;
        timer_expiry_pending = 1'b1;
        timer_irq_level = 1'b1;
        gpio_irq_level = 1'b0;

        // Assert then release asynchronous active-low reset.
        #2;
        PRESETn = 0;
        #2;
        check(gpio_direction == 0 && gpio_irq_enable == 0, "reset clears GPIO configuration");
        check(!timer_enable && !timer_periodic_mode && !timer_irq_enable, "reset clears timer control");
        check(timer_reload_value == 0, "reset clears timer reload value");
        check(timer_prescaler_divider == 1, "reset initializes prescaler divider to one");
        repeat (2) @(negedge PCLK);
        PRESETn = 1;

        // Read-only ID and peripheral-provided values.
        apb_transfer(0, 32'h00, 0, 4'hF, 0, rd);
        check(rd == 32'h4150_4247, "ID register reads expected constant");
        apb_transfer(0, 32'h0C, 0, 4'hF, 0, rd);
        check(rd[7:0] == 8'hA5, "GPIO input register reflects peripheral input");
        apb_transfer(0, 32'h24, 0, 4'hF, 0, rd);
        check(rd == 32'h1234_5678, "timer count register reflects peripheral count");
        apb_transfer(0, 32'h28, 0, 4'hF, 0, rd);
        check(rd[1:0] == 2'b11, "timer status reports active and expiry pending");
        apb_transfer(0, 32'h2C, 0, 4'hF, 0, rd);
        check(rd[1:0] == 2'b01, "IRQ status reports timer and GPIO levels");

        // Basic configuration writes and readback.
        apb_transfer(1, 32'h04, 32'h0000_00A5, 4'h1, 0, rd);
        check(gpio_direction == 8'hA5, "GPIO direction write updates register");
        apb_transfer(1, 32'h14, 32'h0000_005A, 4'h1, 0, rd);
        check(gpio_irq_enable == 8'h5A, "GPIO IRQ enable write updates register");
        apb_transfer(1, 32'h18, 32'h0000_0007, 4'h1, 0, rd);
        check(timer_enable && timer_periodic_mode && timer_irq_enable, "timer control bits update");
        apb_transfer(1, 32'h1C, 32'hCAFE_BABE, 4'hF, 0, rd);
        check(timer_reload_value == 32'hCAFE_BABE, "timer reload register write updates all byte lanes");
        apb_transfer(1, 32'h20, 32'h0000_1234, 4'hF, 0, rd);
        check(timer_prescaler_divider == 32'h0000_1234, "timer prescaler register write updates");
        apb_transfer(0, 32'h04, 0, 4'hF, 0, rd);
        check(rd[7:0] == 8'hA5, "GPIO direction register readback");
        apb_transfer(0, 32'h18, 0, 4'hF, 0, rd);
        check(rd[2:0] == 3'b111, "timer control register readback");

        // Partial byte write must preserve untouched bytes.
        apb_transfer(1, 32'h1C, 32'h1122_3344, 4'hF, 0, rd);
        apb_transfer(1, 32'h1C, 32'h0000_AA00, 4'b0010, 0, rd);
        check(timer_reload_value == 32'h1122_AA44, "PSTRB updates only selected byte lane");

        // Peripheral write/clear strobes and byte-lane behavior.
        apb_transfer(1, 32'h08, 32'h0000_00C3, 4'h1, 0, rd);
        #1;
        check(gpio_output_write_en === 1'b0, "GPIO output write enable deasserts after transfer");
        apb_transfer(1, 32'h10, 32'h0000_0002, 4'h1, 0, rd);
        #1;
        check(gpio_irq_clear_en === 1'b0, "GPIO IRQ clear enable deasserts after transfer");
        apb_transfer(1, 32'h28, 32'h0000_0002, 4'h1, 0, rd);
        #1;
        check(timer_clear_expiry === 1'b0, "timer expiry clear pulse deasserts after transfer");

        // Invalid and illegal writes must return errors and not alter config.
        apb_transfer(1, 32'h04, 32'h0000_00A5, 4'h1, 0, rd);
        apb_transfer(1, 32'h00, 32'hFFFF_FFFF, 4'hF, 1, rd);
        check(gpio_direction == 8'hA5, "write to read-only ID has no configuration side effect");
        apb_transfer(0, 32'h30, 0, 4'hF, 1, rd);
        apb_transfer(0, 32'h05, 0, 4'hF, 1, rd);
        apb_transfer(1, 32'h30, 32'hFFFF_FFFF, 4'hF, 1, rd);
        check(gpio_direction == 8'hA5, "invalid accesses do not modify GPIO direction");

        // Outside access phase, PREADY/PSLVERR should be low.
        idle_bus();
        #1;
        check(PREADY === 1'b0 && PSLVERR === 1'b0, "no ready/error response outside APB access phase");

        $display("\nAll APB slave tests passed: %0d checks", tests_passed);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "TIMEOUT: testbench did not finish");
    end
endmodule
