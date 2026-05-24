# Phase 0 Firmware

This directory contains the smallest useful bare-metal firmware package for the planned Phase 0 RISC-V control subsystem.

Current intent:

- boot from small on-chip ROM
- use small on-chip RAM for stack/data
- exercise the existing audio control register block at `0x4000_0000`
- use a simple polling UART contract at `0x4000_1000`
- trigger a deterministic hardware-owned audio path rather than synthesize samples in software

Important limitation:

- the current RTL now boots this image through `rtl/control/phase0_rv32i_soc.v`, but the hardware control plane is still intentionally minimal rather than a general-purpose SoC
- the MMIO base addresses in `phase0_hw.h` are now the live integrated Phase 0 map and should stay stable unless there is a strong reason to change them

Files:

- `phase0_hw.h`: Phase 0 memory map, register offsets, UART contract, and MMIO helpers
- `start.S`: minimal RV32I reset entry, `.data` copy, `.bss` clear, and handoff to `phase0_main`
- `phase0_main.c`: codec-status polling, CPU-driven WM8978 follow-on writes, tone trigger, and UART debug loop
- `link.ld`: small on-chip ROM/RAM memory layout for early bring-up
- `build.ps1`: PowerShell build entry that emits `phase0.elf`, `phase0.bin`, `phase0.dis`, `phase0.map`, `phase0.mem`, and `phase0.mif`

Build:

```powershell
cd fw\phase0
.\build.ps1
```

`build.ps1` first looks for common prefixes on `PATH` and then falls back to the user-space xPack install root at `%APPDATA%\xPacks\@xpack-dev-tools\riscv-none-elf-gcc`.

If your toolchain uses a different prefix or lives somewhere else, pass it explicitly. Examples:

```powershell
.\build.ps1 -ToolPrefix riscv-none-elf-
.\build.ps1 -ToolPrefix riscv64-unknown-elf-
.\build.ps1 -ToolPrefix C:\toolchains\riscv\bin\riscv-none-elf-
```

The build script expects `gcc`, `objcopy`, and `objdump` for the chosen prefix to exist, either on `PATH` or under the explicit prefix path.

Build outputs used by the current RTL flow:

- `build/phase0.elf`
- `build/phase0.bin`
- `build/phase0.dis`
- `build/phase0.map`
- `build/phase0.mem`
- `build/phase0.mif`
- repo-root `phase0_fw.mif`
- `quartus/phase0/phase0_fw.mif`

The current ROM-init contract is `phase0_fw.mif`:

- Quartus consumes `quartus/phase0/phase0_fw.mif`
- ModelSim expects `phase0_fw.mif` to be visible from the simulator working directory; the validated repo flow runs simulation from the repo root
