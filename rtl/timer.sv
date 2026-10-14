module timer #(
    parameter int WIDTH = 32
) (
    input  logic             clk,
    input  logic             reset_n,

    input  logic             timer_enable,
    input  logic [WIDTH-1:0] prescaler_divider,
    input  logic [WIDTH-1:0] timer_reload_value,
    input  logic             periodic_mode,
    input  logic             clear_expiry_status,

    output logic [WIDTH-1:0] timer_counter,
    output logic             timer_active,
    output logic             expiry_pulse,
    output logic             expiry_pending
);

    logic [WIDTH-1:0] prescaler_counter;
    logic             tick;

    always_comb begin
        tick = 1'b0;

        if (timer_enable && timer_active) begin
            if (prescaler_divider <= 1)
                tick = 1'b1;
            else if (prescaler_counter ==
                    prescaler_divider - 1'b1)
                tick = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            prescaler_counter <= '0;
        end else if (!timer_enable || !timer_active || tick) begin
            prescaler_counter <= '0;
        end else begin
            prescaler_counter <= prescaler_counter + 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            timer_counter  <= '0;
            timer_active   <= 1'b0;
            expiry_pulse   <= 1'b0;
            expiry_pending <= 1'b0;
        end else begin
            expiry_pulse <= 1'b0;

            if (clear_expiry_status)
                expiry_pending <= 1'b0;

            if (!timer_enable) begin
                timer_active <= 1'b0;
            end else if (!timer_active) begin
                timer_active  <= 1'b1;
                timer_counter <= timer_reload_value;
            end else if (tick) begin
                if (timer_counter == '0) begin
                    expiry_pulse   <= 1'b1;
                    expiry_pending <= 1'b1;

                    if (periodic_mode) begin
                        timer_counter <= timer_reload_value;
                    end else begin
                        timer_active <= 1'b0;
                    end
                end else begin
                    timer_counter <= timer_counter - 1'b1;
                end
            end
        end
    end

endmodule
