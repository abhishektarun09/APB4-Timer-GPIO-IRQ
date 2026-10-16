`timescale 1ns/1ps

module tb_irq_aggregator;

    localparam int unsigned NUM_IRQS = 2;

    logic [NUM_IRQS-1:0] irq_sources;
    logic                irq_out;

    // DUT instantiation
    irq_aggregator #(
        .NUM_IRQS(NUM_IRQS)
    ) dut (
        .irq_sources(irq_sources),
        .irq_out    (irq_out)
    );

    // ------------------------------------------------------------
    // Waveform dump
    // Compatible with Icarus Verilog / GTKWave
    // ------------------------------------------------------------
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_irq_aggregator);
    end

    // Test procedure
    initial begin
        $display("Starting irq_aggregator testbench...");
        $display("Time\tirq_sources\tirq_out");

        // Test all possible input combinations
        for (int i = 0; i < (1 << NUM_IRQS); i++) begin
            irq_sources = i;
            #10;

            $display("%0t\t%b\t\t%b",
                     $time, irq_sources, irq_out);

            // Check expected output
            if (irq_out !== (|irq_sources)) begin
                $error("FAIL: irq_sources=%b, irq_out=%b, expected=%b",
                       irq_sources, irq_out, (|irq_sources));
                $fatal(1, "Test failed.");
            end
        end

        $display("PASS: All test cases passed.");
        $finish;
    end

endmodule
