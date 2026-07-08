`timescale 1ns / 1ps

module control_unit (
        input clk,
        input rst,
        
        // Inputs
            // Board Switches (BSW)
        input i_bsw_inmode,
        input i_bsw_majsysmode,
        input i_bsw_mirsysmode,
        input i_bsw_positiondp,
            // Board Button (BTN)
        input i_btn_up,
        input i_btn_down,
        input i_btn_left,
        input i_btn_right,
            // UART ascii_decoder (ASCDEC) - s_2_1_0_d_u_l_r
        input [7:0] i_ascdec_opcode,

        // Outputs
            // Stopwatch Datapath (SWD)
        output reg o_swd_mode,
        output reg o_swd_clear,
        output reg o_swd_runstop,
            // Watch Datapath (WD)
        output reg o_wd_modifymode,
        output reg [3:0] o_wd_sel_timeslot,
        output reg o_wd_up,
        output reg o_wd_down,
            // Ultrasonic Datapath (USD)
        output reg o_usd_start,
            // Humidity Temperature Datapath (HTD)
        output reg o_htd_start,
            // UART ascii_sender (ASCSND) 
        output reg o_ascsnd_sendreq,
            // DATAPATHS MUX (DPM) - 2bit
        output reg [1:0] o_dpm_select,
            // FND DISPLAY POSITION 
        output reg o_fnd_position
);
    // System Mode State
    localparam  SYS_SW = 3'd0, SYS_W = 3'd1, SYS_W_MODIFY = 3'd5, 
                SYS_ULTRASONIC = 3'd2, SYS_HUMI_TEMP = 3'd3;
    reg [2:0] sys_state, sys_state_next;

    // Stopwatch State
    localparam  SWD_STOP_STRAGHT = 3'd0, SWD_RUN = 3'd1, 
                SWD_STOP_BACK = 3'd2, SWD_BACK = 3'd3, SWD_CLEAR = 3'd4;
    reg [2:0] swd_state, swd_state_next;

    // Position Register
    reg disp_position, disp_position_next;
    reg sel_position, sel_position_next;

    // Registers
    always @(posedge clk, posedge rst) begin
        if (rst) begin
            sys_state <= SYS_SW;
            swd_state <= SWD_STOP_STRAGHT;

            disp_position <= 0;
            sel_position <= 0;
        end
        else begin
            sys_state <= sys_state_next;
            swd_state <= swd_state_next;
            
            disp_position <= disp_position_next;
            sel_position <= sel_position_next;
        end
    end

    // System Mode State - NEXT
    always @(*) begin
        sys_state_next = sys_state;
        
        disp_position_next = disp_position;
        sel_position_next = sel_position;

        if (i_bsw_inmode) begin // UART MODE
            if (i_ascdec_opcode[4] | i_ascdec_opcode[5]) begin
                    // OFF Time Change Mode
                sys_state_next[2] = 1'b0; 
                    // Change Major System Mode
                sys_state_next[1] = (i_ascdec_opcode[5]) ? ~sys_state[1] : sys_state[1];
                    // Change Minor System Mode
                sys_state_next[0] = (i_ascdec_opcode[4]) ? ~sys_state[0] : sys_state[0];             
            end

            disp_position_next = (i_ascdec_opcode[6])? ~disp_position : disp_position; // UPPER-UNDER FND DISPLAY
            if (sys_state == SYS_W_MODIFY) sel_position_next = (i_ascdec_opcode[0])? ~sel_position : sel_position;
        end
        else begin  // SW/BTN MODE
            case({i_bsw_majsysmode, i_bsw_mirsysmode})
                2'b00: sys_state_next = SYS_SW;
                2'b01: begin
                    if (sys_state == SYS_W) begin
                        sys_state_next = (i_btn_left)? SYS_W_MODIFY : SYS_W;
                    end
                    else if (sys_state == SYS_W_MODIFY) begin
                        sys_state_next = (i_btn_left)? SYS_W : SYS_W_MODIFY;
                    end
                    else sys_state_next = SYS_W;
                end
                2'b10: sys_state_next = SYS_ULTRASONIC;
                2'b11: sys_state_next = SYS_HUMI_TEMP;
            endcase

            disp_position_next = i_bsw_positiondp; // UPPER-UNDER FND DISPLAY
            if (sys_state == SYS_W_MODIFY) sel_position_next = (i_btn_right)? ~sel_position : sel_position;
        end
    end
    
    // System Mode State - OUTPUT
    always @(*) begin
        o_wd_modifymode = 0;
        o_wd_sel_timeslot = 0;
        o_wd_up = 0; o_wd_down = 0;
        o_usd_start = 0; o_htd_start = 0;

        o_dpm_select = 2'b00;
        o_fnd_position = disp_position;

        o_ascsnd_sendreq = (i_bsw_inmode)? i_ascdec_opcode[7] : 0;

        case(sys_state)
            SYS_SW: begin
                o_dpm_select = 2'b00;
            end
            SYS_W: begin
                o_dpm_select = 2'b01;
            end
            SYS_W_MODIFY: begin
                o_dpm_select = 2'b01;
                o_wd_modifymode = 1;
                o_wd_up = i_btn_up; o_wd_down = i_btn_down;

                case({disp_position, sel_position})
                    2'b00: o_wd_sel_timeslot = 4'b0001;
                    2'b01: o_wd_sel_timeslot = 4'b0010;
                    2'b10: o_wd_sel_timeslot = 4'b0100;
                    2'b11: o_wd_sel_timeslot = 4'b1000;
                endcase
            end
            SYS_ULTRASONIC: begin
                o_dpm_select = 2'b10;
                o_usd_start = (i_bsw_inmode)? i_ascdec_opcode[0] : i_btn_right;
                o_ascsnd_sendreq = (i_bsw_inmode)? i_ascdec_opcode[7] : i_btn_left;
            end
            SYS_HUMI_TEMP: begin
                o_dpm_select = 2'b11;
                o_htd_start = (i_bsw_inmode)? i_ascdec_opcode[0] : i_btn_right;
                o_ascsnd_sendreq = (i_bsw_inmode)? i_ascdec_opcode[7] : i_btn_left;
            end
        endcase
    end

    // Stopwatch Mode State - NEXT
    always @(*) begin
        swd_state_next = swd_state;

        if (sys_state == SYS_SW) begin
            if (i_bsw_inmode) begin
                case(swd_state)
                    SWD_STOP_STRAGHT: begin
                        if (i_ascdec_opcode[3]) swd_state_next = SWD_STOP_BACK;
                        else if (i_ascdec_opcode[1]) swd_state_next = SWD_CLEAR;
                        else if (i_ascdec_opcode[0]) swd_state_next = SWD_RUN;
                    end
                    SWD_RUN: begin
                        if (i_ascdec_opcode[0]) swd_state_next = SWD_STOP_STRAGHT;
                    end
                    SWD_STOP_BACK: begin
                        if (i_ascdec_opcode[2]) swd_state_next = SWD_STOP_STRAGHT;
                        else if (i_ascdec_opcode[1]) swd_state_next = SWD_CLEAR;
                        else if (i_ascdec_opcode[0]) swd_state_next = SWD_BACK;
                    end
                    SWD_BACK: begin
                        if (i_ascdec_opcode[0]) swd_state_next = SWD_STOP_BACK;
                    end
                    SWD_CLEAR: begin swd_state_next = SWD_STOP_STRAGHT; end
                endcase
            end
            else begin
                case(swd_state)
                    SWD_STOP_STRAGHT: begin
                        if (i_btn_down) swd_state_next = SWD_STOP_BACK;
                        else if (i_btn_left) swd_state_next = SWD_CLEAR;
                        else if (i_btn_right) swd_state_next = SWD_RUN;
                    end
                    SWD_RUN: begin
                        if (i_btn_right) swd_state_next = SWD_STOP_STRAGHT;
                    end
                    SWD_STOP_BACK: begin
                        if (i_btn_up) swd_state_next = SWD_STOP_STRAGHT;
                        else if (i_btn_left) swd_state_next = SWD_CLEAR;
                        else if (i_btn_right) swd_state_next = SWD_BACK;
                    end
                    SWD_BACK: begin
                        if (i_btn_right) swd_state_next = SWD_STOP_BACK;
                    end
                    SWD_CLEAR: begin swd_state_next = SWD_STOP_STRAGHT; end
                endcase
            end
        end
    end

    // Stopwatch Mode State - OUTPUT
    always @(*) begin
        o_swd_mode = 0; o_swd_clear = 0; o_swd_runstop = 0;
        case(swd_state)
            SWD_STOP_STRAGHT: begin
                o_swd_mode = 0; o_swd_clear = 0; o_swd_runstop = 0;
            end
            SWD_RUN: begin
                o_swd_mode = 0; o_swd_clear = 0; o_swd_runstop = 1;
            end
            SWD_STOP_BACK: begin
                o_swd_mode = 1; o_swd_clear = 0; o_swd_runstop = 0;
            end
            SWD_BACK: begin
                o_swd_mode = 1; o_swd_clear = 0; o_swd_runstop = 1;
            end
            SWD_CLEAR: begin 
                o_swd_mode = 0; o_swd_clear = 1; o_swd_runstop = 0;
            end
        endcase
    end

endmodule

module control_unit_v1(
    input           clk,
    input           reset,
    input [2:0]     sw_under,
    input [1:0]     sw_upper,
    input           btn_l,
    input           btn_r,
    input           btn_u,
    input           btn_d,
    output reg      o_monitor_type, // SW? W?
    output          o_sel_display,  // s-ms / h-m
    output          o_sw_mode,
    output reg      o_sw_run_stop,
    output reg      o_sw_clear,
    output reg      o_w_modify_mode,
    output reg [3:0] o_w_modify_position,
    output          o_w_up,
    output          o_w_down
);

    // State
    localparam  SYS_SW          = 2'b00,
                SYS_W           = 2'b10,
                SYS_W_MODIFY    = 2'b11;

    localparam  SW_STOP    = 2'b00,
                SW_RUN     = 2'b01,
                SW_CLEAR   = 2'b10;
    
    wire sel_sw_ud, sel_sw_w, sel_sec_hm, sel_RL, sel_modify;

    assign sel_sw_ud = sw_under[0];
    assign sel_sw_w = sw_under[1];
    assign sel_sec_hm = sw_under[2];

    assign sel_RL = sw_upper[0];
    assign sel_modify = sw_upper[1];

    assign o_sel_display = sel_sec_hm;
    assign o_sw_mode = sel_sw_ud;

    assign o_w_up = btn_u;
    assign o_w_down = btn_d;

    // State Variable
    reg [1:0] sys_state, next_sys_state;
    reg [1:0] sw_state, next_sw_state;

    // State Register SL
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            sys_state <= SYS_SW;
            sw_state <= SW_STOP;
        end
        else begin
            sys_state <= next_sys_state;
            sw_state <= next_sw_state;
        end
    end

    // Next State Logic CL
    always @(*) begin
        // System
        next_sys_state = sys_state;
        case (sys_state)
            SYS_SW: begin
                if (sel_sw_w) begin
                    next_sys_state = (sel_modify)? SYS_W_MODIFY : SYS_W;
                end
            end
            SYS_W: begin
                if (~sel_sw_w) begin next_sys_state = SYS_SW; end
                else if (sel_modify) begin next_sys_state = SYS_W_MODIFY; end
            end
            SYS_W_MODIFY: begin
                if (~sel_sw_w) begin next_sys_state = SYS_SW; end
                else if (~sel_modify) begin next_sys_state = SYS_W; end
            end
        endcase

        // Stopwatch
        next_sw_state = sw_state;
        case (sw_state)
            SW_STOP: begin
                if (sys_state == SYS_SW) begin
                    if (btn_l) next_sw_state = SW_CLEAR;
                    else if (btn_r) next_sw_state = SW_RUN;
                end
            end
            SW_RUN: begin
                if (sys_state == SYS_SW) begin
                    if (btn_r) next_sw_state = SW_STOP;
                end
            end
            SW_CLEAR: begin
                next_sw_state = SW_STOP;
            end
        endcase
    end

    // Output Logic CL
    always @(*) begin
        // System
        o_monitor_type = 1'b0;
        o_w_modify_mode = 1'b0;
        o_w_modify_position = 4'b0000;
        case (sys_state)
            SYS_SW: begin
                o_monitor_type = 1'b0;
                o_w_modify_mode = 1'b0;
                o_w_modify_position = 4'b0000;
            end
            SYS_W: begin
                o_monitor_type = 1'b1;
                o_w_modify_mode = 1'b0;
                o_w_modify_position = 4'b0000;
            end
            SYS_W_MODIFY: begin
                o_monitor_type = 1'b1;
                o_w_modify_mode = 1'b1;
                case ({sel_sec_hm, sel_RL})
                    2'b00: o_w_modify_position = 4'b0001;
                    2'b01: o_w_modify_position = 4'b0010;
                    2'b10: o_w_modify_position = 4'b0100;
                    2'b11: o_w_modify_position = 4'b1000;
                endcase
            end
        endcase

        // Stopwatch
        o_sw_run_stop = 1'b0;
        o_sw_clear = 1'b0;
        case (sw_state)
            SW_STOP: begin
                o_sw_run_stop = 1'b0;
                o_sw_clear = 1'b0;
            end
            SW_RUN: begin
                o_sw_run_stop = 1'b1;
                o_sw_clear = 1'b0;
            end
            SW_CLEAR: begin
                o_sw_run_stop = 1'b0;
                o_sw_clear = 1'b1;
            end
        endcase
    end
    

endmodule
