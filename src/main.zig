const std = @import("std");
const rl = @import("raylib");
const cg = @import("cell_grid.zig");
const Game_phase = enum { PREP, RUNNING };
const c = std.c;

fn get_scaling_factor(tw: f32, th: f32, sw: f32, sh: f32) f32 {
    return @min(sw / tw, sh / th);
}

fn scale_texture_to_screen(texture: rl.Texture, screen_w: i32, screen_h: i32) rl.Rectangle {
    const scale = get_scaling_factor(@as(f32, @floatFromInt(texture.width)), @as(f32, @floatFromInt(texture.height)), @as(f32, @floatFromInt(screen_w)), @as(f32, @floatFromInt(screen_h)));
    return rl.Rectangle.init(0, 0, @as(f32, @floatFromInt(texture.width)) * scale, @as(f32, @floatFromInt(texture.height)) * scale);
}

fn get_clicked_cell(mx: f32, my: f32, screen_w: i32, screen_h: i32, tex_w: u32, tex_h: u32) rl.Vector2 {
    const scale = get_scaling_factor(@floatFromInt(tex_w), @floatFromInt(tex_h), @floatFromInt(screen_w), @floatFromInt(screen_h));
    const pos_x = mx / scale;
    const pos_y = my / scale;
    return rl.Vector2{ .x = @floor(pos_x), .y = @floor(pos_y) };
}

fn conway_advance(celg: cg.Cell_grid) void {
    for (0..celg.width) |w| {
        for (0..celg.height) |h| {
            const cell = celg.get_bit_at(w, h);
            if (cell == true) {}
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

    const screen_width: i32 = 1280;
    const screen_height: i32 = 720;

    rl.initWindow(screen_width, screen_height, "Conway");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var game_phase = Game_phase.PREP;

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
    const srect = rl.Rectangle.init(0, 0, @as(f32, @floatFromInt(texture.width)), @as(f32, @floatFromInt(texture.height)));
    const drect = scale_texture_to_screen(texture, screen_width, screen_height);
    while (!rl.windowShouldClose()) {
        const key = rl.getKeyPressed();

        if (key == rl.KeyboardKey.space) {
            game_phase = Game_phase.RUNNING;
        }

        if (game_phase == Game_phase.PREP) {
            const clicked = rl.isMouseButtonPressed(rl.MouseButton.left);

            if (clicked == true) {
                const mouse_pos = rl.getMousePosition();
                const tex_w: u32 = cell_grid.w_offset * 64;
                const tex_h: u32 = grid_h;

                const cell_clicked = get_clicked_cell(mouse_pos.x, mouse_pos.y, screen_width, screen_height, tex_w, tex_h);
                const gx: usize = @intFromFloat(cell_clicked.x);
                const gy: usize = @intFromFloat(cell_clicked.y);

                if (gx < grid_w and gy < grid_h) {
                    _ = cell_grid.flip_bit_at(gx, gy);
                    cell_grid.map_grid_to_rgba32();
                    rl.updateTexture(texture, cell_grid.rgba32.ptr);
                }
            }
        } else {}
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);
        rl.drawTexturePro(texture, srect, drect, rl.Vector2.init(0.0, 0.0), 0.0, rl.Color.white);
    }
    return 0;
}
