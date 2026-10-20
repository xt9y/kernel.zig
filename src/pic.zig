// this is just a 8259 pic thing in zig, kinda defines only the constants the
// idt needs cause the actual remapping and masking is done in the kernel level
// which is pretty cool.eoi has to stay here cause it runs inside the isr tho,
// so somewhere the vm cant really do much
//
// see: https://wiki.osdev.org/8259_PIC

const port = @import("port.zig");

const MASTER_CMD: u16 = 0x20;
const SLAVE_CMD: u16 = 0xA0;
const EOI: u8 = 0x20; // end of interrupt command

pub const MASTER_OFFSET: u8 = 0x20; // irq0..7  -> vectors 0x20..0x27
pub const SLAVE_OFFSET: u8 = 0x28; // irq8..15 -> vectors 0x28..0x2f

// tell the pic were done. the slaves interrupts also need the master eoid
// since they arrive via the cascade
pub fn eoi(irq: u4) void {
    if (irq >= 8) port.outb(SLAVE_CMD, EOI); // irq 8..15 live on the slave pic
    port.outb(MASTER_CMD, EOI);
}

// Reprogram the dual 8259 PIC and enable PIT IRQ0 and COM1 IRQ4.
pub fn init() void {
    port.outb(0x20, 0x11);
    port.outb(0xA0, 0x11);
    port.outb(0x21, MASTER_OFFSET);
    port.outb(0xA1, SLAVE_OFFSET);
    port.outb(0x21, 0x04);
    port.outb(0xA1, 0x02);
    port.outb(0x21, 0x01);
    port.outb(0xA1, 0x01);
    port.outb(0x21, 0xEE); // IRQ0 and IRQ4
    port.outb(0xA1, 0xFF);
}
