const std = @import("std");
const rl = @import("raylib");
const Allocator = std.mem.Allocator;

const ALIVE: u32 = 0xFF000000;
const DEAD: u32 = 0xFFFFFFFF;

fn buildByteLut() [256][8]u32 {
    var lut: [256][8]u32 = undefined;
    var b: usize = 0;
    @setEvalBranchQuota(3000);
    while (b < 256) : (b += 1) {
        inline for (0..8) |i| {
            lut[b][i] = if (((b >> i) & 1) == 1) ALIVE else DEAD;
        }
    }
    return lut;
}

const LUT = buildByteLut();

pub const Cell_xy = struct { x: u64, y: u64 };

///Grid is a u64 array bitmap stored row-wise. Use .init() to initialise the grid safely with zeroed out memory. Use .deinit() to dealocate.
pub const Cell_grid = struct {
    width: u32,
    height: u32,
    ///Number of extra u64 elements needed to store the elements on each grid row.
    w_offset: u32,
    grid: []u64,
    next_grid: []u64,
    rgba32: []u32,
    alive_cells: std.ArrayList(Cell_xy),
    allocator: Allocator,

    pub fn init(width: u32, height: u32, allocator: Allocator) !Cell_grid {
        const w_offset = (width + 63) / 64;
        const self = Cell_grid{
            .width = width,
            .height = height,
            .w_offset = w_offset,
            .grid = try allocator.alloc(u64, w_offset * height),
            .next_grid = try allocator.alloc(u64, w_offset * height),
            .rgba32 = try allocator.alloc(u32, w_offset * height * 64),
            .alive_cells = try std.ArrayList(Cell_xy).initCapacity(allocator, width * height),
            .allocator = allocator,
        };
        @memset(self.grid, 0);
        @memset(self.next_grid, 0);
        @memset(self.rgba32, std.math.maxInt(u32));
        return self;
    }
    pub fn deinit(self: *Cell_grid) void {
        self.allocator.free(self.grid);
        self.allocator.free(self.next_grid);
        self.allocator.free(self.rgba32);
        self.alive_cells.clearAndFree(self.allocator);
    }
    ///Returns a bool representing the exact bit state of the element at x=w and y=h in the bitmap.
    pub fn get_bit_at(self: *Cell_grid, w: usize, h: usize, grid: []u64) bool {
        const loc = self.get_bit_loc(w, h);
        return grid[loc.row_idx] & loc.mask != 0;
    }
    ///Returns the index of the exact u64 value containing the bit and its bit mask.
    fn get_bit_loc(self: *Cell_grid, w: usize, h: usize) struct { row_idx: usize, mask: usize } {
        return .{
            .row_idx = h * self.w_offset + (w / 64),
            .mask = (@as(u64, 1) << @intCast(w % 64)),
        };
    }
    ///Flips the bit at the specified x=w y=h location.
    pub fn flip_bit_at(self: *Cell_grid, w: usize, h: usize, grid: []u64) bool {
        const loc = self.get_bit_loc(w, h);
        grid[loc.row_idx] = grid[loc.row_idx] ^ loc.mask;
        return (grid[loc.row_idx] & loc.mask) != 0;
    }

    ///Maps cell grid to a rgba32 img using the comptime LUT
    pub fn map_grid_to_rgba32(self: *Cell_grid) void {
        const words_per_row: usize = self.w_offset;
        const rows: usize = self.height;

        for (0..rows) |y| {
            const word_row_base = y * words_per_row;
            const px_row_base = y * words_per_row * 64;
            for (0..words_per_row) |xw| {
                const word = self.grid[word_row_base + xw];
                const px_base = px_row_base + xw * 64;

                inline for (0..8) |k| {
                    const byte: u8 = @intCast((word >> @intCast(k * 8)) & 0xFF);
                    const entry = LUT[byte];
                    const dst = self.rgba32[(px_base + k * 8)..(px_base + k * 8 + 8)];
                    inline for (0..8) |i| dst[i] = entry[i];
                }
            }
        }
    }
    ///Adds cell at xy to the alive list
    pub fn alive_add(self: *Cell_grid, x: u64, y: u64) !void {
        try self.alive_cells.append(self.allocator, .{ .x = x, .y = y });
    }
    ///Removes alive cell at xy from the alive list, swaps with last item
    pub fn alive_delete(self: *Cell_grid, x: u64, y: u64) void {
        for (self.alive_cells.items, 0..self.alive_cells.items.len) |cell, i| {
            if (cell.x == x and cell.y == y) {
                _ = self.alive_cells.swapRemove(i);
                break;
            }
        }
    }

    pub fn get_neighbour_count(self: *Cell_grid, x: u64, y: u64, grid: []u64) u8 {
        var neighbour_count: u8 = 0;

        for (0..3) |i| {
            const offs_x_i: i64 = @as(i64, @intCast(x)) + @as(i64, @intCast(i)) - 1;
            if (offs_x_i < 0 or offs_x_i >= self.width) continue;
            const offs_x: u64 = @intCast(offs_x_i);

            for (0..3) |j| {
                const offs_y_i: i64 = @as(i64, @intCast(y)) + @as(i64, @intCast(j)) - 1;
                if (offs_y_i < 0 or offs_y_i >= self.height) continue;
                const offs_y: u64 = @intCast(offs_y_i);

                if (offs_x == x and offs_y == y) continue;

                if (self.get_bit_at(offs_x, offs_y, grid)) {
                    neighbour_count += 1;
                }
            }
        }

        return neighbour_count;
    }
    ///Advance the next frame
    pub fn advance_life(self: *Cell_grid) void {
        @memcpy(self.next_grid, self.grid);

        for (0..self.width) |x| {
            for (0..self.height) |y| {
                const nc = self.get_neighbour_count(x, y, self.grid);
                const alive = self.get_bit_at(x, y, self.grid);

                if (alive) {
                    if (nc < 2 or nc > 3) {
                        _ = self.flip_bit_at(x, y, self.next_grid);
                    }
                } else {
                    if (nc == 3) {
                        _ = self.flip_bit_at(x, y, self.next_grid);
                    }
                }
            }
        }

        @memcpy(self.grid, self.next_grid);
    }
};
