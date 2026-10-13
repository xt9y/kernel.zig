# kernel.zig

Minimal x86-64 freestanding Zig kernel runtime extracted from [Revel](https://github.com/hachem-wtf/revel) (MIT).

This repository is language-independent: it initializes the machine and exposes serial I/O and a heap to an application linked with the `app` Zig module. It uses Limine and runs headless via the COM1 UART. No window manager, graphics, or keyboard layout is built in.

The `os.rv` consumer links a Revo VM application; this kernel does not import Revo.

## Dependencies

Zig 0.17.0, Limine (recursive Git submodule), xorriso, and QEMU for testing the consumer.

Copyright (c) 2026 hachem. Reused MIT-licensed portions retain the original license in `LICENSE.revel`.
