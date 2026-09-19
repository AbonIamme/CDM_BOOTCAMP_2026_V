/*
 * Brick Breaker for the Tiny Tapeout VGA template.
 * Reuses hvsync_generator.v from the tt_um_vga_example project.
 *
 * Controls (ui_in[7:0]):
 *   ui_in[0] = move paddle left
 *   ui_in[1] = move paddle right
 *   If both are held, the paddle follows whichever button had its
 *   rising edge most recently ("latest input wins").
 *   ui_in[7:2] are unused.
 */

`default_nettype none

module tt_um_brick_breaker (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // ---------------- VGA signals ----------------
  wire       hsync;
  wire       vsync;
  wire       video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;
  reg  [1:0] R, G, B;

  // TinyVGA PMOD output mapping
  assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uio_out = 0;
  assign uio_oe  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, uio_in, ui_in[7:2]};

  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  // ---------------- controls ----------------
  reg prev_left, prev_right;
  reg right_is_latest;  // 1 = right was the most recently pressed button

  always @(posedge clk) begin
    if (~rst_n) begin
      prev_left       <= 1'b0;
      prev_right      <= 1'b0;
      right_is_latest <= 1'b0;
    end else begin
      prev_left  <= ui_in[0];
      prev_right <= ui_in[1];
      if (ui_in[1] && !prev_right)
        right_is_latest <= 1'b1;         // right just pressed
      else if (ui_in[0] && !prev_left)
        right_is_latest <= 1'b0;         // left just pressed
    end
  end

  // effective direction: latest-pressed button wins when both are held
  wire move_left  = ui_in[0] && !(ui_in[1] &&  right_is_latest);
  wire move_right = ui_in[1] && !(ui_in[0] && !right_is_latest);

  // ---------------- game parameters ----------------
  localparam H_DISPLAY = 640;
  localparam V_DISPLAY = 480;

  localparam PADDLE_W     = 64;
  localparam PADDLE_H     = 8;
  localparam PADDLE_Y     = 456;
  localparam PADDLE_SPEED = 4;

  localparam BALL_SIZE  = 6;
  localparam BALL_SPEED = 2;

  localparam BRICK_COLS    = 8;
  localparam BRICK_ROWS    = 4;
  localparam BRICK_COUNT   = BRICK_COLS * BRICK_ROWS;  // 32
  localparam BRICK_W       = 70;
  localparam BRICK_H       = 16;
  localparam BRICK_GAP     = 6;
  localparam BRICK_START_X = 19;
  localparam BRICK_START_Y = 40;

  // ---------------- game state ----------------
  reg [9:0] paddle_x;
  reg [9:0] ball_x, ball_y;
  reg signed [3:0] ball_dx, ball_dy;
  reg [BRICK_COUNT-1:0] brick_alive;

  // fires once per frame (start of vertical blank)
  wire frame_tick = (pix_x == 0) && (pix_y == V_DISPLAY);

  integer i;
  reg signed [3:0] new_dx, new_dy;
  reg [9:0] bx, by;
  reg hit_this_frame;

  always @(posedge clk) begin
    if (~rst_n) begin
      paddle_x    <= (H_DISPLAY - PADDLE_W) / 2;
      ball_x      <= H_DISPLAY/2 - BALL_SIZE/2;
      ball_y      <= V_DISPLAY/2;
      ball_dx     <= BALL_SPEED;
      ball_dy     <= -BALL_SPEED;
      brick_alive <= {BRICK_COUNT{1'b1}};
    end else if (frame_tick) begin

      // --- paddle movement ---
      if (move_left && paddle_x > 0)
        paddle_x <= paddle_x - PADDLE_SPEED;
      else if (move_right && paddle_x < (H_DISPLAY - PADDLE_W))
        paddle_x <= paddle_x + PADDLE_SPEED;

      // --- figure out next ball direction ---
      new_dx = ball_dx;
      new_dy = ball_dy;

      // side walls
      if ((ball_dx < 0 && ball_x <= BALL_SPEED) ||
          (ball_dx > 0 && ball_x >= H_DISPLAY - BALL_SIZE - BALL_SPEED))
        new_dx = -ball_dx;

      // top wall
      if (ball_dy < 0 && ball_y <= BALL_SPEED)
        new_dy = -ball_dy;

      // Reset hit flag for this frame tick
      hit_this_frame = 1'b0;

      // paddle bounce: Look ahead tracking (checks overlap with paddle area)
      if (ball_dy > 0 &&
          (ball_y + BALL_SIZE >= PADDLE_Y) && (ball_y <= PADDLE_Y + PADDLE_H) &&
          (ball_x + BALL_SIZE >= paddle_x) && (ball_x <= paddle_x + PADDLE_W)) begin
        new_dy         = -BALL_SPEED; // Force direction UP completely independent of state
        hit_this_frame = 1'b1;        // Mark hit to bypass brick checks this frame
      end

      // brick collisions (Yosys Synthesizable Loop)
      for (i = 0; i < BRICK_COUNT; i = i + 1) begin
        if (brick_alive[i] && !hit_this_frame) begin
          bx = BRICK_START_X + (i % BRICK_COLS) * (BRICK_W + BRICK_GAP);
          by = BRICK_START_Y + (i / BRICK_COLS) * (BRICK_H + BRICK_GAP);
          if (ball_x + BALL_SIZE >= bx && ball_x <= bx + BRICK_W &&
              ball_y + BALL_SIZE >= by && ball_y <= by + BRICK_H) begin
            brick_alive[i] <= 1'b0;
            new_dy         = -new_dy; // Reverse current calculated direction cleanly
            hit_this_frame = 1'b1;    // Flag ensures other iterations are ignored
          end
        end
      end

      // --- ball lost off bottom, or level cleared: respawn ---
      if (ball_y + BALL_SIZE >= V_DISPLAY || brick_alive == 0) begin
        ball_x  <= H_DISPLAY/2 - BALL_SIZE/2;
        ball_y  <= V_DISPLAY/2;
        ball_dx <= BALL_SPEED;
        ball_dy <= -BALL_SPEED;
        if (brick_alive == 0)
          brick_alive <= {BRICK_COUNT{1'b1}};
      end else begin
        // Apply calculated updates directly to positions to clear boundary limits
        ball_x  <= ball_x + new_dx;
        ball_y  <= ball_y + new_dy;
        ball_dx <= new_dx;
        ball_dy <= new_dy;
      end
    end
  end

  // ---------------- rendering ----------------
  wire ball_on = (pix_x >= ball_x) && (pix_x < ball_x + BALL_SIZE) &&
                 (pix_y >= ball_y) && (pix_y < ball_y + BALL_SIZE);

  wire paddle_on = (pix_x >= paddle_x) && (pix_x < paddle_x + PADDLE_W) &&
                   (pix_y >= PADDLE_Y) && (pix_y < PADDLE_Y + PADDLE_H);

  wire in_brick_field = (pix_x >= BRICK_START_X) && (pix_y >= BRICK_START_Y) &&
                        (pix_x < BRICK_START_X + BRICK_COLS*(BRICK_W+BRICK_GAP)) &&
                        (pix_y < BRICK_START_Y + BRICK_ROWS*(BRICK_H+BRICK_GAP));

  wire [9:0] brick_col_pos = (pix_x - BRICK_START_X) % (BRICK_W + BRICK_GAP);
  wire [9:0] brick_row_pos = (pix_y - BRICK_START_Y) % (BRICK_H + BRICK_GAP);
  wire [3:0] brick_col     = (pix_x - BRICK_START_X) / (BRICK_W + BRICK_GAP);
  wire [3:0] brick_row     = (pix_y - BRICK_START_Y) / (BRICK_H + BRICK_GAP);
  wire [5:0] brick_index   = brick_row * BRICK_COLS + brick_col;

  wire brick_on = in_brick_field && (brick_col_pos < BRICK_W) && (brick_row_pos < BRICK_H) &&
                  brick_alive[brick_index];

  // combinational color choice (1 bit per channel)
  reg r, g, b;
  always @(*) begin
    r = 0; g = 0; b = 0;
    if (video_active) begin
      if (ball_on) begin
        r = 1; g = 1; b = 1;              // white ball
      end else if (paddle_on) begin
        g = 1; b = 1;                     // cyan paddle
      end else if (brick_on) begin
        case (brick_row)
          0: r = 1;                       // red
          1: begin r = 1; g = 1; end      // yellow
          2: g = 1;                       // green
          default: b = 1;                 // blue
        endcase
      end
    end
  end

  // registered output, duplicated into the 2-bit R/G/B PMOD channels
  always @(posedge clk) begin
    if (~rst_n) begin
      R <= 0;
      G <= 0;
      B <= 0;
    end else begin
      R <= {r, r};
      G <= {g, g};
      B <= {b, b};
    end
  end

endmodule
