`timescale 1ns / 1ps

module uart_sys (
    input         clk,
    input         rst,
    input         i_uart_rx,
    output        o_uart_tx,
    input  [ 1:0] i_type,
    input  [31:0] i_data,
    input         i_send_start,
    output [ 7:0] opcode
);

    wire w_b_tick, w_rx_done;
    wire [7:0] w_rx_data;

    wire [7:0] w_tx_data;
    wire w_tx_start;
    wire tx_full, tx_empty, tx_tx_busy;
    wire [7:0] tx_pop_data;

    uart_rx U_UART_RX (
        .clk(clk),
        .reset(rst),
        .rx(i_uart_rx),
        .b_tick(w_b_tick),
        .rx_data(w_rx_data),
        .rx_done(w_rx_done)
    );

    ascii_decoder U_ASCII_DECODER (
        .clk(clk),
        .reset(rst),
        .i_rx_data(w_rx_data),
        .i_rx_done(w_rx_done),
        .opcode(opcode)
    );

    ascii_sender U_ASCII_SENDER (
        .clk(clk),
        .reset(rst),
        .i_data(i_data),
        .i_fifo(tx_full),
        .i_send_start(i_send_start),
        .i_type(i_type),
        .o_tx_data(w_tx_data),
        .o_tx_start(w_tx_start)
    );

    fifo #(
        .DEPTH(32),
        .BIT_WIDTH(8)
    ) U_FIFO_TX (
        .clk(clk),
        .rst(rst),
        .push(w_tx_start),
        .pop(~tx_tx_busy),
        .push_data(w_tx_data),
        .pop_data(tx_pop_data),
        .full(tx_full),
        .empty(tx_empty)
    );

    uart_tx U_UART_TX (
        .clk(clk),
        .reset(rst),
        .tx_start(~tx_empty),
        .b_tick(w_b_tick),
        .tx_data(tx_pop_data),
        .tx_busy(tx_tx_busy),
        .tx_done(),
        .uart_tx(o_uart_tx)
    );

    baud_tick U_BAUD_TICK (
        .clk(clk),
        .reset(rst),
        .b_tick(w_b_tick)
    );
endmodule

module uart_rx (
    input        clk,
    input        reset,
    input        rx,
    input        b_tick,
    output [7:0] rx_data,
    output       rx_done
);

    // State
    localparam IDLE = 2'd0, START = 2'd1;
    localparam DATA = 2'd2, STOP = 2'd3;

    reg [1:0] c_state, n_state;
    reg [4:0] b_tick_cnt_reg, next_b_tick_cnt;
    reg [2:0] bit_cnt_reg, next_bit_cnt;
    reg rx_done_reg, rx_done_next;
    reg [7:0] buf_reg, next_buf;

    assign rx_data = buf_reg;
    assign rx_done = rx_done_reg;

    // State, Counter REG
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state        <= 2'b00;
            b_tick_cnt_reg <= 5'b00000;
            bit_cnt_reg    <= 3'b000;
            rx_done_reg    <= 1'b0;
            buf_reg        <= 8'b0000_0000;
        end else begin
            c_state        <= n_state;
            b_tick_cnt_reg <= next_b_tick_cnt;
            bit_cnt_reg    <= next_bit_cnt;
            rx_done_reg    <= rx_done_next;
            buf_reg        <= next_buf;
        end
    end

    // next, output
    always @(*) begin
        n_state         = c_state;
        next_b_tick_cnt = b_tick_cnt_reg;
        next_bit_cnt    = bit_cnt_reg;
        rx_done_next    = rx_done_reg;
        next_buf        = buf_reg;
        case (c_state)
            IDLE: begin
                next_b_tick_cnt = 5'b00000;
                next_bit_cnt = 3'b000;
                rx_done_next = 1'b0;
                next_buf = 8'b0000_0000;

                if (b_tick & (rx == 0)) begin
                    n_state = START;
                end
            end
            START: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 7) begin
                        next_b_tick_cnt = 0;
                        //next_bit_cnt = bit_cnt_reg + 1;
                        n_state = DATA;
                    end else begin
                        next_b_tick_cnt = b_tick_cnt_reg + 1;
                    end
                end
            end
            DATA: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        next_b_tick_cnt = 0;
                        next_buf = {rx, buf_reg[7:1]};

                        if (bit_cnt_reg == 7) begin
                            n_state = STOP;
                        end else begin
                            next_bit_cnt = bit_cnt_reg + 1;
                        end
                    end else begin
                        next_b_tick_cnt = b_tick_cnt_reg + 1;
                    end
                end
            end
            STOP: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        next_b_tick_cnt = 0;
                        rx_done_next = 1'b1;
                        n_state = IDLE;
                    end else begin
                        next_b_tick_cnt = b_tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end

endmodule

module uart_tx (
    input        clk,
    input        reset,
    input        tx_start,
    input        b_tick,
    input  [7:0] tx_data,
    output       tx_busy,
    output       tx_done,
    output       uart_tx
);

    localparam IDLE = 2'd0, START = 2'd1;
    localparam DATA = 2'd2, STOP = 2'd3;

    //state reg
    reg [1:0] current_state, next_state;
    reg tx_reg, tx_next;  // for output SL
    reg [2:0] bit_cnt_reg, bit_cnt_next;
    //baud tick counter
    reg [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    // busy, done
    reg busy_reg, busy_next, done_reg, done_next;
    // data_in_buf
    reg [7:0] data_in_buf_reg, data_in_buf_next;

    assign uart_tx = tx_reg;
    assign tx_busy = busy_reg;
    assign tx_done = done_reg;

    //state register SL
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            current_state   <= IDLE;
            tx_reg          <= 1'b1;
            bit_cnt_reg     <= 1'b0;
            b_tick_cnt_reg  <= 4'h0;
            busy_reg        <= 1'b0;
            done_reg        <= 1'b0;
            data_in_buf_reg <= 8'h00;
        end else begin
            current_state   <= next_state;
            tx_reg          <= tx_next;
            bit_cnt_reg     <= bit_cnt_next;
            b_tick_cnt_reg  <= b_tick_cnt_next;
            busy_reg        <= busy_next;
            done_reg        <= done_next;
            data_in_buf_reg <= data_in_buf_next;
        end
    end

    // next CL
    always @(*) begin
        next_state       = current_state;
        tx_next          = tx_reg;
        bit_cnt_next     = bit_cnt_reg;
        b_tick_cnt_next  = b_tick_cnt_reg;
        busy_next        = busy_reg;
        done_next        = done_reg;
        data_in_buf_next = data_in_buf_reg;
        case (current_state)
            IDLE: begin
                tx_next         = 1'b1;
                bit_cnt_next    = 1'b0;
                b_tick_cnt_next = 4'h0;
                busy_next       = 1'b0;
                done_next       = 1'b0;
                if (tx_start) begin
                    next_state       = START;
                    busy_next        = 1'b1;
                    data_in_buf_next = tx_data;
                end
            end
            START: begin
                tx_next = 1'b0;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        next_state = DATA;
                        b_tick_cnt_next = 4'h0;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            DATA: begin
                tx_next = data_in_buf_reg[0];
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        if (bit_cnt_reg == 7) begin
                            b_tick_cnt_next = 4'h0;
                            next_state = STOP;
                        end else begin
                            b_tick_cnt_next = 4'h0;
                            bit_cnt_next = bit_cnt_reg + 1;
                            data_in_buf_next = {1'b0, data_in_buf_reg[7:1]};
                            next_state = DATA;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            STOP: begin
                tx_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        done_next  = 1'b1;
                        next_state = IDLE;
                        busy_next  = 1'b0;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end

endmodule
module baud_tick (
    input      clk,
    input      reset,
    output reg b_tick
);

    parameter BAUDRATE = 9600 * 16;
    parameter F_COUNT = 100_000_000 / BAUDRATE;

    reg [$clog2(F_COUNT)-1:0] counter_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            counter_reg <= 0;
            b_tick <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == F_COUNT - 1) begin
                counter_reg <= 0;
                b_tick <= 1'b1;
            end else begin
                b_tick <= 1'b0;
            end
        end
    end

endmodule

module ascii_decoder (
    input        clk,
    input        reset,
    input  [7:0] i_rx_data,
    input        i_rx_done,
    output [7:0] opcode
);

    localparam IDLE = 1'b0;
    localparam DECODE = 1'b1;

    reg current_state, next_state;
    reg [7:0] data, data_next;
    reg [7:0] opcode_reg, opcode_next;

    assign opcode = opcode_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= 1'b0;
            data <= 8'b0;
            opcode_reg <= 8'b0;
        end else begin
            current_state <= next_state;
            data <= data_next;
            opcode_reg <= opcode_next;
        end
    end

    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (i_rx_done) next_state = DECODE;
                else next_state = IDLE;
            end
            DECODE: begin
                if (i_rx_done) next_state = DECODE;
                else next_state = IDLE;
            end
        endcase
    end

    always @(*) begin
        data_next = (i_rx_done) ? i_rx_data : 0;
        if (current_state == IDLE) begin
            opcode_next = 8'b0000_0000;
        end else if (current_state == DECODE) begin
            case (data)
                8'h72:   opcode_next = 8'b0000_0001;
                8'h6C:   opcode_next = 8'b0000_0010;
                8'h75:   opcode_next = 8'b0000_0100;
                8'h64:   opcode_next = 8'b0000_1000;
                8'h30:   opcode_next = 8'b0001_0000;
                8'h31:   opcode_next = 8'b0010_0000;
                8'h32:   opcode_next = 8'b0100_0000;
                8'h73:   opcode_next = 8'b1000_0000;
                default: opcode_next = 8'b0000_0000;
            endcase
        end
    end

endmodule

module ascii_sender (
    input             clk,
    input             reset,
    input             i_fifo,
    input             i_send_start,
    input      [ 1:0] i_type,
    input      [31:0] i_data,
    output reg [ 7:0] o_tx_data,
    output reg        o_tx_start
);

    localparam  IDLE = 5'd0,
                T1 = 5'd1, T2 = 5'd2, T3 = 5'd3, T4 = 5'd4, 
                V1 = 5'd5, V2 = 5'd6, D1 = 5'd7, 
                V3 = 5'd8, V4 = 5'd9, D2 = 5'd10,
                V5 = 5'd11, V6 = 5'd12, D3 = 5'd13,
                V7 = 5'd14, V8 = 5'd15,
                CR = 5'd16, LF = 5'd17;

    reg [4:0] current_state, next_state;
    reg [31:0] data_buf;
    reg [1:0] type_buf;

    reg i_send_start_prev;  // no this? loop infinite

    wire [3:0] val[0:7];
    assign val[7] = data_buf[31:28];
    assign val[6] = data_buf[27:24];
    assign val[5] = data_buf[23:20];
    assign val[4] = data_buf[19:16];
    assign val[3] = data_buf[15:12];
    assign val[2] = data_buf[11:8];
    assign val[1] = data_buf[7:4];
    assign val[0] = data_buf[3:0];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            data_buf <= 32'd0;
            type_buf <= 2'd0;
            i_send_start_prev <= 1'b0;
        end else begin
            current_state <= next_state;
            i_send_start_prev <= i_send_start;

            if (current_state == IDLE && i_send_start && !i_send_start_prev && !i_fifo) begin
                type_buf <= i_type;


                data_buf[31:28] <= i_data[31:24] / 10;
                data_buf[27:24] <= i_data[31:24] % 10;

                data_buf[23:20] <= i_data[23:16] / 10;
                data_buf[19:16] <= i_data[23:16] % 10;

                data_buf[15:12] <= i_data[15:8] / 10;
                data_buf[11:8] <= i_data[15:8] % 10;

                data_buf[7:4] <= i_data[7:0] / 10;
                data_buf[3:0] <= i_data[7:0] % 10;
            end
        end
    end
    always @(*) begin
        next_state = current_state;
        o_tx_data  = 8'd0;
        o_tx_start = 1'b0;

        case (current_state)
            IDLE:
            if (i_send_start && !i_send_start_prev && !i_fifo) next_state = T1;

            T1:
            if (!i_fifo) begin
                o_tx_start = 1'b1;
                case (type_buf)
                    2'd0: o_tx_data = "S";
                    2'd1: o_tx_data = "W";
                    2'd2: o_tx_data = "D";
                    2'd3: o_tx_data = "H";
                endcase
                next_state = T2;
            end

            T2:
            if (!i_fifo) begin
                o_tx_start = 1'b1;
                case (type_buf)
                    2'd0: o_tx_data = "W";
                    2'd1: o_tx_data = " ";
                    2'd2: o_tx_data = "I";
                    2'd3: o_tx_data = "/";
                endcase
                next_state = T3;
            end

            T3:
            if (!i_fifo) begin
                o_tx_start = 1'b1;
                case (type_buf)
                    2'd0: o_tx_data = " ";
                    2'd1: o_tx_data = " ";
                    2'd2: o_tx_data = "S";
                    2'd3: o_tx_data = "T";
                endcase
                next_state = T4;
            end

            T4:
            if (!i_fifo) begin
                o_tx_start = 1'b1;
                o_tx_data  = ":";
                next_state = V1;
            end

            V1:
            if (!i_fifo) begin
                o_tx_data  = val[7] + 8'h30;
                o_tx_start = 1'b1;
                next_state = V2;
            end

            V2:
            if (!i_fifo) begin
                o_tx_data  = val[6] + 8'h30;
                o_tx_start = 1'b1;
                next_state = D1;
            end

            D1:
            if (!i_fifo) begin
                o_tx_start = 1'b1;
                o_tx_data = (type_buf == 3) ? 8'h2E : (type_buf == 2) ? 8'h20 : 8'h3A;
                next_state = V3;
            end

            V3:
            if (!i_fifo) begin
                o_tx_data  = val[5] + 8'h30;
                o_tx_start = 1'b1;
                next_state = V4;
            end

            V4:
            if (!i_fifo) begin
                o_tx_data  = val[4] + 8'h30;
                o_tx_start = 1'b1;
                next_state = D2;
            end

            D2:
            if (!i_fifo) begin
                o_tx_start = 1'b1;
                o_tx_data = (type_buf == 3) ? 8'h2F : (type_buf == 2) ? 8'h20 : 8'h3A;
                next_state = V5;
            end

            V5:
            if (!i_fifo) begin
                o_tx_data  = val[3] + 8'h30;
                o_tx_start = 1'b1;
                next_state = V6;
            end

            V6:
            if (!i_fifo) begin
                o_tx_data  = val[2] + 8'h30;
                o_tx_start = 1'b1;
                next_state = D3;
            end

            D3:
            if (!i_fifo) begin
                o_tx_start = 1'b1;
                o_tx_data = (type_buf == 3) ? 8'h2E : (type_buf == 2) ? 8'h20 : 8'h3A;
                next_state = V7;
            end

            V7:
            if (!i_fifo) begin
                o_tx_data  = val[1] + 8'h30;
                o_tx_start = 1'b1;
                next_state = V8;
            end

            V8:
            if (!i_fifo) begin
                o_tx_data  = val[0] + 8'h30;
                o_tx_start = 1'b1;
                next_state = CR;
            end

            CR:
            if (!i_fifo) begin
                o_tx_data  = 8'h0D;
                o_tx_start = 1'b1;
                next_state = LF;
            end

            LF:
            if (!i_fifo) begin
                o_tx_data  = 8'h0A;
                o_tx_start = 1'b1;
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end
endmodule
