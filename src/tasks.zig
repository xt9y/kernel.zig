// Minimal single-core ring-3 processes: one private code page and four stack pages.
// A process executes raw x86-64 position-independent code and uses int 0x80.
// The scheduler runs on PIT IRQ0; all guest code uses user-only low-half mappings.
const std = @import("std");
const Frame = @import("regs.zig").Frame;
const pmm = @import("pmm.zig");
const vmm = @import("vmm.zig");
const gdt = @import("gdt.zig");

pub const MAX: usize = 8;
pub const CODE_BASE: u64 = 0x0040_0000;
pub const STACK_TOP: u64 = 0x0080_0000;
pub const CODE_SIZE: usize = 4096;
const STACK_PAGES: usize = 4;
const KSTACK_SIZE: usize = 16 * 1024;
const State = enum(u8) { unused, ready, exited };

const Task = struct {
    state: State = .unused,
    cr3: u64 = 0,
    frame: Frame = std.mem.zeroes(Frame),
    kernel_stack: u64 = 0,
};

var tasks: [MAX]Task = @splat(.{});
var kstacks: [MAX][KSTACK_SIZE]u8 align(16) = undefined;
var active: usize = 0;

pub fn init() void {
    tasks[0] = .{ .state = .ready, .cr3 = vmm.activePml4() };
    active = 0;
}

pub fn current() u64 {
    return active;
}

pub fn count() u64 {
    var result: u64 = 0;
    for (tasks[1..]) |t| if (t.state == .ready) {
        result += 1;
    };
    return result;
}

pub fn state(pid: u64) u64 {
    if (pid >= MAX) return 0;
    return @intFromEnum(tasks[@intCast(pid)].state);
}

// Exited task slots can be reused once their private pages are reclaimed.
pub fn spawn(bytes: []const u8) ?u64 {
    if (bytes.len == 0 or bytes.len > CODE_SIZE) return null;
    var slot: usize = 1;
    while (slot < MAX and !(tasks[slot].state == .unused or (tasks[slot].state == .exited and tasks[slot].cr3 == 0))) : (slot += 1) {}
    if (slot == MAX) return null;

    const cr3 = vmm.createAddressSpace() orelse return null;
    const phys = pmm.alloc() orelse { vmm.destroyUserAddressSpace(cr3); return null; };
    const dst: [*]u8 = @ptrFromInt(pmm.physToVirt(phys));
    @memset(dst[0..pmm.PAGE_SIZE], 0);
    @memcpy(dst[0..bytes.len], bytes);
    if (!vmm.map(cr3, CODE_BASE, phys, vmm.USER)) {
        pmm.free(phys);
        vmm.destroyUserAddressSpace(cr3);
        return null;
    }

    for (0..STACK_PAGES) |index| {
        const frame = pmm.alloc() orelse { vmm.destroyUserAddressSpace(cr3); return null; };
        const stack_page: [*]u8 = @ptrFromInt(pmm.physToVirt(frame));
        @memset(stack_page[0..pmm.PAGE_SIZE], 0);
        const virt = STACK_TOP - (@as(u64, @intCast(index)) + 1) * pmm.PAGE_SIZE;
        if (!vmm.map(cr3, virt, frame, vmm.WRITE | vmm.USER)) {
            pmm.free(frame);
            vmm.destroyUserAddressSpace(cr3);
            return null;
        }
    }

    var frame = std.mem.zeroes(Frame);
    frame.rip = CODE_BASE;
    frame.cs = gdt.USER_CODE | 3;
    frame.ss = gdt.USER_DATA | 3;
    frame.rflags = 0x202;
    frame.rsp = STACK_TOP - 16;
    tasks[slot] = .{
        .state = .ready,
        .cr3 = cr3,
        .frame = frame,
        .kernel_stack = @intFromPtr(&kstacks[slot]) + KSTACK_SIZE,
    };
    return slot;
}

pub fn exitCurrent() bool {
    if (active == 0) return false;
    tasks[active].state = .exited;
    return true;
}

pub fn userReadable(ptr: u64, len: u64) bool {
    if (active == 0 or len > 4096) return false;
    const end = std.math.add(u64, ptr, len) catch return false;
    return (ptr >= CODE_BASE and end <= CODE_BASE + CODE_SIZE) or
        (ptr >= STACK_TOP - STACK_PAGES * pmm.PAGE_SIZE and end <= STACK_TOP);
}

pub fn tick(frame: *Frame) void {
    const previous = active;
    if (tasks[active].state == .ready) tasks[active].frame = frame.*;
    var next: usize = 0;
    for (1..MAX + 1) |delta| {
        const i = (active + delta) % MAX;
        if (tasks[i].state == .ready) {
            next = i;
            break;
        }
    }
    if (next == active) return;
    active = next;
    frame.* = tasks[next].frame;
    vmm.loadPml4(tasks[next].cr3);
    if (tasks[next].kernel_stack != 0) gdt.setKernelStack(tasks[next].kernel_stack);
    if (previous != 0 and tasks[previous].state == .exited) {
        vmm.destroyUserAddressSpace(tasks[previous].cr3);
        tasks[previous].cr3 = 0;
    }
}
