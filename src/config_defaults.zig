// Default kernel resource policy. Consumers override these in their build.zig
// through the "kernel_config" options module; no Revo dependency lives here.
pub const heap_mib: usize = 64;
pub const boot_stack_mib: usize = 16;
pub const max_tasks: usize = 8; // includes the kernel task (PID 0)
pub const process_code_pages: usize = 1;
pub const user_stack_pages: usize = 4;
pub const kernel_stack_pages: usize = 4;
pub const max_syscall_write_bytes: usize = 4096;
pub const pit_hz: u64 = 100;
pub const user_code_base: u64 = 0x0040_0000;
pub const user_stack_top: u64 = 0x0080_0000;
pub const ata_secondary: bool = false;
pub const ata_slave: bool = false;
pub const ata_spin_limit: u32 = 1_000_000;
