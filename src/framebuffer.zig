const limine = @import("limine.zig");

export var request: limine.FramebufferRequest linksection(".limine_requests") = .{};

pub const Info = struct { width: u64, height: u64, pitch: u64, bpp: u16 };

fn device() ?*limine.Framebuffer {
    const req: *volatile limine.FramebufferRequest = &request;
    const res = req.response orelse return null;
    if (res.framebuffer_count == 0) return null;
    const fb = res.framebuffers.?[0];
    if (fb.bpp != 32 or fb.memory_model != 1) return null;
    if (fb.width == 0 or fb.height == 0 or fb.pitch < fb.width * 4) return null;
    return fb;
}

pub fn info() ?Info {
    const fb = device() orelse return null;
    return .{ .width = fb.width, .height = fb.height, .pitch = fb.pitch, .bpp = fb.bpp };
}

// rgb is 0xRRGGBB; the VESA bit masks define the actual framebuffer channel order.
fn packedColor(fb: *limine.Framebuffer, rgb: u32) u32 {
    const r = (rgb >> 16) & 255;
    const g = (rgb >> 8) & 255;
    const b = rgb & 255;
    return (r << @as(u5, @intCast(fb.red_mask_shift))) |
        (g << @as(u5, @intCast(fb.green_mask_shift))) |
        (b << @as(u5, @intCast(fb.blue_mask_shift)));
}

fn store(p: [*]u8, color: u32) void {
    p[0] = @truncate(color);
    p[1] = @truncate(color >> 8);
    p[2] = @truncate(color >> 16);
    p[3] = @truncate(color >> 24);
}

pub fn pixel(x: u64, y: u64, rgb: u32) bool {
    const fb = device() orelse return false;
    if (x >= fb.width or y >= fb.height) return false;
    const pos: usize = @intCast(y * fb.pitch + x * 4);
    store(fb.address + pos, packedColor(fb, rgb));
    return true;
}

pub fn clear(rgb: u32) bool {
    const fb = device() orelse return false;
    const color = packedColor(fb, rgb);
    for (0..@intCast(fb.height)) |y| {
        const row = fb.address + y * @as(usize, @intCast(fb.pitch));
        for (0..@intCast(fb.width)) |x| {
            store(row + x * 4, color);
        }
    }
    return true;
}
