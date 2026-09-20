# FPGA Digital Clock & Alarm

A digital clock and alarm system implemented in **Verilog HDL** for FPGA.  
The project provides real-time clock counting, time/alarm configuration, multiplexed 7-segment display, button debouncing, setting timeout, and buzzer feedback.

---

##  Project Overview

This project implements a standalone digital clock with alarm functionality using synchronous digital logic.

The system operates with a **27 MHz input clock** and provides:

- Real-time **HH:MM:SS** clock
- Current time configuration
- Alarm time configuration
- 4-digit 7-segment display
- Button synchronization and debounce
- 0.5-second display blinking during setting modes
- 30-second timeout for time-setting operations
- Short buzzer feedback when buttons are pressed
- Alarm buzzer with a 5-second active period
- 0.5-second ON/OFF alarm modulation

---

##  Features

###  Real-Time Clock

The clock maintains:

- Hours: `00–23`
- Minutes: `00–59`
- Seconds: `00–59`

The 27 MHz system clock is divided down to generate a 1-second timing tick.

###  Alarm

The alarm time can be configured independently from the current clock time.

The alarm is triggered when:

```text
Current Hour   = Alarm Hour
Current Minute = Alarm Minute
```

When the alarm is active:

- The buzzer operates for approximately **5 seconds**
- The alarm sound is modulated with a **0.5-second ON/OFF pattern**

###  Button Handling

Each push button is processed through:

1. Two flip-flop synchronization
2. Debouncing
3. One-shot edge detection

This prevents mechanical button bouncing from generating multiple unwanted events.

###  4-Digit 7-Segment Display

The display shows:

```text
HH:MM
```

The four digits are multiplexed sequentially.

During time/alarm configuration:

- The selected hour digit can blink
- The selected minute digit can blink
- Blink period: approximately **0.5 seconds**

###  Setting Timeout

When entering a setting mode, the system provides a **30-second timeout**.

If no button activity occurs within the timeout period, the setting operation is automatically terminated.

###  Buzzer Feedback

The buzzer provides two types of feedback:

- **Button beep:** short beep when a control button is pressed
- **Alarm:** buzzer remains active for approximately 5 seconds

---

##  System Architecture

The design is divided into several independent Verilog modules.

```text
                         ┌─────────────────────┐
                         │      top_clock      │
                         │    Top-level FSM    │
                         └──────────┬──────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          │                         │                         │
          ▼                         ▼                         ▼
   ┌─────────────┐          ┌───────────────┐         ┌─────────────┐
   │    button   │          │ hour_min_sec  │         │mode_control │
   │ Synchronize │          │  Clock Timer  │         │ Time/Alarm  │
   │  Debounce   │          │   HH:MM:SS    │         │     FSM     │
   └─────────────┘          └───────────────┘         └─────────────┘
                                    │                         │
                                    └────────────┬────────────┘
                                                 ▼
                                         ┌─────────────┐
                                         │ digit_split │
                                         └──────┬──────┘
                                                │
                                                ▼
                                         ┌─────────────┐
                                         │led_multiplex│
                                         │  7-Segment  │
                                         └─────────────┘

                         ┌─────────────────────────────┐
                         │          Buzzer             │
                         │ Button Beep + Alarm Sound  │
                         └─────────────────────────────┘

                         ┌─────────────────────────────┐
                         │          time_30s           │
                         │     Setting Timeout         │
                         └─────────────────────────────┘
```

---

##  Module Structure

| Module | Description |
|---|---|
| `button` | Synchronizes, debounces, and detects a button press edge |
| `hour_min_sec` | Generates the 1-second tick and maintains HH:MM:SS |
| `mode_control` | Controls current-time and alarm-setting modes |
| `digit_split` | Converts hour/minute values into decimal digits |
| `led_multiplex` | Multiplexes the four 7-segment digits and handles blinking |
| `time_30s` | Generates the 30-second setting timeout |
| `buzzer` | Generates button beep and alarm buzzer control |
| `top_clock` | Top-level module connecting the complete system |

---

##  Control Modes

The `mode_control` module contains five operating states:

```text
                 ┌──────────────┐
                 │    NORMAL    │
                 └──────┬───────┘
                        │
             ┌──────────┴──────────┐
             ▼                     ▼
      ┌──────────────┐      ┌──────────────┐
      │ SET_TIME_HH  │      │ SET_ALARM_HH │
      └──────┬───────┘      └──────┬───────┘
             │                     │
             ▼                     ▼
      ┌──────────────┐      ┌──────────────┐
      │ SET_TIME_MM  │      │ SET_ALARM_MM │
      └──────┬───────┘      └──────┬───────┘
             │                     │
             └──────────┬──────────┘
                        ▼
                 ┌──────────────┐
                 │    NORMAL    │
                 └──────────────┘
```

### Available states

| State | Function |
|---|---|
| `NORMAL` | Normal clock display |
| `SET_TIME_HH` | Set current hour |
| `SET_TIME_MM` | Set current minute |
| `SET_ALARM_HH` | Set alarm hour |
| `SET_ALARM_MM` | Set alarm minute |

---

##  Timing Parameters

The design uses a **27 MHz clock**.

| Function | Counter value | Approximate period |
|---|---:|---:|
| 1-second clock tick | `26,999,999` | 1 s |
| Display blink | `13,499,999` | 0.5 s |
| 30-second timeout | `809,999,999` | 30 s |
| Alarm duration | `134,999,999` | 5 s |
| Display multiplex step | `26,999` | 1 ms |

The buzzer carrier is generated separately inside the `buzzer` module.

---

##  Top-Level Interface

The top-level module is:

```verilog
module top_clock(
    input i_clk,
    input i_rst_n,
    input raw_btn_set_time,
    input raw_btn_set_alarm,
    input raw_btn_time_up,
    input raw_btn_time_down,
    output [3:0] choose_led,
    output [6:0] led,
    output o_buzzer
);
```

### Inputs

| Signal | Description |
|---|---|
| `i_clk` | System clock |
| `i_rst_n` | Active-low asynchronous reset |
| `raw_btn_set_time` | Set current time button |
| `raw_btn_set_alarm` | Set alarm button |
| `raw_btn_time_up` | Increase hour/minute |
| `raw_btn_time_down` | Decrease hour/minute |

### Outputs

| Signal | Description |
|---|---|
| `choose_led[3:0]` | 7-segment digit selection |
| `led[6:0]` | 7-segment segment control |
| `o_buzzer` | Buzzer output |

--
##  Design Techniques

This project demonstrates several important RTL design concepts:

- Synchronous digital design
- Asynchronous active-low reset
- Two-flip-flop input synchronization
- Button debouncing
- One-shot pulse generation
- Finite State Machines (FSM)
- Clock/timing counters
- 7-segment display multiplexing
- Decimal digit extraction
- Output combinational decoding
- Alarm state control
- Hierarchical Verilog module design

---

##  Recommended Repository Structure

For a clean GitHub repository, the project can be organized as:

```text
digital-clock-alarm/
│
├── README.md
│
├── rtl/
│   ├── button.v
│   ├── hour_min_sec.v
│   ├── mode_control.v
│   ├── digit_split.v
│   ├── led_multiplex.v
│   ├── time_30s.v
│   ├── buzzer.v
│   └── top_clock.v
│
├── constraints/
│   └── top_clock.cst
│
├── docs/
│   └── block_diagram.png
│
└── simulation/
    └── testbench/
```

If all modules are currently stored in one `.v` file, that is also valid. The modules can be separated into individual files later as the project grows.

---

##  How the System Works

### 1. Button Press

A raw mechanical button signal enters the `button` module.

```text
Raw Button
    ↓
2-FF Synchronizer
    ↓
Debounce Counter
    ↓
Debounced Signal
    ↓
Edge Detection
    ↓
One-Cycle Button Pulse
```

### 2. Clock Generation

`hour_min_sec` counts the 27 MHz clock.

After one second:

```text
tick = 1
```

The clock then updates:

```text
SS → MM → HH
```

with the appropriate rollover conditions.

### 3. Time/Alarm Configuration

`mode_control` determines whether the user is:

- Running the clock normally
- Setting current hour
- Setting current minute
- Setting alarm hour
- Setting alarm minute

The `UP` and `DOWN` buttons modify the selected value.

### 4. Display

The selected time is converted into four decimal digits:

```text
Hour = 15
Minute = 36

15:36
 ↓
1   5   3   6
```

`led_multiplex` rapidly switches between the four digits so that the display appears continuously illuminated.

### 5. Alarm

The alarm comparison is generated in `top_clock`:

```verilog
assign i_tick_alarm = (hour == alarm_hour) &&
                      (min == alarm_min);
```

When the comparison condition is active, the buzzer enters the alarm state.

---

##  Learning Objectives

This project is suitable for practicing:

- Verilog HDL fundamentals
- RTL coding style
- FSM design
- Counter-based timing
- FPGA I/O handling
- Mechanical button debouncing
- 7-segment display control
- Hierarchical module integration
- Basic hardware debugging

---

##  Project Status

**Project type:** FPGA / Digital Design  
**HDL:** Verilog  
**Clock:** 27 MHz  
**Display:** 4-digit 7-segment  
**Main functionality:** Digital clock + alarm

---

##  License

This project is intended for educational and academic purposes.

You may modify and extend the design for learning, experimentation, and personal FPGA projects.
