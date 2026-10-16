module irq_aggregator #(
    parameter int unsigned NUM_IRQS = 2
) (
    input  logic [NUM_IRQS-1:0] irq_sources,
    output logic               irq_out
);

    assign irq_out = |irq_sources;

endmodule
