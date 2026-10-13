// 8253/8254 PIT channel 0, using IRQ0 at 100 Hz.
const port = @import("port.zig");
pub const HZ: u64 = 100;
var counter: u64 = 0;

pub fn init() void {
    const divisor: u16 = @intCast(1_193_182 / HZ);
    port.outb(0x43, 0x36); // channel 0, lo/hi, square wave
    port.outb(0x40, @truncate(divisor));
    port.outb(0x40, @truncate(divisor >> 8));
}
pub fn onIrq() void {
    const p: *volatile u64 = &counter;
    p.* +%= 1;
}
pub fn ticks() u64 {
    const p: *volatile u64 = &counter;
    return p.*;
}
pub fn millis() u64 {
    return ticks() * 1000 / HZ;
}
