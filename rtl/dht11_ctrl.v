`timescale 1ns / 1ps

module humi_temp_datapath (
    input clk,
    input rst,
    input i_ctrl_start,
    output [31:0] o_data,
    output o_dht11_done,
    output o_dht11_valid,
    output [2:0] o_debug,
    output [7:0] o_checksum,
    inout io_dht11
);

    dht11_ctrl (
        .clk(clk),
        .rst(rst),
        .start(i_ctrl_start),
        .humidity(o_data[15:0]),
        .temperature(o_data[31:16]),
        .checksum_out(o_checksum), // N/C
        .dht11_done(o_dht11_done), // N/C ?
        .dht11_valid(o_dht11_valid), // N/C ?
        .dht11_io(io_dht11),
        .debug(o_debug) // N/C
    );

endmodule

module dht11_top_test (
    input clk,
    input rst,
    input start,
    //input tx_start_btn,
    //input [2:0] selector,
    //output uart_tx,
    output [3:0] debug_state,
    inout dhtio
    //output  [3:0] fnd_digit,
    //output  [7:0] fnd_data
);
    wire [7:0] dout_sel;

    ila_0 DEBUG_ILA0(
        .clk(clk),
        .probe0(dhtio),  // 1bit
        //.probe0(1'b1),  // 1bit
        .probe1(debug_state[2:0])  // 3bit
    );

    dht11_ctrl U_DHT11_CTRL (
        .clk(clk),
        .rst(rst),
        .start(start),
        .dht11_io(dhtio),
        .debug(debug_state)
    );

endmodule

module dht11_top (
    input clk,
    input rst,
    input start_btn,
    input tx_start_btn,
    input [2:0] selector,
    output uart_tx,
    output [3:0] debug_state,
    inout dht11_io,
    output  [3:0] fnd_digit,
    output  [7:0] fnd_data
);
    wire          start;
    wire          uart_start;
    wire [15:0]   humidity;
    wire [15:0]   temperature;
    wire [7:0]    checksum;
    wire          dht11_done;
    wire          dht11_valid;
    wire          w_b_tick_9600_16sam;

    wire [7:0] dout_sel;

    assign dout_sel = (selector[2] == 1'b1)? checksum :
                      (selector == 3'b000)? temperature[7:0] :
                      (selector == 3'b001)? temperature[15:8] :
                      (selector == 3'b010)? humidity[7:0] :
                      (selector == 3'b011)? humidity[15:8] : 8'b0;

    btn_debounce U_BTN_DEBOUNCE_START(
        .clk(clk),
        .reset(rst),
        .i_btn(start_btn),
        .o_btn(start)
    );

    btn_debounce U_BTN_DEBOUNCE_UART_RUN(
        .clk(clk),
        .reset(rst),
        .i_btn(tx_start_btn),
        .o_btn(uart_start)
    );

    baud_tick_sampling_divide U_BAUD_TICK (
        .clk(clk),
        .rst(rst),
        .b_tick(w_b_tick_9600_16sam)
    );
    
    uart_tx U_UART_TX (
        .clk(clk),
        .rst(rst),
        .tx_start(uart_start),
        .b_tick(w_b_tick_9600_16sam),
        .tx_data(dout_sel),
        .uart_tx(uart_tx),
        .tx_busy(w_tx_busy),
        .tx_done(w_tx_done)
    );

    dht11_ctrl U_DHT11_CTRL (
        .clk(clk),
        .rst(rst),
        .start(start),
        .humidity(humidity),
        .temperature(temperature),
        .checksum_out(checksum),
        .dht11_done(dht11_done),
        .dht11_valid(dht11_valid),
        .dht11_io(dht11_io),
        .debug(debug_state)
    );

    fnd_controller U_FND_CTRL (
        .clk(clk),
        .reset(rst),
        .sel_display(selector[1]),
        .fnd_in_data({humidity, temperature}),
        .fnd_digit(fnd_digit),
        .fnd_data(fnd_data)
    );

endmodule

module dht11_ctrl (
    input           clk,
    input           rst,
    input           start,
    output [15:0]   humidity,
    output [15:0]   temperature,
    output [7:0]    checksum_out,
    output reg      dht11_done,
    output reg      dht11_valid,
    inout           dht11_io,
    output [3:0]    debug
);
    wire w_tick_10us;

    // Constant
    parameter CLOCK_TIME_NS = 10;
    parameter REQUEST_ZERO_TIMES = 19_000_000;
    parameter REQUEST_ZERO_TICKS = 1900;

    parameter TRANSATION_BITS = 40;
    parameter WAIT_TICKS = 3;
    parameter BOUNDARY_HIGH_TICKS = 5;
    parameter DONE_TICKS = 5;

    tick_gen #(.CLOCK_CYCLE_1SEC(100_000_000), .CLOCK_NS(CLOCK_TIME_NS), .TARGET_TIME(10_000)) 
        U_TICK_GEN_10US (
            .clk(clk),
            .rst(rst),
            .b_tick(w_tick_10us)
        );

    // STATE
    parameter IDLE = 0, START = 1, WAIT = 2, SYNC_0 = 3, SYNC_1 = 4, READY_BIT = 5, DATA_GET = 6, STOP = 7;

    reg [2:0] c_state, n_state;

    reg [1:0] synchronizer, synchronizer_next;

    reg [$clog2(REQUEST_ZERO_TICKS)-1:0] tick_cnt_reg, tick_cnt_next; 
    reg [$clog2(TRANSATION_BITS)-1:0] bit_cnt_reg, bit_cnt_next; 
    reg dhtio_reg, dhtio_next;
    reg io_sel_reg, io_sel_next;

    reg [TRANSATION_BITS-1:0] buf_bits_reg, buf_bits_next;

    reg [15:0] humidity_reg, humidity_next;
    reg [15:0] temperature_reg, temperature_next;
    reg [7:0] checksum_reg, checksum_next;

    wire [7:0] checksum;
    
    assign checksum = buf_bits_reg[15:8]+buf_bits_reg[23:16]+buf_bits_reg[31:24]+buf_bits_reg[39:32];

    assign humidity = humidity_reg;
    assign temperature = temperature_reg;
    assign checksum_out = checksum_reg;

    // DEBUG
    assign debug = {dht11_valid, c_state};

    // Registers
    always @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state <= 3'b000;

            synchronizer <= 0;

            tick_cnt_reg <= 0;
            bit_cnt_reg <= 0;
            dhtio_reg <= 1'b1;
            io_sel_reg <= 1'b1;

            buf_bits_reg <= 0;

            humidity_reg <= 0;
            temperature_reg <= 0;
            checksum_reg <= 0;
        end
        else begin
            c_state <= n_state;

            synchronizer <= synchronizer_next;

            tick_cnt_reg <= tick_cnt_next; 
            bit_cnt_reg <= bit_cnt_next;
            dhtio_reg <= dhtio_next;
            io_sel_reg <= io_sel_next;

            buf_bits_reg <= buf_bits_next;

            humidity_reg <= humidity_next;
            temperature_reg <= temperature_next;
            checksum_reg <= checksum_next;
        end
    end

    assign dht11_io = (io_sel_reg) ? dhtio_reg : 1'bz;

    // next, output
    always @(*) begin
        n_state = c_state;
        dhtio_next = dhtio_reg;
        tick_cnt_next = tick_cnt_reg;
        bit_cnt_next = bit_cnt_reg;
        io_sel_next = io_sel_reg;

        dht11_done = 1'b0;
        dht11_valid = 1'b0;

        buf_bits_next = buf_bits_reg;

        humidity_next = humidity_reg;
        temperature_next = temperature_reg;
        checksum_next = checksum_reg;

        synchronizer_next = {dht11_io, synchronizer[1]};

        case(c_state)
            IDLE: begin
                io_sel_next = 1'b1;
                tick_cnt_next = 0;
                bit_cnt_next = 0;
                buf_bits_next = 0;

                if (start) begin n_state = START; end
            end
            START: begin
                dhtio_next = 1'b0;
                if (w_tick_10us) begin
                    tick_cnt_next = tick_cnt_reg + 1;
                    if (tick_cnt_reg == (REQUEST_ZERO_TICKS-1)) begin
                        tick_cnt_next = 0;
                        n_state = WAIT;
                    end
                end
            end
            WAIT: begin
                dhtio_next = 1'b1;
                if (w_tick_10us) begin
                    tick_cnt_next = tick_cnt_reg + 1;
                    if (tick_cnt_reg == (WAIT_TICKS-1)) begin
                        tick_cnt_next = 0;
                        // for output to high-z
                        io_sel_next = 1'b0;
                        n_state = SYNC_0;
                    end
                end
            end
            SYNC_0: begin
                if (w_tick_10us) begin // 틱에서 확인해서 접근 (metastable 줄이기)
                    if (synchronizer[0] == 1'b1) begin n_state = SYNC_1; end
                end
            end
            SYNC_1: begin
                if (w_tick_10us) begin
                    if (synchronizer[0] == 1'b0) begin n_state = READY_BIT; end
                end
            end
            READY_BIT: begin
                if (w_tick_10us) begin
                    if (synchronizer[0] == 1'b1) begin n_state = DATA_GET; end
                end
            end
            DATA_GET: begin
                if (w_tick_10us) begin
                    tick_cnt_next = tick_cnt_reg + 1;

                    if (synchronizer[0] == 1'b0) begin
                        tick_cnt_next = 0;
                        bit_cnt_next = bit_cnt_reg + 1;

                        buf_bits_next = 
                            { buf_bits_reg[TRANSATION_BITS-2:0], ( (tick_cnt_reg >= BOUNDARY_HIGH_TICKS)? 1'b1 : 1'b0 ) };

                        if (bit_cnt_reg == (TRANSATION_BITS-1)) begin
                            n_state = STOP;
                        end
                        else begin
                            n_state = READY_BIT;
                        end
                    end
                end
            end
            STOP: begin
                humidity_next = buf_bits_reg[39:24];
                temperature_next = buf_bits_reg[23:8];
                checksum_next = buf_bits_reg[7:0];

                if (w_tick_10us) begin
                    tick_cnt_next = tick_cnt_reg + 1;
                    if (tick_cnt_reg == (DONE_TICKS-1)) begin
                        io_sel_next = 1'b1;
                        dhtio_next = 1'b1;
                        n_state = IDLE;

                        dht11_done = 1'b1;

                        if ( checksum == checksum_reg ) begin
                            dht11_valid = 1'b1;
                        end
                        else begin dht11_valid = 1'b0; end
                    end
                end
            end
        endcase
    end

endmodule
