`timescale 1ns / 1ps

module tb_uart_sys ();

    parameter BAUD_RATE = 9600;
    parameter BIT_PERIOD = 1000000000 / BAUD_RATE;

    reg         clk;
    reg         rst;
    reg         i_uart_rx;
    wire        o_uart_tx;
    reg  [ 1:0] i_type;
    reg  [31:0] i_data;
    reg         i_send_start;
    wire [ 7:0] opcode;

    uart_sys dut (
        .clk(clk),
        .rst(rst),
        .i_uart_rx(i_uart_rx),
        .o_uart_tx(o_uart_tx),
        .i_type(i_type),
        .i_data(i_data),
        .i_send_start(i_send_start),
        .opcode(opcode)
    );

    always #5 clk = ~clk;

    task uart_send_to_rx(input [7:0] data);
        integer i;
        begin
            i_uart_rx = 1'b0;
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                i_uart_rx = data[i];
                #(BIT_PERIOD);
            end
            i_uart_rx = 1'b1;
            #(BIT_PERIOD);
            #(BIT_PERIOD);
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        i_uart_rx = 1'b1;
        i_type = 2'b00;
        i_data = 32'h0;
        i_send_start = 0;

        repeat (5) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        uart_send_to_rx(8'h72);
        #(BIT_PERIOD);

        uart_send_to_rx(8'h75);
        #(BIT_PERIOD);

        $stop;
    end

endmodule




/*
        // --- TEST CASE 2: TX Sending (Formatting Data) ---
        // data 0x12345678 (각 바이트를 10진수로 변환하여 송신)
        // i_ctrl_type = 0 이면 "SW :12:34:56:78\r\n" 형태 예상
        i_data = 32'h0C22384E;  // 12, 34, 56, 78 (Hex-to-Dec 가공 확인용)
        i_type = 2'd0;  // "SW " 타입

        @(posedge clk);
        #1 i_send_start = 1;  // Send Start!
        @(posedge clk);
        #1 i_send_start = 0;

        // TX는 문자가 많으므로 (약 15자 이상) 충분히 기다려야 합니다.
        // 17자 * 10비트(Start+8Data+Stop) * BIT_PERIOD
        #(BIT_PERIOD * 200);

*/

/*        uart_send_to_rx(8'h72);
        #(BIT_PERIOD);

        uart_send_to_rx(8'h75);
        #(BIT_PERIOD);
*/