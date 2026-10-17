module gpio_block #(
    parameter int unsigned WIDTH = 8,
    parameter bit          ENABLE_FALLING_EDGE = 1'b0
) (
    input  logic                 clk,
    input  logic                 rstn,

    // Physical GPIO interface
    input  logic [WIDTH-1:0]     gpio_in,
    output logic [WIDTH-1:0]     gpio_out,
    output logic [WIDTH-1:0]     gpio_oe,

    // Software/register interface
    input  logic [WIDTH-1:0]     direction,
    input  logic [WIDTH-1:0]     output_write_data,
    input  logic                 output_write_en,

    input  logic [WIDTH-1:0]     interrupt_clear,
    input  logic                 interrupt_clear_en,

    // Readback and interrupts
    output logic [WIDTH-1:0]     input_data,
    output logic [WIDTH-1:0]     output_data,
    output logic [WIDTH-1:0]     interrupt_status,
    output logic                 interrupt
);

    // Two-flop synchronizer for asynchronous GPIO inputs.
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_ff1;
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_ff2;

    logic [WIDTH-1:0] previous_input;
    logic [WIDTH-1:0] rising_edges;
    logic [WIDTH-1:0] falling_edges;
    logic [WIDTH-1:0] edge_events;

    // Registered output latch.
    logic [WIDTH-1:0] output_latch;

    // Direction: 1 = output, 0 = input.
    assign gpio_oe    = direction;
    assign gpio_out   = output_latch;
    assign output_data = output_latch;
    assign input_data  = sync_ff2;

    // Edge detection operates on synchronized signals.
    assign rising_edges  =  sync_ff2 & ~previous_input;
    assign falling_edges = ~sync_ff2 &  previous_input;

    assign edge_events = rising_edges |
        (ENABLE_FALLING_EDGE ? falling_edges
                             : {WIDTH{1'b0}});

    // Interrupt is asserted when any pin has pending status.
    assign interrupt = |interrupt_status;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            sync_ff1        <= '0;
            sync_ff2        <= '0;
            previous_input  <= '0;
            output_latch    <= '0;
            interrupt_status <= '0;
        end else begin
            // Synchronize physical inputs.
            sync_ff1       <= gpio_in;
            sync_ff2       <= sync_ff1;
            previous_input <= sync_ff2;

            // Update output latch only on a write.
            if (output_write_en)
                output_latch <= output_write_data;

            // Set-dominant interrupt policy:
            // new edge events win over simultaneous clears.
            interrupt_status <= (interrupt_status & ~(interrupt_clear_en ?
                                                        interrupt_clear :
                                                        {WIDTH{1'b0}})) | edge_events;
        end
    end

endmodule
