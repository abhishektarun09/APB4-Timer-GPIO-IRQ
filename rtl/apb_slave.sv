module apb_slave #(
    parameter int unsigned GPIO_WIDTH  = 8,
    parameter int unsigned TIMER_WIDTH = 32
) (
    input  logic                  PCLK,
    input  logic                  PRESETn,

    // APB4 slave interface
    input  logic [31:0]           PADDR,
    input  logic                  PSEL,
    input  logic                  PENABLE,
    input  logic                  PWRITE,
    input  logic [31:0]           PWDATA,
    input  logic [3:0]            PSTRB,
    input  logic [2:0]            PPROT,
    output logic [31:0]           PRDATA,
    output logic                  PREADY,
    output logic                  PSLVERR,

    // Configuration owned by the APB register bank
    output logic [GPIO_WIDTH-1:0] gpio_direction,
    output logic [GPIO_WIDTH-1:0] gpio_irq_enable,
    output logic                  timer_enable,
    output logic                  timer_periodic_mode,
    output logic                  timer_irq_enable,
    output logic [TIMER_WIDTH-1:0] timer_reload_value,
    output logic [TIMER_WIDTH-1:0] timer_prescaler_divider,

    // GPIO register/peripheral interface
    input  logic [GPIO_WIDTH-1:0] gpio_input_data,
    input  logic [GPIO_WIDTH-1:0] gpio_output_data,
    input  logic [GPIO_WIDTH-1:0] gpio_irq_status,
    output logic [GPIO_WIDTH-1:0] gpio_output_write_data,
    output logic                  gpio_output_write_en,
    output logic [GPIO_WIDTH-1:0] gpio_irq_clear_data,
    output logic                  gpio_irq_clear_en,

    // Timer register/peripheral interface
    input  logic [TIMER_WIDTH-1:0] timer_count,
    input  logic                   timer_active,
    input  logic                   timer_expiry_pending,
    output logic                   timer_clear_expiry,

    // Interrupt levels are supplied by top.sv and are also readable at APB.
    input  logic                  timer_irq_level,
    input  logic                  gpio_irq_level
);

    // Register map: all registers are 32-bit word aligned.
    localparam logic [7:0] ADDR_ID               = 8'h00; // RO
    localparam logic [7:0] ADDR_GPIO_DIR         = 8'h04; // RW
    localparam logic [7:0] ADDR_GPIO_OUT         = 8'h08; // RW
    localparam logic [7:0] ADDR_GPIO_IN          = 8'h0C; // RO
    localparam logic [7:0] ADDR_GPIO_IRQ_STATUS  = 8'h10; // RW1C
    localparam logic [7:0] ADDR_GPIO_IRQ_ENABLE  = 8'h14; // RW
    localparam logic [7:0] ADDR_TIMER_CTRL       = 8'h18; // RW
    localparam logic [7:0] ADDR_TIMER_RELOAD     = 8'h1C; // RW
    localparam logic [7:0] ADDR_TIMER_PRESCALER  = 8'h20; // RW
    localparam logic [7:0] ADDR_TIMER_COUNT      = 8'h24; // RO
    localparam logic [7:0] ADDR_TIMER_STATUS     = 8'h28; // bit 1 is RW1C
    localparam logic [7:0] ADDR_IRQ_STATUS       = 8'h2C; // RO

    localparam logic [31:0] PERIPHERAL_ID = 32'h4150_4247; // "APBG"

    logic [GPIO_WIDTH-1:0]  gpio_direction_reg;
    logic [GPIO_WIDTH-1:0]  gpio_irq_enable_reg;
    logic [2:0]             timer_ctrl_reg;
    logic [TIMER_WIDTH-1:0] timer_reload_reg;
    logic [TIMER_WIDTH-1:0] timer_prescaler_reg;

    logic access_phase;
    logic address_aligned;
    logic address_in_apb_window;
    logic address_known;
    logic address_valid;
    logic read_only_address;
    logic apb_write_commit;

    assign access_phase          = PSEL && PENABLE;
    assign address_aligned       = (PADDR[1:0] == 2'b00);
    assign address_in_apb_window = (PADDR[31:8] == 24'h0);
    assign address_valid         = address_in_apb_window &&
                                   address_aligned && address_known;

    always_comb begin
        address_known = 1'b1;
        case (PADDR[7:0])
            ADDR_ID,
            ADDR_GPIO_DIR,
            ADDR_GPIO_OUT,
            ADDR_GPIO_IN,
            ADDR_GPIO_IRQ_STATUS,
            ADDR_GPIO_IRQ_ENABLE,
            ADDR_TIMER_CTRL,
            ADDR_TIMER_RELOAD,
            ADDR_TIMER_PRESCALER,
            ADDR_TIMER_COUNT,
            ADDR_TIMER_STATUS,
            ADDR_IRQ_STATUS: address_known = 1'b1;
            default:         address_known = 1'b0;
        endcase
    end

    always_comb begin
        read_only_address = 1'b0;
        case (PADDR[7:0])
            ADDR_ID,
            ADDR_GPIO_IN,
            ADDR_TIMER_COUNT,
            ADDR_IRQ_STATUS: read_only_address = 1'b1;
            default:         read_only_address = 1'b0;
        endcase
    end

    // Zero-wait-state APB peripheral. Error is asserted only in access phase.
    always_comb begin
        PREADY  = access_phase;
        PSLVERR = 1'b0;
        if (access_phase) begin
            if (!address_valid)
                PSLVERR = 1'b1;
            else if (PWRITE && read_only_address)
                PSLVERR = 1'b1;
        end
    enda

    assign apb_write_commit = access_phase && PREADY && !PSLVERR && PWRITE;

    // Export the stored configuration to top.sv and its functional blocks.
    assign gpio_direction       = gpio_direction_reg;
    assign gpio_irq_enable      = gpio_irq_enable_reg;
    assign timer_enable         = timer_ctrl_reg[0];
    assign timer_periodic_mode  = timer_ctrl_reg[1];
    assign timer_irq_enable     = timer_ctrl_reg[2];
    assign timer_reload_value   = timer_reload_reg;
    assign timer_prescaler_divider = timer_prescaler_reg;

    // GPIO output is a whole-vector port. Merge byte strobes against the
    // current output latch so partial APB writes preserve untouched bits.
    always_comb begin
        gpio_output_write_data = gpio_output_data;
        for (int bit_index = 0; bit_index < GPIO_WIDTH; bit_index++) begin
            if (PSTRB[bit_index / 8])
                gpio_output_write_data[bit_index] = PWDATA[bit_index];
        end
    end

    // Apply PSTRB to write-one-to-clear data as well. The clear enable only
    // pulses for a successful write to the GPIO interrupt status register.
    always_comb begin
        gpio_irq_clear_data = '0;
        for (int bit_index = 0; bit_index < GPIO_WIDTH; bit_index++) begin
            if (PSTRB[bit_index / 8])
                gpio_irq_clear_data[bit_index] = PWDATA[bit_index];
        end
    end

    assign gpio_output_write_en = apb_write_commit &&
                                  (PADDR[7:0] == ADDR_GPIO_OUT);
    assign gpio_irq_clear_en    = apb_write_commit &&
                                  (PADDR[7:0] == ADDR_GPIO_IRQ_STATUS);
    assign timer_clear_expiry   = apb_write_commit &&
                                  (PADDR[7:0] == ADDR_TIMER_STATUS) &&
                                  PSTRB[0] && PWDATA[1];

    // APB-owned configuration registers. Active-low asynchronous reset.
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            gpio_direction_reg  <= '0;
            gpio_irq_enable_reg <= '0;
            timer_ctrl_reg      <= '0;
            timer_reload_reg    <= '0;
            timer_prescaler_reg <= {{(TIMER_WIDTH-1){1'b0}}, 1'b1};
        end else if (apb_write_commit) begin
            case (PADDR[7:0])
                ADDR_GPIO_DIR: begin
                    for (int bit_index = 0; bit_index < GPIO_WIDTH; bit_index++) begin
                        if (PSTRB[bit_index / 8])
                            gpio_direction_reg[bit_index] <= PWDATA[bit_index];
                    end
                end

                ADDR_GPIO_IRQ_ENABLE: begin
                    for (int bit_index = 0; bit_index < GPIO_WIDTH; bit_index++) begin
                        if (PSTRB[bit_index / 8])
                            gpio_irq_enable_reg[bit_index] <= PWDATA[bit_index];
                    end
                end

                ADDR_TIMER_CTRL: begin
                    if (PSTRB[0])
                        timer_ctrl_reg <= PWDATA[2:0];
                end

                ADDR_TIMER_RELOAD: begin
                    for (int bit_index = 0; bit_index < TIMER_WIDTH; bit_index++) begin
                        if (PSTRB[bit_index / 8])
                            timer_reload_reg[bit_index] <= PWDATA[bit_index];
                    end
                end

                ADDR_TIMER_PRESCALER: begin
                    for (int bit_index = 0; bit_index < TIMER_WIDTH; bit_index++) begin
                        if (PSTRB[bit_index / 8])
                            timer_prescaler_reg[bit_index] <= PWDATA[bit_index];
                    end
                end

                default: begin
                    // GPIO output and peripheral status are owned by the IPs.
                end
            endcase
        end
    end

    // Single read mux for all software-visible registers.
    always_comb begin
        PRDATA = 32'h0000_0000;
        if (address_valid) begin
            case (PADDR[7:0])
                ADDR_ID:              PRDATA = PERIPHERAL_ID;
                ADDR_GPIO_DIR:        PRDATA[GPIO_WIDTH-1:0] = gpio_direction_reg;
                ADDR_GPIO_OUT:        PRDATA[GPIO_WIDTH-1:0] = gpio_output_data;
                ADDR_GPIO_IN:         PRDATA[GPIO_WIDTH-1:0] = gpio_input_data;
                ADDR_GPIO_IRQ_STATUS: PRDATA[GPIO_WIDTH-1:0] = gpio_irq_status;
                ADDR_GPIO_IRQ_ENABLE: PRDATA[GPIO_WIDTH-1:0] = gpio_irq_enable_reg;
                ADDR_TIMER_CTRL:      PRDATA[2:0] = timer_ctrl_reg;
                ADDR_TIMER_RELOAD:    PRDATA[TIMER_WIDTH-1:0] = timer_reload_reg;
                ADDR_TIMER_PRESCALER: PRDATA[TIMER_WIDTH-1:0] = timer_prescaler_reg;
                ADDR_TIMER_COUNT:     PRDATA[TIMER_WIDTH-1:0] = timer_count;
                ADDR_TIMER_STATUS: begin
                    PRDATA[0] = timer_active;
                    PRDATA[1] = timer_expiry_pending;
                end
                ADDR_IRQ_STATUS: begin
                    PRDATA[0] = timer_irq_level;
                    PRDATA[1] = gpio_irq_level;
                end
                default: PRDATA = 32'h0000_0000;
            endcase
        end
    end

    // PPROT is part of the APB4 interface but is currently not used for
    // protection checks. Keep the port so this module remains APB4-shaped.

    initial begin
        if ((GPIO_WIDTH < 1) || (GPIO_WIDTH > 32))
            $error("GPIO_WIDTH must be in the range 1..32");
        if ((TIMER_WIDTH < 1) || (TIMER_WIDTH > 32))
            $error("TIMER_WIDTH must be in the range 1..32");
    end

endmodule
