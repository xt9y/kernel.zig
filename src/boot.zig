const std = @import("std");
const k = @import("kernel");
const app = @import("app");
const limine = k.limine;

pub const std_options_debug_threaded_io = null;
pub const std_options_debug_io: std.Io = k.io.debug_io;

pub const panic = std.debug.FullPanic(struct {
    fn halt(msg: []const u8, _: ?usize) noreturn {
        k.serial.init();
        k.write("\r\nKERNEL PANIC: ");
        k.write(msg);
        k.write("\r\n");
        while (true) asm volatile ("cli; hlt");
    }
}.halt);

export var base_revision: limine.BaseRevision linksection(".limine_requests") = limine.BaseRevision.init(3);
export var requests_start: limine.RequestsStartMarker linksection(".limine_requests_start") = .{};
export var requests_end: limine.RequestsEndMarker linksection(".limine_requests_end") = .{};
export var hhdm_request: limine.HhdmRequest linksection(".limine_requests") = .{};
export var memmap_request: limine.MemoryMapRequest linksection(".limine_requests") = .{};
export var stack_size_request: limine.StackSizeRequest linksection(".limine_requests") = .{
    .stack_size = 16 * 1024 * 1024,
};

fn enableSse() void {
    asm volatile (
        \\ mov %%cr0, %%rax
        \\ and $0xfffb, %%ax
        \\ or  $0x2, %%ax
        \\ mov %%rax, %%cr0
        \\ mov %%cr4, %%rax
        \\ or  $0x600, %%rax
        \\ mov %%rax, %%cr4
        ::: .{ .rax = true, .memory = true });
}

export fn _start() callconv(.c) noreturn {
    // Until IRQ handlers are installed this is a single-core, polled serial kernel.
    asm volatile ("cli");
    enableSse();
    k.serial.init();
    k.write("kernel.zig: serial ready\n");

    const hhdm_req: *volatile limine.HhdmRequest = &hhdm_request;
    const memmap_req: *volatile limine.MemoryMapRequest = &memmap_request;
    const hhdm = hhdm_req.response orelse @panic("no Limine HHDM");
    const memmap = memmap_req.response orelse @panic("no Limine memory map");
    k.pmm.init(hhdm, memmap);
    k.heap.init();
    k.write("kernel.zig: memory ready\n");

    app.boot(k.heap.allocator());
    while (true) {
        if (k.readByte()) |byte| {
            app.onInput(byte);
        } else {
            asm volatile ("pause");
        }
    }
}
