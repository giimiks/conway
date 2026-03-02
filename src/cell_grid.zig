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

///Grid is a u64 array bitmap stored row-wise. Use .init() to initialise the grid safely with zeroed out memory. Use .deinit() to deallocate.
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
    ///Traverses neigbhbours and counts neighbours
    pub fn get_neighbour_count(self: *Cell_grid, x: u64, y: u64, grid: []u64) u8 {
        var neighbour_count: u8 = 0;

        for (0..3) |i| {
            if (neighbour_count > 3) break;
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
    fn halfAdd(a: u64, b: u64) struct { sum: u64, carry: u64 } {
        return .{
            .sum = a ^ b,
            .carry = a & b,
        };
    }

    fn fullAdd(a: u64, b: u64, c: u64) struct { sum: u64, carry: u64 } {
        const s = a ^ b ^ c;
        const carry = (a & b) | (a & c) | (b & c);
        return .{ .sum = s, .carry = carry };
    }
    inline fn load(grid: []u64, idx: usize, ok: bool) u64 {
        return if (ok) grid[idx] else 0;
    }

    inline fn lifeRule(mid: u64, bit0: u64, bit1: u64, bit2: u64) u64 {
        const is3 = (~bit2) & bit1 & bit0;
        const is2 = (~bit2) & bit1 & (~bit0);
        return is3 | (mid & is2);
    }
    ///Advance the next frame
    ///
    /// TODO: Make this use the list of alive cells
    pub fn advance_life(self: *Cell_grid) void {
        const h: usize = @intCast(self.height);
        const wpr: usize = @intCast(self.w_offset);
        const w: usize = @intCast(self.width);
        const rem: u6 = @intCast(w & 63);
        const last_mask: u64 = if (rem == 0) ~@as(u64, 0) else (@as(u64, 1) << rem) - 1;

        for (0..h) |y| {
            const row = y * wpr;

            const top_valid = y > 0;
            const bot_valid = (y + 1) < h;

            const top_row = if (top_valid) (y - 1) * wpr else 0;
            const bot_row = if (bot_valid) (y + 1) * wpr else 0;

            for (0..wpr) |xword| {
                const has_l = xword > 0;
                const has_r = (xword + 1) < wpr;

                const top_c = if (top_valid) self.grid[top_row + xword] else 0;
                const mid_c = self.grid[row + xword];
                const bot_c = if (bot_valid) self.grid[bot_row + xword] else 0;

                const top_l = if (top_valid and has_l) self.grid[top_row + (xword - 1)] else 0;
                const top_r = if (top_valid and has_r) self.grid[top_row + (xword + 1)] else 0;

                const mid_l = if (has_l) self.grid[row + (xword - 1)] else 0;
                const mid_r = if (has_r) self.grid[row + (xword + 1)] else 0;

                const bot_l = if (bot_valid and has_l) self.grid[bot_row + (xword - 1)] else 0;
                const bot_r = if (bot_valid and has_r) self.grid[bot_row + (xword + 1)] else 0;
                //Bit operation magic
                const top_left = (top_c << 1) | (top_r >> 63);
                const top_right = (top_c >> 1) | (top_l << 63);

                const mid_left = (mid_c << 1) | (mid_r >> 63);
                const mid_right = (mid_c >> 1) | (mid_l << 63);

                const bot_left = (bot_c << 1) | (bot_r >> 63);
                const bot_right = (bot_c >> 1) | (bot_l << 63);

                const a = top_left;
                const b = top_c;
                const c = top_right;
                const d = mid_left;
                const e = mid_right;
                const f = bot_left;
                const g = bot_c;
                const hh = bot_right;

                const s1 = fullAdd(a, b, c);
                const s2 = fullAdd(d, e, f);
                const s3 = halfAdd(g, hh);

                const s4 = fullAdd(s1.sum, s2.sum, s3.sum);
                const c1 = fullAdd(s1.carry, s2.carry, s3.carry);

                const bit0 = s4.sum;
                const bit1 = s4.carry ^ c1.sum;
                const bit2 = c1.carry;

                const is3 = (~bit2) & bit1 & bit0;
                const is2 = (~bit2) & bit1 & (~bit0);

                var next = is3 | (mid_c & is2);

                if (xword + 1 == wpr) next &= last_mask;

                self.next_grid[row + xword] = next;
            }
        }

        const tmp = self.grid;
        self.grid = self.next_grid;
        self.next_grid = tmp;
    }
    pub fn advance_life_par(self: *Cell_grid, low: usize, up: usize) void {
        const h: usize = @intCast(self.height);
        const wpr: usize = @intCast(self.w_offset);
        const w: usize = @intCast(self.width);
        const rem: u6 = @intCast(w & 63);
        const last_mask: u64 = if (rem == 0) ~@as(u64, 0) else (@as(u64, 1) << rem) - 1;

        const y_end = @min(up, h);

        for (low..y_end) |y| {
            const row = y * wpr;

            const top_valid = y > 0;
            const bot_valid = (y + 1) < h;

            const top_row = if (top_valid) (y - 1) * wpr else 0;
            const bot_row = if (bot_valid) (y + 1) * wpr else 0;

            for (0..wpr) |xword| {
                const has_l = xword > 0;
                const has_r = (xword + 1) < wpr;

                const top_c = if (top_valid) self.grid[top_row + xword] else 0;
                const mid_c = self.grid[row + xword];
                const bot_c = if (bot_valid) self.grid[bot_row + xword] else 0;

                const top_l = if (top_valid and has_l) self.grid[top_row + (xword - 1)] else 0;
                const top_r = if (top_valid and has_r) self.grid[top_row + (xword + 1)] else 0;

                const mid_l = if (has_l) self.grid[row + (xword - 1)] else 0;
                const mid_r = if (has_r) self.grid[row + (xword + 1)] else 0;

                const bot_l = if (bot_valid and has_l) self.grid[bot_row + (xword - 1)] else 0;
                const bot_r = if (bot_valid and has_r) self.grid[bot_row + (xword + 1)] else 0;

                const top_left = (top_c << 1) | (top_r >> 63);
                const top_right = (top_c >> 1) | (top_l << 63);

                const mid_left = (mid_c << 1) | (mid_r >> 63);
                const mid_right = (mid_c >> 1) | (mid_l << 63);

                const bot_left = (bot_c << 1) | (bot_r >> 63);
                const bot_right = (bot_c >> 1) | (bot_l << 63);

                const a = top_left;
                const b = top_c;
                const c = top_right;
                const d = mid_left;
                const e = mid_right;
                const f = bot_left;
                const g = bot_c;
                const hh = bot_right;

                const s1 = fullAdd(a, b, c);
                const s2 = fullAdd(d, e, f);
                const s3 = halfAdd(g, hh);

                const s4 = fullAdd(s1.sum, s2.sum, s3.sum);
                const c1 = fullAdd(s1.carry, s2.carry, s3.carry);

                const bit0 = s4.sum;
                const bit1 = s4.carry ^ c1.sum;
                const bit2 = c1.carry;

                const is3 = (~bit2) & bit1 & bit0;
                const is2 = (~bit2) & bit1 & (~bit0);

                var next = is3 | (mid_c & is2);

                if (xword + 1 == wpr) next &= last_mask;

                self.next_grid[row + xword] = next;
            }
        }
    }

    pub fn randomize(self: *Cell_grid) void {
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
        var random = prng.random();

        const total_words = self.w_offset * self.height;

        for (0..total_words) |i| {
            self.grid[i] = random.int(u64);
        }

        const remainder = self.width & 63;

        if (remainder != 0) {
            const mask: u64 = (@as(u64, 1) << @intCast(remainder)) - 1;

            for (0..self.height) |y| {
                const idx = y * self.w_offset + (self.w_offset - 1);
                self.grid[idx] &= mask;
            }
        }
    }
};
