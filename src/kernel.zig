// Public, language-independent kernel API.
pub const config = @import("config.zig");
pub const limine = @import("limine.zig");
pub const pmm = @import("pmm.zig");
pub const heap = @import("heap.zig");
pub const serial = @import("serial.zig");
pub const port = @import("port.zig");
pub const io = @import("io.zig");
pub const ata = @import("ata.zig");
pub const framebuffer = @import("framebuffer.zig");
pub const ps2 = @import("ps2.zig");
pub const timer = @import("timer.zig");
pub const tasks = @import("tasks.zig");
pub const gdt = @import("gdt.zig");
pub const idt = @import("idt.zig");
pub const pic = @import("pic.zig");
pub const syscall = @import("syscall.zig");
pub const vmm = @import("vmm.zig");

pub fn write(bytes: []const u8) void {
    serial.write(bytes);
}
pub fn readByte() ?u8 {
    return serial.readByte();
}
