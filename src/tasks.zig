// Single-core, timer-preempted ring-3 tasks with configurable memory regions.
// Executables are raw position-independent x86-64 bytes, not ELF images.
const std = @import("std");
const Frame = @import("regs.zig").Frame;
const pmm = @import("pmm.zig");
const vmm = @import("vmm.zig");
const gdt = @import("gdt.zig");
const heap = @import("heap.zig");
const config = @import("config.zig");

pub const MAX: usize = config.max_tasks; // includes kernel task PID 0
pub const CODE_BASE: u64 = config.user_code_base;
pub const STACK_TOP: u64 = config.user_stack_top;
pub const CODE_SIZE: usize = config.process_code_pages * pmm.PAGE_SIZE;
const KSTACK_SIZE: usize = config.kernel_stack_pages * pmm.PAGE_SIZE;
const STACK_BYTES: u64 = config.user_stack_pages * pmm.PAGE_SIZE;
const State = enum(u8) { unused, ready, exited };

const Task = struct {
    state: State = .unused,
    cr3: u64 = 0,
    frame: Frame = std.mem.zeroes(Frame),
    kernel_stack: u64 = 0,
    stack_memory: ?[]u8 = null,
    code_pages: usize = 0,
};

var tasks: [MAX]Task = @splat(.{});
var active: usize = 0;
var ready_users: usize = 0;
var has_exited: bool = false;

pub fn init() void {
    tasks[0] = .{ .state = .ready, .cr3 = vmm.activePml4() };
    active = 0;
    ready_users = 0;
    has_exited = false;
}
pub fn current() u64 {
    return active;
}
pub fn count() u64 {
    const ready: *volatile usize = &ready_users;
    return ready.*;
}
pub fn state(pid: u64) u64 {
    if (pid >= MAX) return 0;
    return @intFromEnum(tasks[@intCast(pid)].state);
}

// This runs in the kernel event loop, not inside the timer interrupt.
// Never free a user kernel stack while the interrupt handler is using it.
pub fn reapExited() void {
    const pending: *volatile bool = &has_exited;
    if (!pending.*) return;
    // Clear before sweeping; an exit during the sweep sets it again.
    pending.* = false;
    for (tasks[1..]) |*task| {
        if (task.state != .exited or task.cr3 == 0) continue;
        vmm.destroyUserAddressSpace(task.cr3);
        if (task.stack_memory) |stack| heap.allocator().free(stack);
        task.* = .{};
    }
}

pub fn spawn(bytes: []const u8) ?u64 {
    if (bytes.len == 0 or bytes.len > CODE_SIZE) return null;
    var slot: usize = 1;
    while (slot < MAX and tasks[slot].state != .unused) : (slot += 1) {}
    if (slot == MAX) return null;

    const cr3 = vmm.createAddressSpace() orelse return null;
    const code_pages = (bytes.len + pmm.PAGE_SIZE - 1) / pmm.PAGE_SIZE;
    for (0..code_pages) |index| {
        const phys = pmm.alloc() orelse {
            vmm.destroyUserAddressSpace(cr3);
            return null;
        };
        const page: [*]u8 = @ptrFromInt(pmm.physToVirt(phys));
        @memset(page[0..pmm.PAGE_SIZE], 0);
        const begin = index * pmm.PAGE_SIZE;
        const length = @min(pmm.PAGE_SIZE, bytes.len - begin);
        @memcpy(page[0..length], bytes[begin..][0..length]);
        if (!vmm.mapInactive(cr3, CODE_BASE + index * pmm.PAGE_SIZE, phys, vmm.USER)) {
            pmm.free(phys);
            vmm.destroyUserAddressSpace(cr3);
            return null;
        }
    }

    for (0..config.user_stack_pages) |index| {
        const phys = pmm.alloc() orelse {
            vmm.destroyUserAddressSpace(cr3);
            return null;
        };
        const page: [*]u8 = @ptrFromInt(pmm.physToVirt(phys));
        @memset(page[0..pmm.PAGE_SIZE], 0);
        const address = STACK_TOP - (@as(u64, @intCast(index)) + 1) * pmm.PAGE_SIZE;
        if (!vmm.mapInactive(cr3, address, phys, vmm.WRITE | vmm.USER)) {
            pmm.free(phys);
            vmm.destroyUserAddressSpace(cr3);
            return null;
        }
    }

    // Allocate privileged stacks only for active processes. The heap already
    // guarantees 16-byte alignment, and KSTACK_SIZE is page-aligned.
    const stack = heap.allocator().alloc(u8, KSTACK_SIZE) catch {
        vmm.destroyUserAddressSpace(cr3);
        return null;
    };

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
        .kernel_stack = @intFromPtr(stack.ptr) + stack.len,
        .stack_memory = stack,
        .code_pages = code_pages,
    };
    ready_users += 1;
    return slot;
}

pub fn exitCurrent() bool {
    if (active == 0 or tasks[active].state != .ready) return false;
    tasks[active].state = .exited;
    ready_users -= 1;
    const pending: *volatile bool = &has_exited;
    pending.* = true;
    return true;
}

pub fn userReadable(ptr: u64, len: u64) bool {
    if (active == 0 or len == 0 or len > config.max_syscall_write_bytes) return false;
    const end = std.math.add(u64, ptr, len) catch return false;
    const code_end = CODE_BASE + tasks[active].code_pages * pmm.PAGE_SIZE;
    return (ptr >= CODE_BASE and end <= code_end) or
        (ptr >= STACK_TOP - STACK_BYTES and end <= STACK_TOP);
}

pub fn tick(frame: *Frame) void {
    const ready: *volatile usize = &ready_users;
    if (active == 0 and ready.* == 0) return;
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
}
