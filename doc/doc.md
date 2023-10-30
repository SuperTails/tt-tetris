# Pin Assigment

Outputs:
    1. R
    2. G
    3. B
    4. HSYNC
    5. VSYNC
    6. MEM_START
    7. MEM_WRITE_ENABLE
    8. MEM_CONT

Inputs:
    1. Left
    2. Right
    3. Down
    4. Spin Clockwise
    5. Spin Counterclockwise
    6. --
    7. --
    8. --

Bidirectional:
    1. D0/A0
    2. D1/A1
    3. D2/A2
    4. A3
    5. A4
    6. A5
    7. --
    8. MEM_CLK

## States

The game has several different states.

State transitions only occur on odd-to-even frame boundaries.

### `FALLING`

The falling state is the normal mode of gameplay in Tetris.
The player can control the movement of the falling piece,
and the falling piece is checked for collisions with the matrix.

If the falling piece hits the bottom, `needs_to_lock` will be asserted,
and the game will go to the LOCKING state on the next frame.

If the falling piece collides in the same frame as when it spawns, the game is over,
and it will go to the GAME OVER state on the next frame.

### `LOCKING`

The locking state is only entered for a single frame.
It is used to "lock" the falling piece into the matrix.

The player does not have any control during this time.

This state asserts `write_back_falling` in order to save the falling piece into the matrix.

The game will go to COLLAPSING on the next odd-to-even frame.

### `COLLAPSING`

In the collapsing state, the game checks for any rows in the matrix that are full,
and clears them by copying all the rows above downwards.

In this state, full rows are checked on even frames, and the rows are moved on odd frames.

Once no full rows are found, the game will return to the `FALLING` state.

In this state, `hide_falling_piece` is asserted to prevent the (nonexistent) falling piece from being drawn.

## Timing

I use [an 800x600 @ 72Hz (50MHz) resolution](http://tinyvga.com/vga-timing/800x600@72Hz), but divide the pixel clock by 8.
This results in effectively a 100x600 @ 72Hz (6.25MHz) resolution that is horizontally scaled by 8.
This also means the system clock is 6.25 MHz.

Game tiles are shown on a 2 clock x 16 scanline grid, and most actions are aligned to this grid.

### Vertical Timing

There are 666 scanlines per frame.
They are divided up as follows:

```
Name:   | T Margin |    Matrix    | B Margin |  Processing  |      Unused      |
Length: |  1 * 16  |    20 * 16   |  3 * 16  |    1 * 16    | (not a multiple) |
        |<-------->|<------------>|<-------->|<------------>|<---------------->|
Tile:   0          1              21         24             25                 N/A
Line:   0          16             88         384            400                666
```

### Horizontal Timing

There are 1040 pixels per scanline, so 130 clock cycles.
Every gameplay scanline is split up into the following:

```
Name:   | L Margin |    Matrix    | R Margin |    Fetching    | Unused, Visible  | Unused, Blanking |
Length: |  1 * 2   |    10 * 2    |  1 * 2   |     10 * 2     |      28 * 2      |      15 * 2      |
        |<-------->|<------------>|<-------->|<-------------->|<---------------->|<---------------->|
Tile:   0          1              11         12               22                 50                 65
Cycle:  0          2              22         24               44                 100                130
```

## Modules

### `CollisionChecker`

Sets a flag if the falling block overlaps any tile on the matrix.
The flag is reset every frame, and isn't ready until all the tiles are drawn.