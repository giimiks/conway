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

inline fn update_rate(rate: f32) f32 {
    return 1.0 / rate;
}

pub fn main() anyerror!u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var grid_w: u32 = 32;
    var grid_h: u32 = 32;
    var update_time: f32 = 0.2;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        grid_w = std.fmt.parseInt(u32, args[1], 10) catch {
            std.debug.print("invalid grid width\n", .{});
            return 1;
        };
    }

    if (args.len > 2) {
        grid_h = std.fmt.parseInt(u32, args[2], 10) catch {
            std.debug.print("invalid grid height\n", .{});
            return 1;
        };
    }

    if (args.len > 3) {
        const rate = std.fmt.parseFloat(f32, args[3]) catch {
            std.debug.print("invalid update rate\n", .{});
            return 1;
        };
        update_time = 1.0 / rate;
    }

    if (grid_w == 0 or grid_h == 0) {
        std.debug.print("grid size must be > 0\n", .{});
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
    rl.setTargetFPS(0);
    rl.setConfigFlags(rl.ConfigFlags{
        .window_resizable = true,
    });

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

    var conway_frame_time: f32 = 0;
    while (!rl.windowShouldClose()) {
        const key = rl.getKeyPressed();
        const dt = rl.getFrameTime();
        conway_frame_time += dt;
        if (key == rl.KeyboardKey.r) {
            cell_grid.randomize();
            cell_grid.map_grid_to_rgba32();
            rl.updateTexture(texture, cell_grid.rgba32.ptr);
        }
        if (key == rl.KeyboardKey.space) {
            game_phase = Game_phase.RUNNING;
        }
        if (key == rl.KeyboardKey.q) {
            game_phase = Game_phase.PREP;
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
                    const flipped = cell_grid.flip_bit_at(gx, gy, cell_grid.grid);
                    if (flipped == true) {
                        cell_grid.alive_add(gx, gy) catch |err| {
                            std.debug.print("{any}", .{err});
                            return 1;
                        };
                    } else {
                        cell_grid.alive_delete(gx, gy);
                    }
                    cell_grid.map_grid_to_rgba32();
                    rl.updateTexture(texture, cell_grid.rgba32.ptr);
                }
            }
        } else {
            if (conway_frame_time >= update_time) {
                cell_grid.advance_life();

                cell_grid.map_grid_to_rgba32();
                rl.updateTexture(texture, cell_grid.rgba32.ptr);

                conway_frame_time = 0.0;
            }
        }
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);
        rl.drawTexturePro(texture, srect, drect, rl.Vector2.init(0.0, 0.0), 0.0, rl.Color.white);
        rl.drawFPS(screen_width - 100, 0);
    }
    return 0;
}
