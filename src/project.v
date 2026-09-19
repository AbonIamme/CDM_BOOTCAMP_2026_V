`default_nettype none

module tt_um_brick_breaker (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // ---------------- VGA signals ----------------
  wire        hsync;
  wire        vsync;
  wire        video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;
  reg  [1:0] R, G, B;

  assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uio_out = 0;
  assign uio_oe  = 0;

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
  reg right_is_latest;

  always @(posedge clk) begin
    if (~rst_n) begin
      prev_left       <= 1'b0;
      prev_right      <= 1'b0;
      right_is_latest <= 1'b0;
    end else begin
      prev_left  <= ui_in[0];
      prev_right <= ui_in[1];
      if (ui_in[1] && !prev_right)
        right_is_latest <= 1'b1;
      else if (ui_in[0] && !prev_left)
        right_is_latest <= 1'b0;
    end
  end

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
  localparam BRICK_COUNT   = BRICK_COLS * BRICK_ROWS;
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

  wire frame_tick = (pix_x == 0) && (pix_y == V_DISPLAY);

  integer i;

  always @(posedge clk) begin
    if (~rst_n) begin
      paddle_x    <= (H_DISPLAY - PADDLE_W) / 2;
      ball_x      <= H_DISPLAY/2 - BALL_SIZE/2;
      ball_y      <= V_DISPLAY/2;
      ball_dx     <= BALL_SPEED;
      ball_dy     <= -BALL_SPEED;
      brick_alive <= {BRICK_COUNT{1'b1}};
    end else if (frame_tick) begin
      
      // Automatic temp values for this frame tick step
      reg signed [3:0] next_dx;
      reg signed [3:0] next_dy;
      reg [9:0] bx, by;
      reg hit_paddle;
      reg hit_brick;
      reg [9:0] paddle_hit_offset;

      next_dx = ball_dx;
      next_dy = ball_dy;
      hit_paddle = 1'b0;
      hit_brick  = 1'b0;

      // --- paddle movement ---
      if (move_left && paddle_x >= PADDLE_SPEED)
        paddle_x <= paddle_x - PADDLE_SPEED;
      else if (move_right && paddle_x < (H_DISPLAY - PADDLE_W - PADDLE_SPEED))
        paddle_x <= paddle_x + PADDLE_SPEED;

      // --- Side Walls Collision ---
      if ((ball_dx < 0 && ball_x <= BALL_SPEED) ||
          (ball_dx > 0 && ball_x >= H_DISPLAY - BALL_SIZE - BALL_SPEED)) begin
        next_dx = -ball_dx;
      end

      // --- Top Wall Collision ---
      if (ball_dy < 0 && ball_y <= BALL_SPEED) begin
        next_dy = -ball_dy;
      end

      // --- Paddle Bounce Collision ---
      if (ball_dy > 0 && 
         (ball_y + BALL_SIZE >= PADDLE_Y) && 
         (ball_y <= PADDLE_Y + PADDLE_H) &&
         (ball_x + BALL_SIZE >= paddle_x) && 
         (ball_x <= paddle_x + PADDLE_W)) begin
        
        hit_paddle = 1'b1;
        next_dy = -BALL_SPEED; // Always reflect upward

        if (ball_x < paddle_x)
          paddle_hit_offset = 0;
        else
          paddle_hit_offset = ball_x - paddle_x;

        if (paddle_hit_offset < (PADDLE_W / 3))
          next_dx = -BALL_SPEED;
        else if (paddle_hit_offset >= ((2 * PADDLE_W) / 3))
          next_dx = BALL_SPEED;
        else
          next_dx = ball_dx;
      end

      // --- Brick Collisions ---
      if (!hit_paddle) begin
        for (i = 0; i < BRICK_COUNT; i = i + 1) begin
          if (brick_alive[i] && !hit_brick) begin
            bx = BRICK_START_X + (i % BRICK_COLS) * (BRICK_W + BRICK_GAP);
            by = BRICK_START_Y + (i / BRICK_COLS) * (BRICK_H + BRICK_GAP);
            if ((ball_x + BALL_SIZE >= bx) && (ball_x <= bx + BRICK_W) &&
                (ball_y + BALL_SIZE >= by) && (ball_y <= by + BRICK_H)) begin
              brick_alive[i] <= 1'b0;
              next_dy        = -next_dy;
              hit_brick      = 1'b1;
            end
          end
        end
      end

      // --- Ball Reset / Position Update ---
      if (ball_y + BALL_SIZE >= V_DISPLAY || brick_alive == 0) begin
        ball_x      <= H_DISPLAY/2 - BALL_SIZE/2;
        ball_y      <= V_DISPLAY/2;
        ball_dx     <= BALL_SPEED;
        ball_dy     <= -BALL_SPEED;
        if (brick_alive == 0)
          brick_alive <= {BRICK_COUNT{1'b1}};
      end else begin
        ball_x  <= ball_x + next_dx;
        ball_y  <= ball_y + next_dy;
        ball_dx <= next_dx;
        ball_dy <= next_dy;
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

  reg r, g, b;
  always @(*) begin
    r = 0; g = 0; b = 0;
    if (video_active) begin
      if (ball_on) begin
        r = 1; g = 1; b = 1;
      end else if (paddle_on) begin
        g = 1; b = 1;
      end else if (brick_on) begin
        case (brick_row)
          0: r = 1;
          1: begin r = 1; g = 1; end
          2: g = 1;
          default: b = 1;
        endcase
      end
    end
  end

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
