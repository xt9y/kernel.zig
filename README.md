# kernel.zig

Minimal, language-independent freestanding x86-64 kernel derived from
[Revel](https://github.com/hachem-wtf/revel), under its MIT license.

The kernel provides Limine boot, physical memory allocation, a contiguous
free-list heap, COM1 serial I/O, GDT/IDT/PIC, PIT timer, protected ring-3
tasks and a raw x86-64 process loader, a simple ATA PIO interface, and
optional framebuffer pixel access. It does not implement a filesystem,
ELF loader, keyboard, or window manager.

## Consumer-owned kernel configuration

The **consumer's** Zig `build.zig` supplies a module named `kernel_config`.
The defaults live in [src/config_defaults.zig](src/config_defaults.zig), and
[src/config.zig](src/config.zig) validates the build-time settings. Consumers
never need to edit the submodule to tune resource policy.

The [os.rv](https://github.com/xt9y/os.rv) consumer supplies the module via
`kernel.config.zig` and accepts the following `zig build -D...` overrides:

| Flag | Default | Meaning |
| --- | ---: | --- |
| `-Dheap-mib=...` | 64 | Contiguous heap size, MiB |
| `-Dboot-stack-mib=...` | 16 | Limine initial kernel stack, MiB |
| `-Dmax-tasks=...` | 8 | Total task table entries, including PID 0 |
| `-Dprocess-code-pages=...` | 1 | Maximum raw process image in 4 KiB pages |
| `-Duser-stack-pages=...` | 4 | Stack pages in each user address space |
| `-Dkernel-stack-pages=...` | 4 | Privileged stack pages allocated per process |
| `-Dmax-syscall-write-bytes=...` | 4096 | Maximum bytes in one write syscall |
| `-Dpit-hz=...` | 100 | PIT interrupt rate |
| `-Duser-code-base=...` | 4194304 | Page-aligned raw program virtual address |
| `-Duser-stack-top=...` | 8388608 | Page-aligned process stack top |
| `-Data-secondary=true` | false | Use secondary legacy ATA bus |
| `-Data-slave=true` | false | Use slave device on selected bus |
| `-Data-spin-limit=...` | 1000000 | ATA I/O polling deadline (iterations) |

These are **build-time** settings. Limits are checked for plausible values and
nonoverlapping user memory regions. A bigger process image now maps multiple
physical pages; task privileged stacks are allocated only when a task starts
and are reclaimed after exit outside the interrupt handler. Allocation failure
is still possible. The heap still needs a sufficiently large **contiguous**
physical memory region.

Only these existing resource restrictions are configurable. The current raw
program format (not ELF), ring-3 syscall ABI (exit / write / time), 512-byte
ATA sectors, 28-bit LBA mode, single-core scheduler, 32-bit RGB framebuffer
requirement and serial terminal remain as before. Kernel-stack and code
addresses used by hand-written user machine code must agree with the config.

## Requirements

Zig 0.17.0, a Limine submodule, QEMU, and xorriso for the
[os.rv](https://github.com/xt9y/os.rv) consumer.

The original MIT copyright notice is preserved in [LICENSE.revel](LICENSE.revel).
