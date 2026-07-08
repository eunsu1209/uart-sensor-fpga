`timescale 1ns / 1ps
module loopback_fifo_uart(
    input       clk,
    input       rst,
    input       rx,
    output      tx
);
    wire           b_tick;
    wire [7:0]    rx_data;
    wire          rx_done;

    wire [7:0] rx_pop_data;
    wire rx_empty;

    wire [7:0] tx_pop_data;
    wire tx_full;
    wire tx_empty;

    baud_tick_sampling_divide U_BAUD_TICK (
        .clk(clk),
        .rst(rst),
        .b_tick(b_tick)
    );

    uart_rx U_UART_RX (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .b_tick(b_tick),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

    fifo #(.DEPTH(8), .BIT_WIDTH(8)) U_FIFO_RX (
        .clk(clk),
        .rst(rst),
        .push(rx_done),
        .pop(~tx_full),
        .push_data(rx_data),
        .pop_data(rx_pop_data),
        .full(),
        .empty(rx_empty)
    );

    fifo #(.DEPTH(8), .BIT_WIDTH(8)) U_FIFO_TX (
        .clk(clk),
        .rst(rst),
        .push(~rx_empty),
        .pop(~tx_tx_busy),
        .push_data(rx_pop_data),
        .pop_data(tx_pop_data),
        .full(tx_full),
        .empty(tx_empty)
    );

    uart_tx U_UART_TX (
        .clk(clk),
        .rst(rst),
        .tx_start(~tx_empty),
        .b_tick(b_tick),
        .tx_data(tx_pop_data),
        .tx_busy(tx_tx_busy),
        .tx_done(),
        .uart_tx(tx)
    );

endmodule
