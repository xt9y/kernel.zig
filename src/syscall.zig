// int 0x80 ABI for ring-3 processes: rax=0 exit, rax=1 write,
// rax=2 uptime ticks. All pointer arguments are validated within the
// caller's private user-mapped code or stack ranges.
const regs = @import("regs.zig");
const idt = @import("idt.zig");
const serial = @import("serial.zig");
const tasks = @import("tasks.zig");
const timer = @import("timer.zig");

const Frame = extern struct {
    r15: u64, r14: u64, r13: u64, r12: u64, r11: u64, r10: u64,
    r9: u64, r8: u64, rbp: u64, rdi: u64, rsi: u64, rdx: u64,
    rcx: u64, rbx: u64, rax: u64,
    rip: u64, cs: u64, rflags: u64, rsp: u64, ss: u64,
};
pub fn init() void {
    idt.setGate(0x80, @intFromPtr(&syscallStub), 3, 1);
}
export fn syscallStub() callconv(.naked) void {
    asm volatile (regs.PUSH_GPRS ++
        \\
        \\ mov %rsp, %rdi
        \\ call syscallHandler
        \\
        ++ regs.POP_GPRS ++
        \\
        \\ iretq
    );
}
export fn syscallHandler(frame: *Frame) callconv(.c) void {
    switch (frame.rax) {
        0 => { // exit
            _ = tasks.exitCurrent();
            asm volatile ("sti");
            while (true) asm volatile ("hlt");
        },
        1 => { // write(ptr, len)
            if (tasks.userReadable(frame.rdi, frame.rsi)) {
                const p: [*]const u8 = @ptrFromInt(frame.rdi);
                serial.write(p[0..@intCast(frame.rsi)]);
                frame.rax = frame.rsi;
            } else frame.rax = @bitCast(@as(i64, -1));
        },
        2 => frame.rax = timer.ticks(),
        else => frame.rax = @bitCast(@as(i64, -1)),
    }
}
