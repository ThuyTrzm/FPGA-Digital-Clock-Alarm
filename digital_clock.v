/* =====================================================================
 * Project Name: FPGA Digital Clock with Alarm & Configuration FSM
 * Description: Comprehensive digital clock system featuring real-time counting,
 *              debounce filtering, FSM-based configuration, multiplexed 7-segment 
 *              display, 30s timeout protection, and a PWM buzzer notifier.
 * ===================================================================== */

`timescale 1ns / 1ps

// =====================================================================
// Module: Button Debouncer & Edge Detector
// Filters mechanical bounce and generates a single-cycle active-high pulse.
// =====================================================================
module button(
    input i_clk, i_rst_n,
    input raw_btn,
    output out_edge
    );
    
    reg ff1, ff2;
    reg [22:0] cnt_btn;
    reg btn_db;
    reg btn_pre;
    
    // Step 1: Dual flip-flop synchronizer to avoid metastability from asynchronous inputs
    always@(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n) begin
            ff1 <= 1'b0;
            ff2 <= 1'b0;
        end
        else begin
            ff1 <= raw_btn;
            ff2 <= ff1;
        end
    end
    
    // Step 2: Debounce filter using a clock-cycle counter
    always@(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            cnt_btn <= 1'd0;
            btn_db <= 1'b1; // Default pull-up state assumption
        end
        else begin
            if(ff2 != btn_db)begin
                // Wait for stable input state over threshold clock cycles
                if(cnt_btn < 23'd5400000)
                    cnt_btn <= cnt_btn + 1'd1;
                else begin
                    cnt_btn <= 1'd0;
                    btn_db <= ff2; // Update stable debounced button state
                end
           end
           else
                cnt_btn <= 1'd0;
        end
    end
    
    // Step 3: Rising edge detection on the debounced signal
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            btn_pre <= 1'b1;
        else
            btn_pre <= btn_db;
    end
    assign out_edge = (~btn_db) & btn_pre;

endmodule


// =====================================================================
// Module: Real-Time Clock Core (Hour, Minute, Second Counter)
// Generates 1-second ticks from system clock and maintains timekeeping.
// =====================================================================
module hour_min_sec(
    input i_clk, i_rst_n,
    input load,
    input [4:0] set_hour,
    input [5:0] set_min,
    output reg tick,
    output reg [24:0] cnt,
    output reg [4:0] hour,
    output reg [5:0] min,
    output reg [5:0] sec
    );
    
    // Step 1: Clock divider to generate a precise 1-second pulse (tick)
    always@(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            tick <= 1'b0;
            cnt <= 1'd0;
        end
        else begin
            tick <= 1'b0;
            if(cnt < 25'd26_999_999)
                cnt <= cnt + 1'd1;
            else begin
                cnt <= 1'd0;
                tick <= 1'b1; // Trigger 1-second tick flag
            end
        end
    end

    // Step 2: Time progression logic (Seconds -> Minutes -> Hours) with manual load override
    always@(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            hour <= 5'd15; // Default initial hour
            min <= 6'd36;  // Default initial minute
            sec <= 1'd0;
        end
        else begin
            if(load)begin
                // Synchronously load user-configured time values
                hour <= set_hour;
                min <= set_min;
                sec <= 1'd0;
            end
            else if(tick)begin
                // Standard increment pipeline upon every 1-second tick
                if(sec < 6'd59)
                    sec <= sec + 1'd1;
                else begin
                    sec <= 1'd0;
                    if(min < 6'd59)
                        min <= min + 1'd1;
                    else begin
                        min <= 1'd0;
                        if(hour < 5'd23)
                            hour <= hour + 1'd1;
                        else
                            hour <= 1'd0; // Roll over at midnight (23:59:59 -> 00:00:00)
                    end
                end
            end
        end
    end
endmodule


// =====================================================================
// Module: Mode Control FSM
// Manages system states (Normal, Set Time, Set Alarm) and user inputs.
// =====================================================================
module mode_control(
    input i_clk, i_rst_n,
    input btn_set_time,
    input btn_set_alarm,
    input btn_up,
    input btn_down,
    input tick_time_out,
    input [4:0] hour,
    input [5:0] min,
    output reg [4:0] settime_hour,
    output reg [5:0] settime_min,
    output reg [4:0] alarm_hour,
    output reg [5:0] alarm_min,
    output reg led_hour,
    output reg led_min,
    output reg load,
    output reg [2:0] state_mode
    );
    
    // Define FSM states for operational modes
    localparam NORMAL        = 3'd0;
    localparam SET_TIME_HH   = 3'd1;
    localparam SET_TIME_MM   = 3'd2;
    localparam SET_ALARM_HH  = 3'd3;
    localparam SET_ALARM_MM  = 3'd4;
    
    always@(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n) begin
            led_hour <= 1'b0;
            led_min <= 1'b0;
            settime_hour <= 5'd0;
            settime_min <= 6'd0;
            alarm_hour <= 5'd0;
            alarm_min <= 6'd0;
            load <= 1'b0;
            state_mode <= NORMAL;
        end
        else begin
            load <= 1'b0; // Default load pulse to low
            case(state_mode)
                // --- STATE: NORMAL OPERATION ---
                NORMAL: begin
                    led_hour <= 1'b0;
                    led_min <= 1'b0;
                    settime_hour <= hour;
                    settime_min <= min;
                    if(btn_set_time && !btn_set_alarm) begin
                        state_mode <= SET_TIME_HH;
                    end
                    else if(!btn_set_time && btn_set_alarm)                
                        state_mode <= SET_ALARM_HH;
                    else
                        state_mode <= NORMAL;
                end
                
                // --- STATE: CONFIGURE TIME - HOURS ---
                SET_TIME_HH: begin
                    led_hour <= 1'b1;
                    led_min <= 1'b0;
                    if(btn_up && !tick_time_out) begin                      
                        if(settime_hour == 5'd23)
                            settime_hour <= 1'd0;
                        else
                            settime_hour <= settime_hour + 1'd1;
                    end
                    if(btn_down && !tick_time_out) begin                      
                        if(settime_hour == 5'd0)
                            settime_hour <= 5'd23;
                        else
                            settime_hour <= settime_hour - 1'd1;
                    end
                    if(btn_set_time && !tick_time_out) begin
                        load <= 1'b1;
                        led_min <= 1'b1;
                        state_mode <= SET_TIME_MM;
                    end
                    else if(tick_time_out) begin
                        load <= 1'b1;
                        state_mode <= NORMAL;
                    end
                end

                
                // --- STATE: CONFIGURE TIME - MINUTES ---
                SET_TIME_MM: begin    
                     led_min <= 1'b1;   
                    led_hour <= 1'b0;                   
                    if(btn_up && !tick_time_out) begin
                        if(settime_min == 6'd59)
                            settime_min <= 1'd0;
                        else
                            settime_min <= settime_min + 1'd1;
                    end
                    if(btn_down && !tick_time_out) begin         
                        if(settime_min == 5'd0)
                            settime_min <= 6'd59;
                        else
                            settime_min <= settime_min - 1'd1;
                    end 
                    if(btn_set_time && !tick_time_out)begin
                        load <= 1'b1;
                        state_mode <= NORMAL;
                     end
                    if(tick_time_out) begin
                        load <= 1'b1;
                        state_mode <= NORMAL;
                    end
                end
                
                // --- STATE: CONFIGURE ALARM - HOURS ---
                SET_ALARM_HH: begin
                    led_min <= 1'b0;   
                    led_hour <= 1'b1;
                     if(btn_up && !tick_time_out) begin
                        if(alarm_hour == 5'd23)
                            alarm_hour <= 1'd0;
                        else
                            alarm_hour <= alarm_hour + 1'd1;
                    end
                    if(btn_down && !tick_time_out) begin         
                        if(alarm_hour == 5'd0)
                            alarm_hour <= 5'd23;
                        else
                            alarm_hour <= alarm_hour - 1'd1;
                    end 
                    if(btn_set_alarm && !tick_time_out)begin
                        load <= 1'b1;
                        state_mode <= SET_ALARM_MM;
                     end
                    if(tick_time_out) begin
                        load <= 1'b1;
                        state_mode <= NORMAL;
                    end                
                end

                
                // --- STATE: CONFIGURE ALARM - MINUTES ---
                SET_ALARM_MM: begin
                   led_min <= 1'b0;   
                    led_hour <= 1'b1;
                     if(btn_up && !tick_time_out) begin
                        if(alarm_min == 6'd59)
                            alarm_min <= 1'd0;
                        else
                            alarm_hour <= alarm_hour + 1'd1;
                    end
                    if(btn_down && !tick_time_out) begin         
                        if(alarm_min == 5'd0)
                            alarm_min <= 6'd59;
                        else
                            alarm_min <= alarm_min - 1'd1;
                    end 
                    if(btn_set_alarm && !tick_time_out)begin
                        load <= 1'b1;
                        state_mode <= SET_ALARM_MM;
                     end
                    if(tick_time_out) begin
                        load <= 1'b1;
                        state_mode <= NORMAL;
                    end
                end
            endcase
        end
   end
   
endmodule


// =====================================================================
// Module: Digit Splitter (Binary to BCD)
// Separates hour and minute binary values into tens and units digits.
// =====================================================================
module digit_split(
    input [4:0] hour,
    input [5:0] min,
    output [3:0] chuc_hour,
    output [3:0] dv_hour,
    output [3:0] chuc_min,
    output [3:0] dv_min
    );
    
    // Extract decimal digits via arithmetic division and modulo operations
    assign chuc_hour = hour / 4'd10;
    assign dv_hour   = hour % 4'd10;
    assign chuc_min  = min / 4'd10;
    assign dv_min    = min % 4'd10;
    
endmodule


// =====================================================================
// Module: LED Multiplexer & 7-Segment Driver
// Handles time-division multiplexing for 4-digit display and blink effects.
// =====================================================================
module led_multiplex(
    input i_clk, i_rst_n,
    input [3:0] chuc_hour,
    input [3:0] dv_hour,
    input [3:0] chuc_min,
    input [3:0] dv_min,
    input led_hour, led_min,
    
    output reg [14:0] cnt_led,
    output reg [3:0] sel_cnt,
    output reg [3:0] choose_led,
    output reg [1:0] state_led,
    output reg [6:0] led,
    output reg blink_05s
    );
    
    reg [23:0] cnt_05s;
    
    localparam LED0 = 2'd0;
    localparam LED1 = 2'd1;
    localparam LED2 = 2'd2;
    localparam LED3 = 2'd3;
    
    // Step 1: Generate 0.5-second clock pulse for configuration blinking effects
    always@(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n) begin
            cnt_05s <= 1'd0;
            blink_05s <= 1'b0;
        end
        else begin
            if(cnt_05s < 24'd13_499_999) begin
                cnt_05s <= cnt_05s + 1'd1;
            end
            else begin
                cnt_05s <= 1'd0;
                blink_05s <= ~blink_05s;
            end
        end
    end
    
    // Step 2: Multiplexing scan state machine to drive 4 digits sequentially
    always@(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            choose_led <= 4'b0001;
            state_led <= LED0;
            cnt_led <= 1'd0;      
            sel_cnt <= 1'd0; 
        end else begin
            case(state_led)
                LED0: begin
                    choose_led <= 4'b0001;
                    sel_cnt <= chuc_hour;
                    if(blink_05s && led_hour) sel_cnt <= 4'd10;
                    if(cnt_led < 15'd26_999)
                        cnt_led <= cnt_led + 1'd1;
                    else begin
                        cnt_led <= 1'd0;
                        state_led <= LED1;
                    end
                end
                LED1: begin
                    choose_led <= 4'b0010;
                    sel_cnt <= dv_hour;
                    if(blink_05s && led_hour) sel_cnt <= 4'd10;
                    if(cnt_led < 15'd26_999)
                        cnt_led <= cnt_led + 1'd1;
                    else begin
                        cnt_led <= 1'd0;
                        state_led <= LED2;
                    end
                end
                LED2: begin
                    choose_led <= 4'b0100;
                    sel_cnt <= chuc_min;
                    if(blink_05s && led_min) sel_cnt <= 4'd10;
                    if(cnt_led < 15'd26_999)
                        cnt_led <= cnt_led + 1'd1;
                    else begin
                        cnt_led <= 1'd0;
                        state_led <= LED3;
                    end
                end
                LED3: begin
                    choose_led <= 4'b1000;
                    sel_cnt <= dv_min;  
                    if(blink_05s && led_min) sel_cnt <= 4'd10;
                    if(cnt_led < 15'd26_999)
                        cnt_led <= cnt_led + 1'd1;
                    else begin
                        cnt_led <= 1'd0;
                        state_led <= LED0;
                    end
                end

            endcase
        end
    end
    
    // Step 3: 7-segment active-low/high display pattern decoder logic
    always @(*) begin
        case (sel_cnt)
            4'd0: led = 7'b1000000; 
            4'd1: led = 7'b1111001;
            4'd2: led = 7'b0100100;
            4'd3: led = 7'b0110000;
            4'd4: led = 7'b0011001;
            4'd5: led = 7'b0010010;
            4'd6: led = 7'b0000010;
            4'd7: led = 7'b1111000;
            4'd8: led = 7'b0000000;
            4'd9: led = 7'b0010000;
            default: led = 7'b1111111; // Blank display state for blinking
        endcase
    end
endmodule


// =====================================================================
// Module: 30-Second Inactivity Timeout Timer
// Forces return to NORMAL mode if no button is pressed for 30 seconds.
// =====================================================================
module time_30s(
    input i_clk, i_rst_n,
    input press_button,
    output reg tick_time_out
    );
    
    reg [29:0] cnt_30s;
    reg timeout_fired;
    
    always@(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n) begin
            cnt_30s <= 1'd0;
            tick_time_out <= 1'b0;
            timeout_fired <= 1'b0;
        end
        else begin
            if(press_button) begin
                // Reset timeout counter upon any button action
                cnt_30s <= 1'd0;
                tick_time_out <= 1'b0;
                timeout_fired <= 1'b0;
            end
            else begin
                tick_time_out <= 1'b0;
                if(!timeout_fired) begin
                    if(cnt_30s < 30'd809_999_999)
                        cnt_30s <= cnt_30s + 1'd1;
                    else begin
                        tick_time_out <= 1'b1; // Trigger timeout flag
                        timeout_fired <= 1'b1;
                    end
                end
            end
        end
    end
endmodule


// =====================================================================
// Module: Buzzer Controller
// Generates PWM audio feedback for button clicks and alarm sequences.
// =====================================================================
module buzzer(
    input i_clk,
    input i_rst_n,
    input i_tick_alarm,

    input i_btn_set_time,
    input i_btn_set_alarm,
    input i_btn_up,
    input i_btn_down,

    output reg o_buzzer
);
    
    localparam IDLE        = 2'd0;
    localparam BUTTON_BEEP = 2'd1;
    localparam ALARM       = 2'd2;

    reg [1:0] state;
    reg [13:0] pwm_cnt;
    reg sound_freq;

    // Step 1: Base audio tone generator via PWM clock divider
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            pwm_cnt <= 14'd0;
            sound_freq <= 1'b0;
        end
        else begin
            if(pwm_cnt < 14'd8181) begin
                pwm_cnt <= pwm_cnt + 1'b1;
            end
            else begin
                pwm_cnt <= 14'd0;
                sound_freq <= ~sound_freq;
            end
        end
    end

    wire button_beep;
    assign button_beep = i_btn_set_time | i_btn_set_alarm | i_btn_up | i_btn_down;

    reg [23:0] cnt_button;
    reg [27:0] cnt_5s;
    reg [23:0] cnt_05s;
    reg buzzer_state;

    // Step 2: Audio pattern control state machine
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            state <= IDLE;
            cnt_button <= 24'd0;
            cnt_5s <= 28'd0;
            cnt_05s <= 24'd0;
            buzzer_state <= 1'b0;
        end
        else begin
            case(state)
                IDLE: begin
                    cnt_button <= 24'd0;
                    cnt_5s <= 28'd0;
                    cnt_05s <= 24'd0;
                    buzzer_state <= 1'b0;
                    if(i_tick_alarm)
                        state <= ALARM;
                    else if(button_beep)
                        state <= BUTTON_BEEP;
                    else
                        state <= IDLE;
                end
               BUTTON_BEEP: begin             
                    // Short beep profile for button clicks (~0.5s duration)
                    if(cnt_button < 24'd13_499_999) begin
                        cnt_button <= cnt_button + 1'b1;
                    end
                    else begin
                        cnt_button <= 22'd0;
                        state <= IDLE;
                    end
                end
                ALARM: begin
                    // Alarm duration filter (~5 seconds total)
                    if(cnt_5s < 28'd134_999_999) begin
                        cnt_5s <= cnt_5s + 1'b1;
                    end
                    else begin
                        cnt_5s <= 28'd0;
                        cnt_05s <= 24'd0;
                        buzzer_state <= 1'b0;
                        state <= IDLE;
                    end
                    // Intermittent toggle pattern during alarm
                    if(cnt_05s < 24'd13_499_999) begin
                        cnt_05s <= cnt_05s + 1'b1;
                    end
                    else begin
                        cnt_05s <= 24'd0;
                        buzzer_state <= ~buzzer_state;
                    end
                end
                default: begin
                    state <= IDLE;
                    cnt_button <= 22'd0;
                    cnt_5s <= 28'd0;
                    cnt_05s <= 24'd0;
                    buzzer_state <= 1'b0;
                end
            endcase
        end
    end

    // Step 3: Output audio modulation routing
    always @(*) begin
        case(state)
            IDLE: o_buzzer = 1'b0;
            BUTTON_BEEP: o_buzzer = sound_freq;
            ALARM: o_buzzer = buzzer_state & sound_freq;
            default: o_buzzer = 1'b0;
        endcase
    end
endmodule


// =====================================================================
// Module: Top Level Clock Integration
// Connects all submodules, managing system buses and routing.
// =====================================================================
module top_clock(
    input i_clk, i_rst_n,
    input raw_btn_set_time,
    input raw_btn_set_alarm,
    input raw_btn_time_up,
    input raw_btn_time_down,
    output [3:0] choose_led,
    output [6:0] led,
    output o_buzzer 
    );
    
    // Internal signal declarations and structural buses
    wire [24:0] cnt;
    wire tick;
    wire [4:0] settime_hour;
    wire [5:0] settime_min;
    wire [4:0] alarm_hour;
    wire [5:0] alarm_min;
    wire [5:0] sec;
    wire [1:0] state_led;
    wire [4:0] hour;
    wire [5:0] min;
    wire [3:0] chuc_hour;
    wire [3:0] dv_hour;
    wire [3:0] chuc_min; 
    wire [3:0] dv_min;
    wire [14:0] cnt_led;
    wire btn_set_time;
    wire btn_set_alarm;
    wire btn_up;
    wire btn_down;
    wire tick_time_out;
    wire [2:0] state_mode;
    wire [3:0] sel_cnt;
    wire led_hour, led_min;
    wire blink_05s;
    wire load;
    wire i_tick_alarm;
    
    wire [4:0] display_hour;
    wire [5:0] display_min;
    wire is_alarm_mode;
    wire button;
    
    // Combinational routing logic for display selection multiplexing
    assign button = btn_set_time | btn_set_alarm | btn_up | btn_down;
    assign is_alarm_mode = (state_mode == 3'd3) || (state_mode == 3'd4);
    assign display_hour = is_alarm_mode ? alarm_hour : settime_hour;
    assign display_min  = is_alarm_mode ? alarm_min  : settime_min;
    
    assign i_tick_alarm = (hour == alarm_hour) && (min == alarm_min);
    
    // Submodule instantiation: Button Debouncers
    button set_time(
        .i_clk(i_clk), 
        .i_rst_n(i_rst_n),
        .raw_btn(raw_btn_set_time), 
        .out_edge(btn_set_time)
    );
    
    button set_alarm(
        .i_clk(i_clk), 
        .i_rst_n(i_rst_n),
        .raw_btn(raw_btn_set_alarm), 
        .out_edge(btn_set_alarm)
    );
    
    button time_up(
        .i_clk(i_clk), 
        .i_rst_n(i_rst_n),
        .raw_btn(raw_btn_time_up), 
        .out_edge(btn_up)
    );
    
    button time_down(
        .i_clk(i_clk), 
        .i_rst_n(i_rst_n),
        .raw_btn(raw_btn_time_down), 
        .out_edge(btn_down)
    );
    
    // Submodule instantiation: Real-Time Clock Core
    hour_min_sec U1(
        .i_clk(i_clk), 
        .i_rst_n(i_rst_n), 
        .load(load),
        .set_hour(settime_hour), 
        .set_min(settime_min),
        .tick(tick), 
        .cnt(cnt), 
        .hour(hour), 
        .min(min), 
        .sec(sec)
     );
     
    // Submodule instantiation: Mode Control FSM
    mode_control U2(
        .i_clk(i_clk), 
        .i_rst_n(i_rst_n),
        .btn_set_time(btn_set_time), 
        .btn_set_alarm(btn_set_alarm),
        .btn_up(btn_up), 
        .btn_down(btn_down), 
        .tick_time_out(tick_time_out),
        .hour(hour), 
        .min(min),
        .settime_hour(settime_hour), 
        .settime_min(settime_min),
        .alarm_hour(alarm_hour), 
        .alarm_min(alarm_min),
        .led_hour(led_hour), 
        .led_min(led_min), 
        .load(load), 
        .state_mode(state_mode)
    );
   
    // Submodule instantiation: Digit Splitter (Binary to BCD)
    digit_split U3(
        .hour(display_hour), 
        .min(display_min),
        .chuc_hour(chuc_hour), 
        .dv_hour(dv_hour),
        .chuc_min(chuc_min), 
        .dv_min(dv_min)
    );
    
    // Submodule instantiation: LED Multiplexer and 7-Segment Driver
    led_multiplex U4(
        .i_clk(i_clk), 
        .i_rst_n(i_rst_n),
        .chuc_hour(chuc_hour), 
        .dv_hour(dv_hour),
        .chuc_min(chuc_min), 
        .dv_min(dv_min),
        .led_hour(led_hour), 
        .led_min(led_min),
        .cnt_led(cnt_led), 
        .sel_cnt(sel_cnt),
        .choose_led(choose_led), 
        .state_led(state_led),
        .led(led), 
        .blink_05s(blink_05s)
    );

    // Submodule instantiation: 30-Second Inactivity Timeout Timer
    time_30s U6(
        .i_clk(i_clk), 
        .i_rst_n(i_rst_n),
        .press_button(button), 
        .tick_time_out(tick_time_out)
   );
   
    // Submodule instantiation: Buzzer Controller
    buzzer u_buzzer(
        .i_clk(i_clk), 
        .i_rst_n(i_rst_n),
        .i_tick_alarm(i_tick_alarm),
        .i_btn_set_time(btn_set_time), 
        .i_btn_set_alarm(btn_set_alarm),
        .i_btn_up(btn_up), 
        .i_btn_down(btn_down),
        .o_buzzer(o_buzzer)
    );
endmodule
