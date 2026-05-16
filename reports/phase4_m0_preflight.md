# Phase 4 M0 SDRAM and Headroom Preflight

Date: 2026-05-16
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-0448be7a`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `7ee07d7`

Sources:
- `reports/phase3_exit_phase4_readiness.md`
- `docs/project_brief.md`
- `docs/board_capabilities_report.md`
- `docs/manual_audio_example_report.md`
- `quartus/phase0/output_files/piano_phase0_top.fit.summary` (LE 9,992 / 10,320, 97 percent)
- `quartus/phase0/output_files/piano_phase0_top.sta.summary` (slow-85C setup +2.914 ns)
- `Manuals_Examples/[野火]征途_Pro开发板硬件规格书V1.0.1.pdf` (board hardware spec)
- `Manuals_Examples/EBF EP4CE10 Pro/征途_PRO_EBF410202v1_SCH_20230915_原理图.pdf` (schematic)
- `Manuals_Examples/硬件数据手册/w9825g6kh_a04.pdf` (W9825G6KH datasheet)
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/44_uart_sdram/` (canonical SDRAM example)
- `Manuals_Examples/ebf_ep4ce10_pro_tutorial_code_20250614/48_audio_record/` (WM8978 + SDRAM example)

## TL;DR

**Recommendation: reclamation-first, with SDRAM held until a specific audible-win candidate justifies it.**

The board carries a real Winbond W9825G6KH 256 Mbit SDRAM on dedicated FPGA pins, and the local `44_uart_sdram` example proves a working controller costs only ~735 LE / ~32 KiB M9K / 1 PLL with timing closed. That is technically affordable in the abstract, but the current Phase 3 baseline already sits at 9,992 / 10,320 LE (97 percent) with no realistic on-chip headroom for adding even a small controller, let alone a controller plus the audio-path features the controller would feed. The local audio-plus-SDRAM example `48_audio_record` confirms the headline LE cost of pairing them (~965 LE total) but ships with negative slack on `audio_bclk`, so it cannot be copied as a timing-clean reference either.

Phase 4 must therefore:

1. Recover headroom on-chip first (Phase 4 M1 reclamation scope, paper only).
2. Identify a specific audio feature whose audible payoff actually requires off-chip memory.
3. Only then revisit SDRAM as a deliberate, measured Phase 4 milestone.

Doing it in the other order risks committing 7-9 percent of the device to an SDRAM controller that has no consumer.

## 1. SDRAM Board Facts

### Chip and topology

| Item | Value | Source |
| --- | --- | --- |
| Part | Winbond `W9825G6KH-6` | `硬件规格书` p. 10, schematic p. 6 |
| Total density | 256 Mbit (32 MiB effective) | datasheet p. 1 |
| Organization | 4M words x 4 banks x 16 bits | datasheet p. 3 |
| Data bus | 16 bits | schematic p. 6 |
| Speed grade | -6, 166 MHz / CL3 | datasheet p. 3 |
| Package | TSOPII-54 | datasheet p. 1 |

There is exactly one SDRAM device on the board. It is a single rank, single chip select.

### Pin and bank usage (from `44_uart_sdram` accepted reference)

The vendor example pins map the controller as follows:

| Signal group | Pins | Count |
| --- | --- | --- |
| Control (CLK, CKE, CS_n, RAS_n, CAS_n, WE_n) | R4, R9, R12, R11, R10, L9 | 6 |
| Bank address `BA[1:0]` | R13, R14 | 2 |
| Row/column `ADDR[12:0]` | M11, N12, T15, P9, T10, T11, T12, T13, T14, N11, N9, P14, P11 | 13 |
| Data `DQ[15:0]` | T2, T3, T4, T5, T6, T7, T8, P8, N8, R8, M8, R7, R6, R5, T9, R3 | 16 |
| Data mask `DQM[1:0]` | M10, M9 | 2 |
| **Total** | | **39** |

Most of these pins (the `R*`, `T*`, `P*` cluster) are dedicated SDRAM nets on the schematic. They are not currently bound by `quartus/phase0` and would not collide with the WM8978 (`D14`/`D12`/`E9`/`D11`/`C14`), I2C (`P15`/`N14`), UART (`N6`/`N5`), or system clock/reset (`E1`/`M15`) pins. SDRAM also does not collide with the camera, TFT, ethernet, RTC, or HDMI nets noted in `docs/board_capabilities_report.md`.

The `IO_B7_*` bank labelling on the schematic for header GPIOs does not affect this conclusion: the SDRAM pins are on different banks (mostly bank 5/6 in the EP4CE10F17 die map) and use the board's main 3.3 V LVTTL/LVCMOS standard.

### Voltage and I/O standard

The schematic shows board rails at 3.3 V, 2.5 V, and 1.2 V (note: the prose hardware spec disagrees and says 3.3 V / 1.5 V / 1.2 V; trust schematic per `docs/board_capabilities_report.md`). The W9825G6KH is a standard 3.3 V SDR SDRAM. The vendor controller uses 3.3 V LVTTL on its SDRAM pins, which matches the FPGA bank assignment shipped in the example QSF.

### Clock and PLL implications

The vendor SDRAM controller (`44_uart_sdram`) instantiates its own PLL (`clk_gen_inst|altpll`) and runs the SDRAM at a higher clock derived from the 50 MHz oscillator. The shipped example uses two PLL outputs:

- `clk[0]`: SDRAM controller clock (memory side)
- `clk[1]`: SDRAM-side clock with phase shift (write/read alignment)

Phase 0 today uses the second PLL output for the 12 MHz audio MCLK derivation (`phase0_audio_mclk_pll`). The board has 2 PLLs; one is used. **Adding SDRAM consumes the second PLL.** That is fine because no Phase 5+ feature has been authorized that needs another PLL, but it does close the door on any "future PLL for richer audio clocking" without explicit replanning.

### Conflicts with current and future peripherals

| Subsystem | Conflict with SDRAM | Notes |
| --- | --- | --- |
| WM8978 audio | None (different pins) | `D*`/`E9`/`P15`/`N14` vs SDRAM `R*`/`T*`/`P*` |
| UART1 (CH340) | None | `N6`/`N5` are not SDRAM pins |
| RV32I core / control plane | None | All on-chip |
| TFT / 12-key UI (Phase 5) | **Possible bank-pressure conflict** | TFT data bus uses 16+ pins on the same physical edge; placement may compete |
| External CTP touch (Phase 6) | None | I2C-based, separate pins |
| Camera (deferred) | None | Camera nets on different banks |

The TFT/UI conflict is not a hard pin clash but is a routability/timing concern at high LE utilization with both subsystems present.

## 2. Reference-Cost Evidence

### Closest local reference: `44_uart_sdram`

This is the cleanest comparable: it ships with a working W9825G6KH controller bound to the same pinout this board would use, with closed timing.

| Metric | Value |
| --- | --- |
| Total logic elements | 735 / 10,320 (7%) |
| Combinational | 678 |
| Registers | 488 |
| Memory bits | 32,768 (8%) |
| Embedded multiplier 9-bit | 0 |
| PLLs | 1 |
| Pins | 43 |
| Slow-85C setup slack (sys_clk) | +11.355 ns |
| Slow-85C setup slack (PLL clk[0]) | +4.046 ns |
| Slow-85C setup slack (PLL clk[1]) | +3.163 ns |
| TNS at all corners | 0.000 |

The 735-LE cost is for the SDRAM controller plus a UART loopback test harness (init FSM, autorefresh, read/write FSMs, arbiter, plus UART RX/TX wrapping a sector-size loopback). The pure controller is roughly 500-600 LE; the harness adds the rest.

This example was synthesized with the same Quartus 13.0.1 SP1 toolchain currently used by `quartus/phase0`.

### Combined audio + SDRAM reference: `48_audio_record`

| Metric | Value |
| --- | --- |
| Total logic elements | 965 / 10,320 (9%) |
| Registers | 619 |
| Memory bits | 32,768 (8%) |
| PLLs | 1 |
| Pins | 50 |

Important caveat: `48_audio_record` ships with **negative timing slack**:

| Clock | Slow-85C setup slack |
| --- | --- |
| `audio_bclk` | -3.967 ns |
| `pll1\|clk[2]` (SDRAM-side) | -4.748 ns |
| `i2c_clk` | -1.843 ns |
| `pll1\|clk[1]` | -0.345 ns |

This is the same vendor-design pattern noted in `docs/manual_audio_example_report.md`: it works for board demonstration purposes but is not a sign-off-clean baseline. **Any Phase 4 SDRAM integration in `quartus/phase0` would need its own clean SDC, not a copy of `48_audio_record`'s.** The Phase 0 build has already proven that disciplined SDC plus multicycle exceptions can close timing on the audio path even at high LE utilization, so this is a known-solvable problem but not a free copy.

### LE cost estimate for adding SDRAM to current Phase 0 build

Conservative bracket, taking the vendor controller as a lower bound and adding overhead for arbitration with the existing audio datapath:

| Component | LE estimate | Confidence |
| --- | --- | --- |
| W9825 controller (init FSM, refresh, R/W FSMs, arbiter) | 500-700 | High (vendor evidence) |
| Phase 0 integration glue (CDC, register expansion, address map) | 100-200 | Medium |
| Audio-side burst FIFO (similar to `dcfifo` in `59_audio_sd_play`) | 50-100 | Medium |
| Optional debug/observability counters | 50-100 | Low |
| **Total minimum** | **~700-1,100 LE** | |

The Phase 0 build at 9,992 / 10,320 LE has **328 LE of headroom**. Adding even the lower bound of an SDRAM controller would require **at least 372 LE of reclamation** before integration.

### Memory bits cost

The vendor controller uses 32,768 memory bits, which is one M9K block (the burst FIFO). Phase 0 currently uses 86,016 bits (20 percent of 423,936). Adding ~32 KiB more would put the design at ~28 percent memory usage. **This is not the constraint.**

### DSP and PLL cost

SDRAM controllers do not consume DSP elements. They consume one PLL. Phase 0 currently uses 1 of 2 PLLs. **SDRAM uses the second PLL.**

## 3. Phase 4 Audio Candidates That Could Benefit from Off-Chip Memory

Per project brief Phase 4 scope (lines 154-167): *"SDRAM for longer delay/state buffers, richer body models, or tables that no longer fit comfortably on-chip."* Three candidates are evaluated below; all others are out of Phase 4 scope or out of Phase 5+ scope.

### Candidate A: Longer body convolution (room/cabinet impulse response)

**What**: Replace the current 2-stage body IIR (about 200 LE, ~10 DSP) with a longer FIR body convolution. A 1024-tap mono FIR at 16-bit coefficients = 16 KiB. A 4096-tap stereo FIR at 16-bit = 128 KiB. The first does not need SDRAM. The second does.

| Aspect | Estimate |
| --- | --- |
| Data size on-chip-only (1024 mono) | 16 KiB (4 M9K blocks at 16 KiB each? actually 1 M9K can hold 4096x9 or 2048x18; 1024x18 fits in 1 M9K) |
| Data size if SDRAM (4096 stereo) | 128 KiB |
| Access pattern | Linear streaming, one sample per FIR tap per output sample |
| Latency tolerance | Very low; missing one sample causes audible click |
| On-chip memory already sufficient? | **Yes for ~1024-tap mono, no for >2048-tap stereo** |
| Audibility win at 1024 taps | Strong (small room or piano body coloration) |
| Audibility win at 4096+ taps | Larger but diminishing returns at this fidelity tier |

**Verdict**: A 1024-tap on-chip FIR is the right next coloration step. Going beyond 2048 taps to need SDRAM is **not justified at the current Phase 4 fidelity target**.

### Candidate B: Richer modal/FDN body model state (longer state vectors per resonator)

**What**: A modal soundboard model maintains state per modal resonator (frequency, damping, output coefficient). Twelve resonators at 32 bits per state field x 4 fields = 192 bytes. Even 64 resonators (the upper end of useful for a piano body) = 1 KiB. A feedback delay network (FDN) with eight delay lines at 4096-sample max delay each = 64 KiB.

| Aspect | Estimate |
| --- | --- |
| Modal bank state on-chip | 1 KiB easily fits (1 M9K = 16 KiB) |
| FDN delay state on-chip | 64 KiB needs ~2 M9K, fits |
| Access pattern | One read + one write per delay line per sample |
| Latency tolerance | Very low |
| On-chip memory already sufficient? | **Yes** |
| Audibility win | Significant (richer body resonance) |
| LE cost | Modal bank: ~1500-3000 LE depending on resonator count. FDN: ~600-1200 LE. |

**Verdict**: Modal/FDN body upgrades are **the right direction for Phase 4 fidelity**, and they fit on-chip memory comfortably. The blocker is **LE budget for the arithmetic, not memory size**. SDRAM does not help here.

### Candidate C: Velocity-layered hammer excitation table (sample-style variant)

**What**: Multiple hammer excitation ROMs indexed by velocity. Currently the hammer ROM is 16 constants. A velocity-layered set of 8 hardness levels x 64 samples each at 16 bits = 1 KiB. A more elaborate sample-style approach with 32 layers x 1024 samples each = 64 KiB.

| Aspect | Estimate |
| --- | --- |
| 8 layers x 64 samples on-chip | 1 KiB easily fits |
| 32 layers x 1024 samples | 64 KiB needs ~2 M9K, fits |
| Access pattern | Random initial read at note-on, then linear during attack (~30 ms) |
| Latency tolerance | Low (audible jitter at attack) |
| On-chip memory already sufficient? | **Yes for the realistic scale** |
| Audibility win | Modest (richer attack timbre) |
| LE cost | ~200-400 LE for indexed ROM + velocity decode |

**Verdict**: Hammer-table expansion fits on-chip and is a small additive win. The variant that would need SDRAM (sample-style multi-layer recordings) crosses into the "no sample playback" blocked-feature line in `docs/project_brief.md`.

## 4. SDRAM-First vs Reclamation-First vs On-Chip Expansion

| Dimension | SDRAM-first | Reclamation-first | Small on-chip expansion |
| --- | --- | --- | --- |
| Step-1 RTL change | Major (controller + integration) | None (audit) | Moderate (one feature) |
| LE delta this step | +700 to +1,100 | -200 to -500 | +200 to +500 |
| Final LE position | 10,300+ (at or above device cap) | ~9,500 | 10,200+ (at or above 99 percent) |
| Risk to accepted M1/M3b/M4 baseline | **High** (no headroom margin) | None | High (similar headroom risk) |
| Audible win this step | None (controller is plumbing) | None | Moderate (one coloration) |
| Unblocks future Phase 4 work | Yes, but only if a consumer exists | Yes (essential) | Partial |
| Compatible with current 97% LE | **No** | Yes | Risky |
| Has a clear next consumer that needs >32 KiB? | Currently no | N/A | N/A |

**The dominant signal**: every Phase 4 audio candidate that has a clear audible payoff (1024-tap body FIR, modal bank, FDN, velocity-layered hammer at realistic scale) **fits in on-chip memory**. SDRAM only earns its keep above the realistic Phase 4 fidelity tier, and at that point it is the **arithmetic** (LE/DSP) that runs out first, not memory bits. Memory bits are at 20 percent.

This means **paying the SDRAM controller LE cost now** would consume ~7-10 percent of the device for a memory resource we do not yet have a consumer for, while making it harder to fit the audio features that would actually use that memory.

## 5. Recommendation

**Go: reclamation-first.**

Rationale:

- The current 97% LE is the immediate threat. Any further work risks breaking the accepted M1/M3b/M4 baseline.
- The best-justified Phase 4 features (longer body coloration, modal/FDN body, hammer layering at realistic scale) **all fit on-chip**. They need **LE/DSP** budget, not SDRAM bandwidth.
- The vendor SDRAM controller demonstrates that adding SDRAM later is technically straightforward (~700-1100 LE estimated, 1 PLL, no DSP, 1 M9K, no audio-pin conflicts). It is not at risk of becoming infeasible if we defer it.
- Reclamation has direct precedent in this codebase: Phase 1C-A and Phase 1C-B both successfully recovered LE/M9K/ROM headroom behavior-preservingly. M8 is a counterexample for ROM but informs the discipline.

### Recommended next task

**Task — Phase 4 M1 reclamation scope (proposal-only)**

- Role: implementer
- Output: `reports/phase4_m1_reclamation_scope.md`
- Required content:
  - Inventory of LE-heavy modules from current `quartus/phase0` Map/Fit reports if accessible, otherwise from RTL inspection.
  - Top 3-5 candidates for behavior-preserving LE reduction (e.g., redundant decode collapse in `phase0_control_regs.v`, common-subexpression elimination in voice/audio pipeline, dead-path removal, telemetry packing).
  - Top 1-2 candidates for ROM reduction (firmware function/macro consolidation if any exist that survive M8's lessons).
  - For each candidate: estimated savings, behavior-preservation argument, and the verifier evidence required to confirm no regression (golden-sample TB, ModelSim happy/NACK runs, hardware UART smoke).
  - Explicit non-goals: no RTL feature changes, no SDC broadening, no UART/register/firmware-behavior changes.
  - Go/no-go gate per candidate: whether the savings justify the verification cost.
- Scope guards (hard):
  - No RTL, firmware, SDC, constraint, PLL, project-file, or host-tool change.
  - No FPGA programming.
  - Documentation only.
  - Do not touch the 4 untracked verifier UART files or `.kiro/`.

**Acceptance gates for M1 scope**:

| Gate | Threshold |
| --- | --- |
| Artifact at `reports/phase4_m1_reclamation_scope.md` | required |
| ASCII-only | required |
| Identifies at least 3 LE candidates with quantitative estimates | required |
| Identifies at least 1 verification path per candidate | required |
| Reaches an explicit go/no-go on whether reclamation can target >=400 LE | required |

### Optional follow-up task — only if M1 scope identifies viable LE recovery

**Task — Phase 4 M2 narrow reclamation slice (implementation)**

- Role: implementer
- Output: code commit + `reports/phase4_m2_reclamation_impl.md`
- Required content: implement only the highest-value LE reclamation slice from M1 scope; preserve all accepted hardware behavior; verify with ModelSim golden samples and Quartus full compile.
- Acceptance gates:
  - LE delta <= 0 (must not grow LE)
  - LE recovery >= scope target (e.g., >= 200 LE)
  - All accepted UART telemetry preserved bit-exact
  - Golden-sample TB PASS
  - Quartus full compile PASS, setup slack >= +2.5 ns slow-85C, hold clean, TNS = 0
  - No SDC/PLL/pin/host-tool/firmware-behavior changes
  - K=0, no audio regression (per audio checklist if hardware available)

### SDRAM stays gated

SDRAM integration is **explicitly held** until:
1. Reclamation has been demonstrated to recover meaningful headroom (target >= 400 LE), and
2. A specific Phase 4 audio feature has been scoped that demonstrably needs >32 KiB of off-chip memory. As shown in section 3, this bar is genuinely hard to cross within the project brief Phase 4 scope and the project's "no sample playback" guardrail.

If a future task identifies such a candidate, an SDRAM-controller scoping task can be queued at that time. The vendor `44_uart_sdram` and `48_audio_record` references will remain available as starting points.

## 6. Why This Is Safe for the Current EP4CE10 Posture

- **No code change in this step.** Pure analysis. Zero risk to the accepted baseline.
- **97% LE makes any controller introduction unsafe** without first recovering headroom. The vendor controller would need at least ~400 LE of recovered budget before it could even fit; the integration glue extends that further.
- **Memory bits are at 20%.** The on-chip M9K is the cheapest, most reliable memory on this device for the Phase 4 candidates that have a clear audible payoff. Spending logic to import SDRAM bandwidth is paying logic to import a resource we already have plenty of.
- **The PLL budget is 1 of 2.** Spending the second PLL on SDRAM forecloses any later need for an additional audio-clock domain. There is no urgency to spend it.
- **Reclamation has direct precedent** (Phase 1C-A, Phase 1C-B) and a known failure mode to avoid (M8 function-extraction NO-GO).
- **Hardware audio is currently working end-to-end.** Anything that risks rolling that back without measured payoff is a net negative.

## 7. Summary

| Item | Status |
| --- | --- |
| SDRAM is technically affordable on this board | Yes (~700-1100 LE, 1 PLL, ~32 KiB M9K) |
| SDRAM has an immediate audio consumer | **No** within Phase 4 scope and project guardrails |
| Current LE budget supports SDRAM integration today | **No** (97% LE, only 328 LE free) |
| Recommended next step | **Phase 4 M1 reclamation scope (paper only)** |
| Recommended deferred step | Phase 4 M2 narrow reclamation slice, if M1 finds >= 400 LE |
| SDRAM revisit | After reclamation lands and a specific consumer is scoped |
| Verdict | **Reclamation-first; SDRAM held; on-chip expansion considered after reclamation** |

This report is documentation only. No RTL, firmware, SDC, constraint, PLL, generated image, or host tool was modified.
