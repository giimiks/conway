const std = @import("std");
const Allocator = std.mem.Allocator;

///Grid is a u64 array bitmap stored row-wise. Use .init() to initialise the grid safely with zeroed out memory. Use .deinit() to dealocate.
pub const Cell_grid = struct {
    width: u32,
    height: u32,
    ///Number of extra u64 elements needed to store the elements on each grid row.
    w_offset: u32,
    grid: []u64,
    rgba32: []u32,
    allocator: Allocator,
    pub fn init(width: u32, height: u32, allocator: Allocator) !Cell_grid {
        const w_offset = (width + 63) / 64;
        const self = Cell_grid{
            .width = width,
            .height = height,
            .w_offset = w_offset,
            .grid = try allocator.alloc(u64, w_offset * height),
            .rgba32 = try allocator.alloc(u32, w_offset * height * 64),
            .allocator = allocator,
        };
        @memset(self.grid, 0);
        @memset(self.rgba32, std.math.maxInt(u32));
        return self;
    }
    pub fn deinit(self: *Cell_grid) void {
        self.allocator.free(self.grid);
        self.allocator.free(self.rgba32);
    }
    ///Returns a bool representing the exact bit state of the element at x=w and y=h in the bitmap.
    pub fn get_bit_at(self: *Cell_grid, w: usize, h: usize) bool {
        const loc = self.get_bit_loc(w, h);
        return self.grid[loc.row_idx] & loc.mask != 0;
    }
    ///Returns the index of the exact u64 value containing the bit and its bit mask.
    fn get_bit_loc(self: *Cell_grid, w: usize, h: usize) struct { row_idx: usize, mask: usize } {
        return .{
            .row_idx = h * self.w_offset + (w / 64),
            .mask = (@as(u64, 1) << @intCast(w % 64)),
        };
    }
    ///Flips the bit at the specified x=w y=h location.
    pub fn flip_bit_at(self: *Cell_grid, w: usize, h: usize) bool {
        const loc = self.get_bit_loc(w, h);
        self.grid[loc.row_idx] = self.grid[loc.row_idx] ^ loc.mask;
        return (self.grid[loc.row_idx] & loc.mask) != 0;
    }
    fn buildByteLut(comptime alive: u32, comptime dead: u32) [256][8]u32 {
        var lut: [256][8]u32 = undefined;
        var b: usize = 0;
        while (b < 256) : (b += 1) {
            inline for (0..8) |i| {
                lut[b][i] = if (((b >> i) & 1) == 1) alive else dead;
            }
        }
        return lut;
    }

    pub fn map_grid_to_rgba32(self: *Cell_grid) void {
        const dead: u32 = 0xFFFFFFFF;
        const alive: u32 = 0xFF000000;
        const lut = comptime buildByteLut(alive, dead);

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
                    const entry = lut[byte];
                    const dst = self.rgba32[(px_base + k * 8)..(px_base + k * 8 + 8)];
                    inline for (0..8) |i| dst[i] = entry[i];
                }
            }
        }
    }
};
