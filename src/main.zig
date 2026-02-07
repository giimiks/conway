const std = @import("std");
const rl = @import("raylib");
const cg = @import("cell_grid.zig");
const Game_phase = enum { PREP, RUNNING };
const c = std.c;

fn handle_keyevents() void {
    return;
}

fn update_phase(phase: *Game_phase, _: cg.Cell_grid) anyerror!u8 {
    if (rl.isKeyReleased(rl.KeyboardKey.space)) {
        if (phase.* == Game_phase.PREP) {
            phase.* = Game_phase.RUNNING;
        } else {
            phase.* = Game_phase.PREP;
        }
    }
}

pub fn main() anyerror!u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var grid_w: u32 = 0;
    var grid_h: u32 = 0;

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 3) {
        std.debug.print("grid width and height not provided -> defaulting to 32x32\n", .{});
        grid_h = 32;
        grid_w = 32;
    } else {
        grid_w = std.fmt.parseInt(u32, args[1], 10) catch |err| {
            std.debug.print("{any}", .{err});
            return 0;
        };
        grid_h = std.fmt.parseInt(u32, args[2], 10) catch |err| {
            std.debug.print("{any}", .{err});
            return 1;
        };
    }
    if (grid_h == 0 or grid_w == 0) {
        std.debug.print("height or width can't be 0", .{});
        return 1;
    }

    defer std.process.argsFree(allocator, args);

    var cell_grid: cg.Cell_grid = cg.Cell_grid.init(grid_w, grid_h, allocator) catch |err| {
        std.debug.print("{any}", .{err});
        return 1;
    };
    defer cell_grid.deinit();

    const screen_width: i32 = 800;
    const screen_height: i32 = 450;

    rl.initWindow(screen_width, screen_height, "Conway");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const img: rl.Image = .{
        .data = @ptrCast(cell_grid.rgba32),
        .format = rl.PixelFormat.uncompressed_r8g8b8a8,
        .height = @bitCast(grid_h),
        .width = @bitCast(cell_grid.w_offset * 64),
        .mipmaps = 1,
    };
    const texture = rl.Texture.fromImage(img) catch |err| {
        std.debug.print("{any}", .{err});
        return 1;
    };

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.white);
        rl.drawTexture(texture, 0, 0, rl.Color.ray_white);
    }
    return 0;
}
