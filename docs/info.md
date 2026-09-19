# Brick Breaker VGA Game

A standalone 2D Brick Breaker game written in Verilog, designed for Tiny Tapeout. It outputs VGA video signals (640x480 resolution) and accepts direct digital input controls for real-time player movement.

## How it works

- **VGA Generator:** Uses an external timing generator module (`hvsync_generator`) to generate standard 640x480 @ 60Hz video timing signals (`hsync`, `vsync`, `video_active`, `pix_x`, `pix_y`).
- **Input Synchronization & Priority Tracking:** 
  - Input pins `ui_in[1]` (Left) and `ui_in[2]` (Right) are synchronized through 2-stage flip-flop synchronizers to prevent metastability from asynchronous button presses.
  - An internal register (`last_dir`) tracks the most recent button edge so that if both direction buttons are pressed simultaneously, movement priority defaults to the latest input.
- **Physics Engine (Frame-synchronized):**
  - Updated on the falling edge of `vsync` (60 FPS tick).
  - Handles ball movement, bounding-box collisions for walls, paddle hits, and individual brick impacts.
  - Dynamic ball bounce deflection occurs depending on where the ball strikes the paddle (left, center, or right third).
  - Tracks a grid of 32 bricks (8 columns × 4 rows) using a 32-bit register array (`brick_alive`).
- **Rendering Pipeline:**
  - Combinational pixel match logic computes pixel ownership for ball, paddle, and active bricks during active display periods.
  - Multi-colored brick rows: Red (Row 0), Yellow (Row 1), Green (Row 2), and Blue (Row 3).
  - Outputs 2-bit color components ($R$, $G$, $B$) mapped directly to the TinyVGA PMOD output pinout.

## How to test

1. **Clock & Reset Setup:**
   - Supply a standard 25.175 MHz clock (or ~25 MHz system clock) to `clk`.
   - Apply an active-low reset pulse to `rst_n` to initialize the paddle, ball, and brick layout.
2. **Video Verification:**
   - Connect the output pins (`uo_out[7:0]`) to a TinyVGA PMOD connected to a VGA display.
   - You should see a white ball bouncing off boundaries, multi-colored brick rows at the top, and a cyan paddle at the bottom.
3. **Controls Testing:**
   - Drive `ui_in[1]` HIGH to move the paddle left.
   - Drive `ui_in[2]` HIGH to move the paddle right.
   - Drive both `ui_in[1]` and `ui_in[2]` HIGH simultaneously to confirm the paddle responds to whichever pin transitioned HIGH most recently.

## External hardware

- **TinyVGA PMOD:** Connected to `uo_out[7:0]` using standard Tiny Tapeout 2-bit R2R resistor ladder mapping for VGA video output:
  - `uo_out[7]`: HSYNC
  - `uo_out[6]`: Blue Bit 0
  - `uo_out[5]`: Green Bit 0
  - `uo_out[4]`: Red Bit 0
  - `uo_out[3]`: VSYNC
  - `uo_out[2]`: Blue Bit 1
  - `uo_out[1]`: Green Bit 1
  - `uo_out[0]`: Red Bit 1
- **Monitors & Controls:**
  - Standard VGA-compatible monitor or video capture card (640x480 @ 60Hz).
  - 2x Active-HIGH pushbuttons or joystick inputs wired to `ui_in[1]` (Left) and `ui_in[2]` (Right) with pull-down resistors.
