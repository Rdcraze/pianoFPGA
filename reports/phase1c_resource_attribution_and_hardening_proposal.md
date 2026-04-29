# Phase 1C Resource Attribution And Hardening Proposal

Task: `task-021ac5d1`  
Date: `2026-04-28`  
Role: `implementer`

## Scope

This is an analysis/proposal report for the hardware-accepted Phase 1 two-voice baseline.

No RTL, firmware, constraints, clocking, register-map behavior, Quartus project settings, or generated SOF files were changed for this task.

Required references reviewed:

- `reports/phase1_next_scaling_architecture_options.md`
- `reports/phase1_two_voice_hardware_acceptance_decision.md`
- `reports/phase1_two_voice_validation.md`
- `reports/phase1_two_voice_impl_report.md`

Additional evidence inspected:

- `quartus/phase0/output_files/piano_phase0_top.fit.rpt`
- `quartus/phase0/output_files/piano_phase0_top.map.rpt`
- `reports/phase1_timing_margin_impl_report.md`
- `reports/phase1_timing_margin_acceptance_decision.md`
- `fw/phase0/build/phase0.map`
- `rtl/audio/phase1_reduced_voice.v`
- `rtl/audio/phase0_audio_path.v`
- `rtl/control/phase0_control_regs.v`
- `rtl/control/phase0_rv32i_soc.v`
- `rtl/control/phase0_rv32i_core.v`
- `rtl/control/phase0_boot_rom.v`
- `rtl/control/phase0_data_ram.v`
- `fw/phase0/phase0_main.c`
- `fw/phase0/phase0_hw.h`

## Accepted Two-Voice Baseline

The accepted two-voice build remains:

| Metric | Value |
| --- | ---: |
| Logic elements | `7366 / 10320` |
| Dedicated registers | `3580` |
| Memory bits | `271360 / 423936` |
| M9Ks | `34 / 46` |
| DSP9 elements | `4 / 46` |
| PLLs | `1 / 2` |
| Slow-85C `sys_clk_50m` setup slack | `+3.957 ns` |
| Slow-85C `sys_clk_50m` hold slack | `+0.432 ns` |
| Slow-85C `sys_clk_50m` Fmax | `62.33 MHz` |

The hardware-accepted SOF is `quartus/phase0/output_files/piano_phase0_top.sof`, checksum `0x00553670`, SHA-256 `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`.

## Hierarchy Resource Attribution

Fitter hierarchy evidence from `piano_phase0_top.fit.rpt`:

| Hierarchy | Logic cells | Dedicated registers | Memory bits | M9Ks | DSP9 elements | Notes |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `piano_phase0_top` | `7366` | `3580` | `271360` | `34` | `4` | Accepted two-voice top |
| `phase0_rv32i_soc` | `3586` | `1278` | `262144` | `32` | `0` | Largest LE block and dominant M9K block |
| `phase0_rv32i_core` | `3423` | `1242` | `0` | `0` | `0` | Dominant control-plane LE/register block |
| `phase0_boot_rom` | `0` | `0` | `131072` | `16` | `0` | 4096 x 32 ROM |
| `phase0_data_ram` | `1` | `0` | `131072` | `16` | `0` | 4096 x 32 RAM |
| `phase0_audio_path` | `3019` | `1959` | `9216` | `2` | `4` | Includes both voices, mix, status, diagnostics |
| `phase1_reduced_voice` voice0 | `1316` | `843` | `4608` | `1` | `2` | One reduced voice engine |
| `phase1_reduced_voice` voice1 | `1316` | `843` | `4608` | `1` | `2` | Duplicated reduced voice engine |
| `phase0_audio_path` own glue | `387` | `273` | `0` | `0` | `0` | Mix/status/counter glue outside the two voice instances |
| `phase0_control_regs` | `542` | `172` | `0` | `0` | `0` | Register decode, control registers, readback mux |
| `wm8978_codec_stub` | `266` | `169` | `0` | `0` | `0` | Codec init/control/DAC/I2C wrapper |
| `phase0_uart_mmio` | `52` | `32` | `0` | `0` | `0` | CPU UART MMIO shell |
| `uart_tx` | `48` | `30` | `0` | `0` | `0` | UART transmitter under MMIO shell |

Interpretation:

- LE pressure is split mainly between the RV32I core and the duplicated audio voice path.
- The current two voice engines alone account for `2632` logic cells and `1686` registers, before mix/control/register glue.
- The complete audio path is `3019` logic cells, so the non-voice mix/status/counter glue inside `phase0_audio_path` is `387` logic cells and `273` registers.
- The current RV32I SoC accounts for `3586` logic cells, with `3423` in the CPU core itself.
- M9K pressure is not from the reduced voices. It is dominated by the current 16 KiB boot ROM and 16 KiB data RAM, which consume `32 / 34` used M9Ks.

## Memory And DSP Attribution

Fitter RAM details show:

| Memory | Logical shape | Logical bits | Physical M9Ks | Notes |
| --- | ---: | ---: | ---: | --- |
| Voice0 delay line `delay_line_rtl_0` | `128 x 18` | `2304` | `1` shared location | Packed with voice0 `delay_line_rtl_1` |
| Voice0 delay line `delay_line_rtl_1` | `128 x 18` | `2304` | `0` incremental | Shares the same physical M9K location |
| Voice1 delay line `delay_line_rtl_0` | `128 x 18` | `2304` | `1` shared location | Packed with voice1 `delay_line_rtl_1` |
| Voice1 delay line `delay_line_rtl_1` | `128 x 18` | `2304` | `0` incremental | Shares the same physical M9K location |
| Boot ROM | `4096 x 32` | `131072` | `16` | `phase0_fw.mif` |
| Data RAM | `4096 x 32` | `131072` | `16` | Current firmware has no `.data` or `.bss` payload |

DSP block details show two signed 18-bit multipliers, one per voice. Each maps to `2` DSP9 elements, so the accepted two-voice build uses `4` DSP9 elements total.

## Second-Voice Cost

The accepted timing-margin baseline was:

| Metric | Single-Voice Timing-Margin Baseline | Two-Voice Build | Delta |
| --- | ---: | ---: | ---: |
| Logic elements | `5683` | `7366` | `+1683` |
| Dedicated registers | `2588` | `3580` | `+992` |
| Memory bits | `266752` | `271360` | `+4608` |
| M9Ks | `33` | `34` | `+1` |
| DSP9 elements | `2` | `4` | `+2` |

The current hierarchy explains the delta well:

- A single reduced voice instance is `1316` logic cells, `843` registers, `4608` logical memory bits, `1` physical M9K, and `2` DSP9 elements.
- The remaining approximate second-voice overhead is about `+367` LEs and `+149` registers after subtracting the duplicated voice instance from the total two-voice delta.
- That residual overhead is consistent with extra voice1 enable/trigger/reset/clip paths, mix saturation/peak/clip logic, extra diagnostic counters, extra readback muxing, and UART-reporting-visible control/status plumbing.

## Source-Level Cost Drivers

The reduced voice kernel in `rtl/audio/phase1_reduced_voice.v` is intentionally sequential and DSP-backed. The large pieces are:

- one `(* ramstyle = "M9K" *)` 128-entry by 18-bit delay line per voice, packed as one physical M9K per voice;
- one signed 18 x 16 multiply datapath per voice, mapped to two DSP9 elements;
- a 32-entry by 18-bit `body_pipe` shift register per voice;
- a multi-state sample FSM for allpass, damping, gain, excitation, body mix, clipping, peak, and quiet detection;
- per-voice state registers for loop/filter/allpass/excitation/peak/clip/active bookkeeping.

The two-voice wrapper in `rtl/audio/phase0_audio_path.v` adds:

- two `phase1_reduced_voice` instances sharing the accepted coefficient inputs;
- signed 17-bit voice0 plus voice1 mix and Q1.15 saturation;
- voice0 counters: sample, trigger, active, valid;
- voice1 counters: trigger, active, valid;
- mix clip counter, sticky clip bit, and mix peak meter;
- status-word packing for voice0, voice1, and mix.

The register/control plane in `rtl/control/phase0_control_regs.v` adds a wide combinational readback mux through offset `0x6C`. The module is still moderate at `542` logic cells, but it will continue to grow if every scaling experiment adds a new full set of always-visible counters.

The RV32I SoC is the largest LE block. The current firmware is tiny, but the CPU and its fixed ROM/RAM envelope are deliberately more general than the present report loop:

- `fw/phase0/build/phase0.map` reports `.text = 0x37c` bytes.
- `.data` and `.bss` are both `0`.
- `phase0.bin` is `892` bytes.
- The linker currently reserves 16 KiB ROM and 16 KiB RAM.
- `phase0_boot_rom.v`, `phase0_data_ram.v`, and `fw/phase0/build.ps1` all assume MIF/BRAM depth `4096` words.

## Practical Third-Voice Outlook

Naively adding a third duplicated voice with the same observed second-voice delta projects to about:

| Metric | Two-Voice Build | Add One More Similar Voice | Estimated Three-Voice Build |
| --- | ---: | ---: | ---: |
| Logic elements | `7366` | `+1683` | `9049 / 10320` |
| Dedicated registers | `3580` | `+992` | `4572` |
| Memory bits | `271360` | `+4608` | `275968` |
| M9Ks | `34` | `+1` | `35 / 46` |
| DSP9 elements | `4` | `+2` | `6 / 46` |

On paper, M9K and DSP totals still fit. The risk is LE/routing margin: `9049 / 10320` is about 88% LE utilization before any additional scheduler, reporting, debug, or placement side effects. That is a poor default next implementation step without first reducing current overhead or setting strict stop criteria.

## Candidate Slice 1: Right-Size Firmware ROM/RAM

Goal:

Reduce M9K pressure without changing audio behavior, clocking, register behavior, UART behavior, or the CPU-out-of-sample-loop architecture.

Observation:

The current 16 KiB ROM plus 16 KiB RAM envelope consumes `32` of the `34` used M9Ks. Current firmware uses less than 1 KiB of ROM payload and has no `.data` or `.bss`.

Proposed work:

- Change the Phase 0 firmware memory envelope from fixed 4096-word ROM/RAM blocks to a measured, documented smaller depth with margin.
- Update `fw/phase0/link.ld`, `fw/phase0/phase0_hw.h`, `fw/phase0/build.ps1`, `rtl/control/phase0_boot_rom.v`, `rtl/control/phase0_data_ram.v`, and the SoC address decode coherently in one narrow task.
- Keep the CPU base addresses stable unless the orchestrator explicitly authorizes a visible memory-map change.
- Preserve the current firmware image behavior and UART/audio smoke outputs.

Estimated savings:

- Reducing each memory from `4096 x 32` to `1024 x 32` should reduce each from `16` M9Ks to about `4` M9Ks, for an estimated `24` M9K saving across ROM and RAM.
- This does not materially reduce LE count, but it changes the scaling headroom story from M9K-tight to M9K-comfortable.

Risk:

- Low to medium. The main risk is an inconsistent depth/address/MIF update rather than algorithmic behavior.
- Stack high-water is not currently measured. A small RAM depth needs either conservative margin or a lightweight stack sentinel test.

Verification burden:

- Firmware build.
- MIF depth/header/linker consistency check.
- ModelSim happy/NACK/voice tests.
- Quartus full compile and TimeQuest.
- Hardware UART/audio smoke, because boot memory changes are board-loadable control-path changes.

Explicit non-goals:

- No new voice.
- No SDRAM.
- No CPU ISA rewrite.
- No register-map behavior change.
- No audio-model change.

## Candidate Slice 2: Replace Per-Voice Body Shift Register With Bit-Exact Tap Storage

Goal:

Reduce per-voice register/LE pressure inside the reduced voice kernel while preserving the current two-voice sound and external behavior.

Observation:

Each `phase1_reduced_voice` includes `body_pipe [0:31]`, an 18-bit-wide, 32-stage shift register. That is 576 state bits per voice before associated muxing/fanout. The current two-voice build therefore carries about 1152 body-pipe register bits. This is a credible contributor to the `843` registers and `1316` logic cells per voice.

Proposed work:

- Replace the per-voice shift-register body pipe with a tap-addressed circular buffer or vendor shift-tap primitive that still produces the exact tap delays used today: taps 6, 16, and 30.
- Keep `body_bypass`, `body_mix_q15`, arithmetic order, saturation behavior, peak/clip behavior, and sample-valid timing bit-exact.
- Do not alter the waveguide delay line, loop parameters, excitation ROM, multiplier mapping, register map, or UART frames.

Estimated savings:

- Best case: recover a meaningful part of the two voices' `1152` body-pipe registers plus some associated shift/fanout LEs.
- Realistic first-pass target: at least several hundred registers and a smaller LE reduction, with exact savings determined only by Quartus.
- If implemented with M9K-backed storage, it could spend one or more M9Ks. This is much more attractive after Candidate Slice 1 frees memory blocks.

Risk:

- Medium. The change is local to the voice module, but it touches audio-state timing and must be bit-exact enough not to perturb the accepted sound unintentionally.
- Inference risk is real. An attempted memory/tap rewrite that maps poorly could increase LEs or break timing.

Verification burden:

- Standalone `phase1_reduced_voice_tb` should compare the existing signature and ideally add a sample-by-sample golden check over the first note.
- Top happy/NACK tests must preserve voice0/voice1 peaks, trigger counts, mix peak, and zero mix clip.
- Quartus full compile must confirm no async-read delay-line regression, DSP mapping preserved, and nonnegative setup/hold slack.
- Hardware UART/audio smoke is recommended because the sound engine itself changes internally even if behavior is intended to be preserved.

Explicit non-goals:

- No third voice.
- No scheduler.
- No richer physics.
- No coefficient/default changes.
- No register-map or UART-frame change.
- No CPU or memory-map changes in the same slice.

## Not Recommended As The Next Slice

Third duplicated voice:

- It would likely fit DSP/M9K totals but would push LE utilization to about 88% before extra debug/control growth.
- It would prove another duplication point, not a scalable architecture.
- It should wait until at least one current-baseline hardening pass lands or until the orchestrator sets strict stop criteria.

RV32I ISA pruning:

- The CPU core is the single largest LE block, but pruning RV32I support around the current firmware image weakens the architectural contract.
- If the control plane becomes the long-term LE bottleneck, it deserves a separate architecture task comparing a smaller custom controller, a stricter RV32I subset, and firmware/toolchain implications.
- It should not be mixed with audio scaling or memory right-sizing.

Broad diagnostic removal:

- The accepted hardware baseline depends on UART and register observability.
- Removing counters or changing register offsets would save some logic but would no longer preserve the current accepted debug contract.
- If a future product mode trims diagnostics, it should be a build-profile decision with separate acceptance criteria, not a hidden optimization.

SDRAM:

- SDRAM does not address current LE pressure and adds latency/controller/verification risk.
- Current immediate memory pressure is from oversized on-chip CPU ROM/RAM, not voice delay-line capacity.

## Recommended Next Step

Recommended order:

1. Run Candidate Slice 1 first to right-size ROM/RAM and recover M9Ks while preserving current two-voice behavior.
2. Then run Candidate Slice 2 only if the project wants a behavior-preserving LE/register reduction before considering a third voice or a scheduler.

This order separates a low-risk memory-envelope cleanup from a medium-risk audio-kernel rewrite. It also avoids using scarce implementation time on a third duplicated voice while the current accepted build still has clear, measurable overhead to remove.

## Commands Used

Read-only inspection commands used during this task:

```powershell
Get-Content reports\phase1_next_scaling_architecture_options.md
Get-Content reports\phase1_two_voice_hardware_acceptance_decision.md
Get-Content reports\phase1_two_voice_validation.md
Get-Content reports\phase1_two_voice_impl_report.md
Get-Content reports\phase1_timing_margin_impl_report.md
Get-Content reports\phase1_timing_margin_acceptance_decision.md
Select-String -Path quartus\phase0\output_files\piano_phase0_top.fit.rpt -Pattern "Resource|Hierarchy|Entity|Logic Elements|Dedicated logic|M9K|DSP|Total"
Select-String -Path quartus\phase0\output_files\piano_phase0_top.map.rpt -Pattern "Resource|Hierarchy|Entity|Logic Elements|Dedicated logic|M9K|DSP|Total"
Get-Content rtl\audio\phase1_reduced_voice.v
Get-Content rtl\audio\phase0_audio_path.v
Get-Content rtl\control\phase0_control_regs.v
Get-Content rtl\control\phase0_rv32i_soc.v
Get-Content rtl\control\phase0_boot_rom.v
Get-Content rtl\control\phase0_data_ram.v
Get-Content fw\phase0\phase0_main.c
Get-Content fw\phase0\phase0_hw.h
Get-Content fw\phase0\build\phase0.map
Get-ChildItem fw\phase0\build\phase0.*
```

No compile, simulation, programmer, or hardware capture command was run because this task was analysis/proposal only.

## Residual Uncertainties

- The report uses current Quartus hierarchy tables and existing acceptance reports; it does not contain new before/after implementation evidence.
- Estimated M9K savings for ROM/RAM right-sizing assume linear 32-bit memory packing similar to the current `4096 x 32` blocks. Quartus must confirm the exact result.
- Estimated LE/register savings for body tap storage are intentionally broad. They require an implementation experiment and bit-exact audio verification.
- Stack high-water is not measured today. Any RAM reduction should add either a sentinel check or conservative reserve.
- The third-voice projection assumes the third voice resembles the observed second-voice delta. Placement/routing effects near high LE utilization could make the real cost worse.
