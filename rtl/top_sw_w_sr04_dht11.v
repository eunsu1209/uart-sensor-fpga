`timescale 1ns / 1ps
module top_sw_w_sr04_dht11 (
    input clk,
    input rst,

    // UART TX/RX
    input  i_uart_rx,
    output o_uart_tx,

    // BOARD INPUTS
    // Switches: [3]Data Print Mode / [2]Minor System Mode / [1]Major System Mode / [0]Input Mode
    input [3:0] i_board_sw,
    // Buttons
    input i_btn_up,
    input i_btn_down,
    input i_btn_left,
    input i_btn_right,

    // FND DISPLAY
    output [3:0] o_fnd_digit,
    output [7:0] o_fnd_data,

    // Sensor's I/O
    // SR04
    input  i_sr04_echo,
    output o_sr04_trigger,
    // DHT11
    inout  io_dht11
);
    // Wires
    // BTN_DEBOUNCE
    wire w_btn_deb_up, w_btn_deb_down, w_btn_deb_left, w_btn_deb_right;
    // Switches Names
    wire w_sw_inmode, w_sw_sysmode_maj, w_sw_sysmode_mir, w_sw_position_data;
    assign w_sw_inmode = i_board_sw[0];  // Input Mode: (UP)UART (DOWN)SW/BTN
    assign w_sw_sysmode_maj = i_board_sw[1]; // Major System Mode: (UP)SENSORS (DOWN)CLOCKS
    assign w_sw_sysmode_mir = i_board_sw[2]; // Minor System Mode: [SENSORS] (UP)DHT11 (DOWN)SR04 [CLOCKS] (UP)Watch (DOWN)Stopwatch
    assign w_sw_position_data = i_board_sw[3]; // Data Print Mode: (UP)UPPER (DOWN)UNDER
    // UART ASCII_DECODER
    wire [7:0] w_ascdec_opcode;
    // CONTROL_UNIT
    wire w_swd_mode, w_swd_clear, w_swd_runstop;  // STOPWATCH

    wire w_wd_modifymode, w_wd_up, w_wd_down;  // WATCH
    wire [3:0] w_wd_sel_timeslot;

    wire w_usd_start, w_htd_start;  // SENSORS CONTROL

    // DATAPATHS DATA
    wire [31:0] w_swd_data, w_wd_data, w_usd_data, w_htd_data;
    // DATAPATHS MUX
    wire [31:0] w_dpm_data;
    wire [1:0] w_dpm_sel;
    // FND
    wire w_fnd_position;
    // UART SYSTEM
    wire w_uart_uartsnd;

    // BTN_DEBOUNCES
    btn_debounce U_BTN_DEB_UP (  // UP
        .clk  (clk),
        .reset(rst),
        .i_btn(i_btn_up),
        .o_btn(w_btn_deb_up)
    );
    btn_debounce U_BTN_DEB_DOWN (  // DOWN
        .clk  (clk),
        .reset(rst),
        .i_btn(i_btn_down),
        .o_btn(w_btn_deb_down)
    );
    btn_debounce U_BTN_DEB_LEFT (  // LEFT
        .clk  (clk),
        .reset(rst),
        .i_btn(i_btn_left),
        .o_btn(w_btn_deb_left)
    );
    btn_debounce U_BTN_DEB_RIGHT (  // RIGHT
        .clk  (clk),
        .reset(rst),
        .i_btn(i_btn_right),
        .o_btn(w_btn_deb_right)
    );

    // CONTROL_UNIT
    control_unit U_CTRL_UNIT (
        .clk(clk),
        .rst(rst),

        // Inputs
        // Board Switches (BSW)
        .i_bsw_inmode    (w_sw_inmode),
        .i_bsw_majsysmode(w_sw_sysmode_maj),
        .i_bsw_mirsysmode(w_sw_sysmode_mir),
        .i_bsw_positiondp(w_sw_position_data),
        // Board Button (BTN)
        .i_btn_up        (w_btn_deb_up),
        .i_btn_down      (w_btn_deb_down),
        .i_btn_left      (w_btn_deb_left),
        .i_btn_right     (w_btn_deb_right),
        // UART ascii_decoder (ASCDEC) - s_2_1_0_d_u_l_r
        .i_ascdec_opcode (w_ascdec_opcode),

        // Outputs
        // Stopwatch Datapath (SWD)
        .o_swd_mode       (w_swd_mode),
        .o_swd_clear      (w_swd_clear),
        .o_swd_runstop    (w_swd_runstop),
        // Watch Datapath (WD)
        .o_wd_modifymode  (w_wd_modifymode),
        .o_wd_sel_timeslot(w_wd_sel_timeslot),
        .o_wd_up          (w_wd_up),
        .o_wd_down        (w_wd_down),
        // Ultrasonic Datapath (USD)
        .o_usd_start      (w_usd_start),
        // Humidity Temperature Datapath (HTD)
        .o_htd_start      (w_htd_start),
        // UART ascii_sender (ASCSND) 
        .o_ascsnd_sendreq (w_uart_uartsnd),
        // DATAPATHS MUX (DPM) - 2bit
        .o_dpm_select     (w_dpm_sel),
        // FND DISPLAY POSITION 
        .o_fnd_position   (w_fnd_position)
    );

    // DATAPATHS

    wire [6:0] w_swd_msec;
    wire [5:0] w_swd_sec, w_swd_min;
    wire [4:0] w_swd_hour;
    stopwatch_datapath U_STOPWATCH_DATAPATH (
        .clk     (clk),
        .reset   (rst),
        .mode    (w_swd_mode),
        .clear   (w_swd_clear),
        .run_stop(w_swd_runstop),
        .msec    (w_swd_msec),
        .sec     (w_swd_sec),
        .min     (w_swd_min),
        .hour    (w_swd_hour)
    );
    assign w_swd_data = {
        3'b0, w_swd_hour, 2'b0, w_swd_min, 2'b0, w_swd_sec, 1'b0, w_swd_msec
    };

    wire [6:0] w_wd_msec;
    wire [5:0] w_wd_sec, w_wd_min;
    wire [4:0] w_wd_hour;
    watch_datapath U_WATCH_DATAPATH (
        .clk         (clk),
        .reset       (rst),
        .modify_mode (w_wd_modifymode),
        .sel_timeslot(w_wd_sel_timeslot),
        .up          (w_wd_up),
        .down        (w_wd_down),
        .msec        (w_wd_msec),
        .sec         (w_wd_sec),
        .min         (w_wd_min),
        .hour        (w_wd_hour)
    );
    assign w_wd_data = {
        3'b0, w_wd_hour, 2'b0, w_wd_min, 2'b0, w_wd_sec, 1'b0, w_wd_msec
    };

    ultrasonic_datapath U_ULTRASONIC_DATAPATH (
        .clk                  (clk),
        .rst                  (rst),
        .i_echo               (i_sr04_echo),
        .i_control_unit_start (w_usd_start),
        .o_trig               (o_sr04_trigger),
        .o_fnd_ultrasonic_data(w_usd_data)
    );

    humi_temp_datapath U_HUMI_TEMP_DATAPATH (
        .clk          (clk),
        .rst          (rst),
        .i_ctrl_start (w_htd_start),
        .o_data       (w_htd_data),
        .o_dht11_done (),
        .o_dht11_valid(),
        .o_debug      (),
        .o_checksum   (),
        .io_dht11     (io_dht11)
    );

    // DATAPATHS MUX
    mux4_32bit U_DP_MUX (
        .i_ctrl_sel(w_dpm_sel),
        .i_dp_data0(w_swd_data),
        .i_dp_data1(w_wd_data),
        .i_dp_data2(w_usd_data),
        .i_dp_data3(w_htd_data),
        .o_seldata (w_dpm_data)
    );

    // FND CONTROLLER
    fnd_controller U_FND_CTRL (
        .clk        (clk),
        .reset      (rst),
        .sel_display(w_fnd_position),
        .fnd_in_data(w_dpm_data),
        .fnd_digit  (o_fnd_digit),
        .fnd_data   (o_fnd_data)
    );

    // UART SYSTEM
    uart_sys U_UART_SYS (
        .clk(clk),
        .rst(rst),

        .i_uart_rx(i_uart_rx),
        .opcode   (w_ascdec_opcode),

        .o_uart_tx   (o_uart_tx),
        .i_type      (w_dpm_sel),
        .i_data      (w_dpm_data),
        .i_send_start(w_uart_uartsnd)
    );

endmodule

module mux4_32bit (
    input  [ 1:0] i_ctrl_sel,
    input  [31:0] i_dp_data0,
    input  [31:0] i_dp_data1,
    input  [31:0] i_dp_data2,
    input  [31:0] i_dp_data3,
    output [31:0] o_seldata
);

    assign o_seldata =  (i_ctrl_sel == 2'd0)? i_dp_data0 :
                        (i_ctrl_sel == 2'd1)? i_dp_data1 :
                        (i_ctrl_sel == 2'd2)? i_dp_data2 :
                        (i_ctrl_sel == 2'd3)? i_dp_data3 : 32'b0;
endmodule
