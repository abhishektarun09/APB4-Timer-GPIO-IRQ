module top #(
    parameter int unsigned GPIO_WIDTH = 8,
    parameter int unsigned TIMER_WIDTH = 32,
    parameter bit GPIO_ENABLE_FALLING_EDGE = 1'b0
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

    // Physical GPIO interface
    input  logic [GPIO_WIDTH-1:0] gpio_in,
    output logic [GPIO_WIDTH-1:0] gpio_out,
    output logic [GPIO_WIDTH-1:0] gpio_oe,

    // Combined level-sensitive interrupt
    output logic                  IRQ
);

    logic [GPIO_WIDTH-1:0] gpio_direction;
    logic [GPIO_WIDTH-1:0] gpio_irq_enable;
    logic [GPIO_WIDTH-1:0] gpio_input_data;
    logic [GPIO_WIDTH-1:0] gpio_output_data;
    logic [GPIO_WIDTH-1:0] gpio_irq_status;
    logic [GPIO_WIDTH-1:0] gpio_output_write_data;
    logic [GPIO_WIDTH-1:0] gpio_irq_clear_data;
    logic                  gpio_output_write_en;
    logic                  gpio_irq_clear_en;
    logic                  gpio_interrupt_unused;

    logic                  timer_enable;
    logic                  timer_periodic_mode;
    logic                  timer_irq_enable;
    logic [TIMER_WIDTH-1:0] timer_reload_value;
    logic [TIMER_WIDTH-1:0] timer_prescaler_divider;
    logic [TIMER_WIDTH-1:0] timer_count;
    logic                   timer_active;
    logic                   timer_expiry_pulse;
    logic                   timer_expiry_pending;
    logic                   timer_clear_expiry;

    logic timer_irq_level;
    logic gpio_irq_level;
    logic [1:0] irq_sources;

    apb_slave #(
        .GPIO_WIDTH (GPIO_WIDTH),
        .TIMER_WIDTH(TIMER_WIDTH)
    ) u_apb_slave (
        .PCLK                   (PCLK),
        .PRESETn                (PRESETn),
        .PADDR                  (PADDR),
        .PSEL                   (PSEL),
        .PENABLE                (PENABLE),
        .PWRITE                 (PWRITE),
        .PWDATA                 (PWDATA),
        .PSTRB                  (PSTRB),
        .PPROT                  (PPROT),
        .PRDATA                 (PRDATA),
        .PREADY                 (PREADY),
        .PSLVERR                (PSLVERR),
        .gpio_direction         (gpio_direction),
        .gpio_irq_enable        (gpio_irq_enable),
        .timer_enable           (timer_enable),
        .timer_periodic_mode    (timer_periodic_mode),
        .timer_irq_enable       (timer_irq_enable),
        .timer_reload_value     (timer_reload_value),
        .timer_prescaler_divider(timer_prescaler_divider),
        .gpio_input_data        (gpio_input_data),
        .gpio_output_data       (gpio_output_data),
        .gpio_irq_status        (gpio_irq_status),
        .gpio_output_write_data (gpio_output_write_data),
        .gpio_output_write_en   (gpio_output_write_en),
        .gpio_irq_clear_data    (gpio_irq_clear_data),
        .gpio_irq_clear_en      (gpio_irq_clear_en),
        .timer_count            (timer_count),
        .timer_active           (timer_active),
        .timer_expiry_pending   (timer_expiry_pending),
        .timer_clear_expiry     (timer_clear_expiry),
        .timer_irq_level        (timer_irq_level),
        .gpio_irq_level         (gpio_irq_level)
    );

    gpio_block #(
        .WIDTH               (GPIO_WIDTH),
        .ENABLE_FALLING_EDGE (GPIO_ENABLE_FALLING_EDGE)
    ) u_gpio (
        .PCLK                (PCLK),
        .PRESETn             (PRESETn),
        .gpio_in             (gpio_in),
        .gpio_out            (gpio_out),
        .gpio_oe             (gpio_oe),
        .direction           (gpio_direction),
        .output_write_data   (gpio_output_write_data),
        .output_write_en     (gpio_output_write_en),
        .interrupt_clear     (gpio_irq_clear_data),
        .interrupt_clear_en  (gpio_irq_clear_en),
        .input_data          (gpio_input_data),
        .output_data         (gpio_output_data),
        .interrupt_status    (gpio_irq_status),
        .interrupt           (gpio_interrupt_unused)
    );

    timer #(
        .WIDTH(TIMER_WIDTH)
    ) u_timer (
        .PCLK                (PCLK),
        .PRESETn             (PRESETn),
        .timer_enable        (timer_enable),
        .prescaler_divider   (timer_prescaler_divider),
        .timer_reload_value  (timer_reload_value),
        .periodic_mode       (timer_periodic_mode),
        .clear_expiry_status (timer_clear_expiry),
        .timer_counter       (timer_count),
        .timer_active        (timer_active),
        .expiry_pulse        (timer_expiry_pulse),
        .expiry_pending      (timer_expiry_pending)
    );

    // Per-pin GPIO masking is applied before aggregation.
    assign timer_irq_level = timer_irq_enable && timer_expiry_pending;
    assign gpio_irq_level  = |(gpio_irq_status & gpio_irq_enable);
    assign irq_sources     = {gpio_irq_level, timer_irq_level};

    irq_aggregator #(
        .NUM_IRQS(2)
    ) u_irq_aggregator (
        .irq_sources(irq_sources),
        .irq_out    (IRQ)
    );

    initial begin
        if ((GPIO_WIDTH < 1) || (GPIO_WIDTH > 32))
            $error("GPIO_WIDTH must be in the range 1..32");
        if ((TIMER_WIDTH < 1) || (TIMER_WIDTH > 32))
            $error("TIMER_WIDTH must be in the range 1..32");
    end

endmodule
