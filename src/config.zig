// The importing application's build.zig creates a "kernel_config" options
// module. This file validates the complete chosen resource policy at compile
// time, preventing impossible or unsafe address layouts.
const opts = @import("kernel_config");
pub const heap_mib: usize = opts.heap_mib;
pub const boot_stack_mib: usize = opts.boot_stack_mib;
pub const max_tasks: usize = opts.max_tasks;
pub const process_code_pages: usize = opts.process_code_pages;
pub const user_stack_pages: usize = opts.user_stack_pages;
pub const kernel_stack_pages: usize = opts.kernel_stack_pages;
pub const max_syscall_write_bytes: usize = opts.max_syscall_write_bytes;
pub const pit_hz: u64 = opts.pit_hz;
pub const user_code_base: u64 = opts.user_code_base;
pub const user_stack_top: u64 = opts.user_stack_top;
pub const ata_secondary: bool = opts.ata_secondary;
pub const ata_slave: bool = opts.ata_slave;
pub const ata_spin_limit: u32 = opts.ata_spin_limit;

pub const page_size: u64 = 4096;
comptime {
    if (heap_mib < 1 or heap_mib > 1024) @compileError("heap-mib must be between 1 and 1024; allocation also requires contiguous physical memory");
    if (boot_stack_mib < 1 or boot_stack_mib > 1024) @compileError("boot-stack-mib must be between 1 and 1024");
    if (ata_spin_limit == 0) @compileError("ata-spin-limit must be positive");
    if (max_tasks < 2 or max_tasks > 256) @compileError("max-tasks must include PID 0 and be between 2 and 256");
    if (process_code_pages == 0 or user_stack_pages == 0 or kernel_stack_pages == 0)
        @compileError("process-code-pages, user-stack-pages, and kernel-stack-pages must be positive");
    if (process_code_pages > 65536 or user_stack_pages > 65536 or kernel_stack_pages > 256)
        @compileError("configured process or stack size exceeds the supported range");
    if (max_syscall_write_bytes == 0 or max_syscall_write_bytes > 16 * 1024 * 1024)
        @compileError("max-syscall-write-bytes must be within 1..16 MiB");
    if (pit_hz < 19 or pit_hz > 10000) @compileError("pit-hz must be between 19 and 10000");
    if (user_code_base < page_size or user_code_base % page_size != 0 or user_stack_top % page_size != 0)
        @compileError("user code base and stack top must be page aligned, and code base nonzero");
    if (user_code_base >= (@as(u64, 1) << 47) or user_stack_top >= (@as(u64, 1) << 47)) @compileError("user processes must stay in the canonical low address half");
    if (user_stack_top <= user_stack_pages * page_size)
        @compileError("user stack must fit below the configured stack top");
    // Leave at least one unmapped page as a guard between code and stack.
    if (user_code_base + process_code_pages * page_size + page_size >
        user_stack_top - user_stack_pages * page_size)
        @compileError("configured code, guard, and user stack regions overlap");
}
