# Phase 0 RISC-V Example Scout

Task: `task-9b569e17`  
Date: `2026-04-23`  
Audience: implementer for `task-9d00cc2f`

## Bottom Line

I did **not** find a true local bundled RISC-V, RV32, Nios, or other soft-core CPU example under `Manuals_Examples/`.

The local tree does contain:

- a planned Phase 0 RISC-V firmware package under `fw/phase0/`
- Phase 0 integration notes under `docs/phase0_impl_notes.md`
- vendor examples for:
  - UART blocks and pin bindings
  - Quartus ROM/RAM IP wrappers
  - SDRAM controller structure

That means the implementer should treat `fw/phase0/` plus the current RTL/doc contract as the authoritative local CPU-side baseline, and treat the vendor bundle only as a source of peripheral patterns and board pin examples.

## Search Result

I searched `Manuals_Examples/` for names and content matching:

- `riscv`, `risc-v`, `rv32`
- `nios`
- `softcore`, `soft-core`
- `cpu`, `processor`, `firmware`, `bootrom`

No hits produced an actual CPU subsystem, instruction memory wrapper, boot flow, bus fabric, or firmware-loading example. The bundle appears to be a peripheral/tutorial set, not a soft-core reference package.

## Best Local CPU-Side References

### 1. `fw/phase0/README.md`

This is the clearest statement of intended bring-up shape:

- small on-chip ROM boot
- small on-chip RAM for stack/data
- control block at `0x4000_0000`
- polling UART aperture at `0x4000_1000`
- hardware-owned audio path with firmware controlling registers, not synthesizing samples in software

It also states the current limitation explicitly: RTL still uses `phase0_soc_stub.v`, so the firmware package is a contract-first scaffold, not yet the executing on-chip subsystem.

### 2. `fw/phase0/start.S`

This is the minimal reset path the eventual soft-core integration needs to honor:

- set stack pointer
- copy `.data` from ROM load image into RAM
- clear `.bss`
- call `phase0_main`
- trap in an infinite loop if `phase0_main` returns

This is the strongest local hint for the expected ROM/RAM boot contract.

### 3. `fw/phase0/link.ld`

This is the cleanest local memory-layout reference:

- `OUTPUT_ARCH(riscv)`
- ROM at `0x0000_0000`, size `16 KiB`
- RAM at `0x0001_0000`, size `16 KiB`

If the implementer changes these addresses, they should treat that as an intentional contract change, not a hidden detail.

### 4. `fw/phase0/phase0_hw.h`

This is the current CPU/MMIO contract:

- `PHASE0_CTRL_BASE = 0x4000_0000`
- `PHASE0_UART_BASE = 0x4000_1000`
- control/status register offsets
- expected semantics for:
  - `CONTROL[8]` trigger strobe
  - `CONTROL[9]` codec-config valid pulse
  - `STATUS[31:24]` codec/audio state bits

For the implementer, this is the most important software-visible interface to preserve.

### 5. `fw/phase0/build.ps1`

This shows the intended toolchain and output shape:

- targets `rv32i` / `ilp32`
- emits:
  - `phase0.elf`
  - `phase0.bin`
  - `phase0.dis`
  - `phase0.map`
  - `phase0.mem`
- auto-detects common RISC-V GCC prefixes including `riscv-none-elf-`

Most important implementer implication: the eventual ROM path should accept a simple memory-init flow such as the generated `phase0.mem`, or there should be a clearly documented replacement.

### 6. `docs/phase0_impl_notes.md`

This remains the best integration-side source because it says the quiet part out loud:

- the current design still uses `rtl/control/phase0_soc_stub.v`
- the future task is to replace that stub with a real soft core plus instruction/data memory path
- the provisional Phase 0 CPU map is already documented and should be preserved unless there is a compelling reason to change it

For task planning, this document is the bridge between the intended firmware contract and the current board RTL.

## Nearest Useful Vendor Examples

These are not CPU examples, but they are the nearest reusable collateral in `Manuals_Examples/`.

### UART board hookup

`Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/21_rs232/quartus_prj/rs232.qsf`

Useful because it confirms:

- `PIN_E1` for `sys_clk`
- `PIN_M15` for reset
- `PIN_K8` / `PIN_M7` for one RS232 routing option
- commented `PIN_N6` / `PIN_N5` alternative that matches the board’s `UART1` / CH340 path discussed elsewhere in this repo

`Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/21_rs232/rtl/rs232.v`

Useful because it is the simplest local vendor UART top-level pattern from `50 MHz`, but it is still just a UART loopback shell, not a memory-mapped peripheral.

### ROM IP wrapper pattern

`Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/18_ip_core/rom/rtl/rom.v`

Useful because it shows the vendor’s Quartus ROM IP instantiation style (`rom_256x8`) and a very small top-level wrapper around a synchronous ROM.

Not useful as a CPU example:

- no instruction fetch
- no boot image integration
- no bus or execute path

### SDRAM controller structure

`Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/44_uart_sdram/rtl/uart_sdram.v`

`Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/44_uart_sdram/rtl/sdram/sdram_top.v`

Useful because they show:

- vendor clocking split for SDRAM
- FIFO-mediated access pattern into the SDRAM controller
- module boundaries for `sdram_top`, arbitration, init, read, and write

Not useful as a CPU example:

- no soft-core
- no bus fabric
- no instruction/data memory split
- UART is used as a byte stream source, not a CPU peripheral

## Recommended Reuse Strategy For The Implementer

Reuse directly:

- the CPU memory map from `fw/phase0/link.ld` and `fw/phase0/phase0_hw.h`
- the firmware boot assumptions from `fw/phase0/start.S`
- the generated memory-init expectation from `fw/phase0/build.ps1`
- the documented control/UART contract from `docs/phase0_impl_notes.md`

Reuse selectively:

- UART timing or pin-assignment ideas from the vendor `21_rs232` example
- Quartus ROM wrapper style from `18_ip_core/rom`
- SDRAM block partitioning ideas from `44_uart_sdram` only if later phases need SDRAM-backed buffering

Do not copy as architectural authority:

- any vendor tutorial top-level as a stand-in CPU subsystem
- the vendor ROM example as a boot ROM design
- the UART+SDRAM example as a bus or SoC template

## Practical Conclusion

There is no hidden local vendor soft-core example to anchor `task-9d00cc2f`.

The safest implementation path is:

1. preserve the already documented `fw/phase0` ROM/RAM/MMIO contract
2. replace `phase0_soc_stub.v` with the smallest real RV32-compatible subsystem that can execute that image
3. borrow only peripheral-level patterns from `Manuals_Examples/` where useful for Quartus IP packaging, UART hookup, or later SDRAM structure

That keeps the implementation aligned with the repo’s existing firmware and avoids inventing a second incompatible Phase 0 control-plane contract.
