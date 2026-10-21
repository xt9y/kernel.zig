// PS/2 controller (QEMU PC): capture raw set-1 keyboard scan bytes.
// No keymaps, text input, focus, repeats, or GUI decisions belong here.
const port = @import("port.zig");

const CAPACITY = 256; // Power of two; one slot is reserved.
var buffer: [CAPACITY]u8 = undefined;
var head: usize = 0;
var tail: usize = 0;

pub fn init() void {
    head = 0;
    tail = 0;
}

// IRQ1: enqueue bytes, including E0/E1 prefixes, make and break codes.
// Deliberately leave decoding and keyboard layout to userland (Revo).
pub fn onIrq() void {
    const write_pos: *volatile usize = &head;
    const read_pos: *volatile usize = &tail;
    // A bounded drain avoids hanging inside the IRQ on broken hardware.
    for (0..32) |_| {
        const status = port.inb(0x64);
        if (status & 1 == 0) break;
        const raw = port.inb(0x60);
        if (status & 0x20 != 0) continue; // PS/2 auxiliary (mouse) byte
        const next = (write_pos.* + 1) & (CAPACITY - 1);
        if (next == read_pos.*) continue; // Queue full; discard this byte
        buffer[write_pos.*] = raw;
        write_pos.* = next;
    }
}

// Called from the main kernel loop with interrupts temporarily disabled.
pub fn readScancode() ?u8 {
    const write_pos: *volatile usize = &head;
    const read_pos: *volatile usize = &tail;
    const pos = read_pos.*;
    if (pos == write_pos.*) return null;
    const raw = buffer[pos];
    read_pos.* = (pos + 1) & (CAPACITY - 1);
    return raw;
}
