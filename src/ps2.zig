// Minimal IRQ1 PS/2 set-1 keyboard. Hardware decoding stays in the kernel;
// screen, layout policy and terminal state belong to the Revo application.
const port = @import("port.zig");
const CAPACITY = 256;
var fifo: [CAPACITY]u8 = undefined;
var head: usize = 0;
var tail: usize = 0;
var left_shift = false;
var right_shift = false;
var caps_lock = false;
var extended = false;

pub fn init() void {
    head = 0;
    tail = 0;
    left_shift = false;
    right_shift = false;
    caps_lock = false;
    extended = false;
    // The PC BIOS/Limine PS/2 controller initializes translation to set 1.
    // The PIC unmasks IRQ1; QEMU's i8042 emits keyboard interrupts.
}

pub fn onIrq() void {
    const write_pos: *volatile usize = &head;
    const read_pos: *volatile usize = &tail;
    while (true) {
        const status = port.inb(0x64);
        if ((status & 1) == 0) break;
        const scancode = port.inb(0x60);
        if ((status & 0x20) != 0) continue; // mouse port
        const next = (write_pos.* + 1) & (CAPACITY - 1);
        if (next != read_pos.*) {
            fifo[write_pos.*] = scancode;
            write_pos.* = next;
        }
    }
}

fn pop() ?u8 {
    const write_pos: *volatile usize = &head;
    const read_pos: *volatile usize = &tail;
    const pos = read_pos.*;
    if (pos == write_pos.*) return null;
    const value = fifo[pos];
    read_pos.* = (pos + 1) & (CAPACITY - 1);
    return value;
}

// German QWERTZ ASCII subset. Extended keys and non-ASCII keys can be
// exposed through a future keyboard-event API without changing this ABI.
fn key(code: u8, shifted: bool) ?u8 {
    return switch (code) {
        0x01 => 27,
        0x0e => 8,
        0x1c => 10,
        0x39 => ' ',
        0x02 => if (shifted) '!' else '1',
        0x03 => if (shifted) '"' else '2',
        0x04 => if (shifted) '#' else '3',
        0x05 => if (shifted) '$' else '4',
        0x06 => if (shifted) '%' else '5',
        0x07 => if (shifted) '&' else '6',
        0x08 => if (shifted) '/' else '7',
        0x09 => if (shifted) '(' else '8',
        0x0a => if (shifted) ')' else '9',
        0x0b => if (shifted) '=' else '0',
        0x0c => if (shifted) '?' else '-',
        0x0d => if (shifted) '`' else '\\',
        0x10 => if (shifted) 'Q' else 'q',
        0x11 => if (shifted) 'W' else 'w',
        0x12 => if (shifted) 'E' else 'e',
        0x13 => if (shifted) 'R' else 'r',
        0x14 => if (shifted) 'T' else 't',
        0x15 => if (shifted) 'Z' else 'z',
        0x16 => if (shifted) 'U' else 'u',
        0x17 => if (shifted) 'I' else 'i',
        0x18 => if (shifted) 'O' else 'o',
        0x19 => if (shifted) 'P' else 'p',
        0x1a => if (shifted) '{' else '[',
        0x1b => if (shifted) '}' else ']',
        0x1e => if (shifted) 'A' else 'a',
        0x1f => if (shifted) 'S' else 's',
        0x20 => if (shifted) 'D' else 'd',
        0x21 => if (shifted) 'F' else 'f',
        0x22 => if (shifted) 'G' else 'g',
        0x23 => if (shifted) 'H' else 'h',
        0x24 => if (shifted) 'J' else 'j',
        0x25 => if (shifted) 'K' else 'k',
        0x26 => if (shifted) 'L' else 'l',
        0x27 => if (shifted) ':' else ';',
        0x28 => if (shifted) '*' else '\'',
        0x29 => if (shifted) '^' else '#',
        0x2b => if (shifted) '\'' else '+',
        0x2c => if (shifted) 'Y' else 'y',
        0x2d => if (shifted) 'X' else 'x',
        0x2e => if (shifted) 'C' else 'c',
        0x2f => if (shifted) 'V' else 'v',
        0x30 => if (shifted) 'B' else 'b',
        0x31 => if (shifted) 'N' else 'n',
        0x32 => if (shifted) 'M' else 'm',
        0x33 => if (shifted) ';' else ',',
        0x34 => if (shifted) ':' else '.',
        0x35 => if (shifted) '_' else '-',
        0x56 => if (shifted) '>' else '<',
        else => null,
    };
}

pub fn readChar() ?u8 {
    while (pop()) |raw| {
        if (raw == 0xe0 or raw == 0xe1) {
            extended = true;
            continue;
        }
        if (extended) {
            extended = false;
            continue;
        }

        const released = (raw & 0x80) != 0;
        const code = raw & 0x7f;
        switch (code) {
            0x2a => { left_shift = !released; continue; },
            0x36 => { right_shift = !released; continue; },
            0x3a => { if (!released) caps_lock = !caps_lock; continue; },
            else => {},
        }
        if (released) continue;
        const shifted = left_shift or right_shift;
        const letter = switch (code) {
            0x10...0x19, 0x1e...0x26, 0x2c...0x32 => true,
            else => false,
        };
        if (key(code, if (letter) shifted != caps_lock else shifted)) |char| {
            // The terminal shell currently handles only printable ASCII,
            // newline and backspace. Ignore Esc until an event API exists.
            if (char == 27) continue;
            return char;
        }
    }
    return null;
}
