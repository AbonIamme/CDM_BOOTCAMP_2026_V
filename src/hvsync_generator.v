`ifndef HVSYNC_GENERATOR_H
`define HVSYNC_GENERATOR_H

/*
 * Video sync generator for 640x480 @ 60Hz VGA display.
 * Pixel clock expected: 25.175 MHz (or 25 MHz standard).
 */

module hvsync_generator (
    input  wire       clk,
    input  wire       reset,        // Active high reset
    output reg        hsync,
    output reg        vsync,
    output wire       display_on,
    output reg  [9:0] hpos,
    output reg  [9:0] vpos
);

  // Horizontal timing (pixels)
  localparam H_DISPLAY    = 640;
  localparam H_FRONT      = 16;   // Front porch
  localparam H_SYNC       = 96;   // Sync pulse width
  localparam H_BACK       = 48;   // Back porch
  localparam H_MAX        = H_DISPLAY + H_FRONT + H_SYNC + H_BACK - 1; // 799

  // Vertical timing (lines)
  localparam V_DISPLAY    = 480;
  localparam V_BOTTOM     = 10;   // Front porch
  localparam V_SYNC       = 2;    // Sync pulse width
  localparam V_TOP        = 33;   // Back porch
  localparam V_MAX        = V_DISPLAY + V_BOTTOM + V_SYNC + V_TOP - 1; // 524

  localparam H_SYNC_START = H_DISPLAY + H_FRONT;             // 656
  localparam H_SYNC_END   = H_DISPLAY + H_FRONT + H_SYNC - 1; // 751

  localparam V_SYNC_START = V_DISPLAY + V_BOTTOM;            // 490
  localparam V_SYNC_END   = V_DISPLAY + V_BOTTOM + V_SYNC - 1; // 491

  // Horizontal Counter & HSYNC
  always @(posedge clk) begin
    if (reset) begin
      hpos  <= 10'd0;
      hsync <= 1'b1; // Inactive high
    end else begin
      if (hpos == H_MAX)
        hpos <= 10'd0;
      else
        hpos <= hpos + 1'b1;

      // Active-low sync pulse
      hsync <= ~((hpos >= H_SYNC_START) && (hpos <= H_SYNC_END));
    end
  end

  // Vertical Counter & VSYNC
  always @(posedge clk) begin
    if (reset) begin
      vpos  <= 10'd0;
      vsync <= 1'b1; // Inactive high
    end else if (hpos == H_MAX) begin
      if (vpos == V_MAX)
        vpos <= 10'd0;
      else
        vpos <= vpos + 1'b1;

      // Active-low sync pulse
      vsync <= ~((vpos >= V_SYNC_START) && (vpos <= V_SYNC_END));
    end
  end

  // Display active range (true when beam is within visible screen bounds)
  assign display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);

endmodule

`endif
