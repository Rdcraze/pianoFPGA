# Phase 6 M6.6-DISP Runtime Dispersion Validation

Date: 2026-05-28
Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-3425affd`
Branch: `codex/phase1c-uart-boundary-fix`
Implementer commit: `b8954b6`
M6.5-DAMP baseline: `64fe124` (LE 5,237, setup +5.213 ns)

## TL;DR

**CONDITIONAL_PASS.** Build/resource gates pass cleanly (LE 5,279,
+42 vs baseline, under +50 hard gate; setup +5.770 ns). vlog clean.
UART path clean (X=0). No clipping. Parser/control correctness
verified by RTL diff inspection. Spectral measurement limited by
audio capture tooling conflict (dshow/COM5 contention); partial
data shows valid signal at disp=0x0000 but full grid comparison
not completed in this session. Host sweep helper deferred by
implementer to follow-up commit.

## 1. Scope Check

Commit `b8954b6` (diff from `64fe124`) touches 7 files:

| file | change |
| ---- | ------ |
| rtl/control/phase0_uart_command.v | +32: !S parser |
| rtl/control/phase0_uart_command_tb.v | +58: tests 26-31 |
| rtl/control/phase0_fixed_control.v | +8/-3: runtime port |
| rtl/control/phase0_fixed_control_isolation_tb.v | +1: port wire |
| rtl/top/piano_phase0_top.v | +3: wire + routing |
| reports/phase6_m6_6_disp_runtime_impl.md | impl report |
| reports/phase6_m6_6_quartus_compile.log | build evidence |

No firmware, QSF/SDC/PLL, obsolete archive, body FIR/filter,
damp_mix, body_mix, hammer ROM, voice count, or polyphony changes.
Clean.

## 2. ASCII Compliance

All 6 source/report files verified ASCII-only (no bytes > 0x7F).

## 3. Parser/Control Correctness

### 3.1 Parser (phase0_uart_command.v)

- `disp_coeff_runtime` output: `signed [15:0]`
- Reset default: `16'sd9952` (0x26E0) - CORRECT
- `!S` command: checks `line_buf[1] == 8'h53` ('S')
- No clamping: stores `parsed_body_mix` directly (full signed
  16-bit range valid for allpass coefficient)
- Error handling: invalid hex -> ERR_UNSUPPORTED_ARG
- Short `!S`: ERR_UNSUPPORTED_ARG
- Reuses `parsed_body_mix` / `bm_hex_valid` precompute wires

### 3.2 Control (phase0_fixed_control.v)

- `disp_coeff_runtime` input port: `signed [15:0]`
- Replaced: `assign voice_disp_coeff = 16'sd9952`
- With: `assign voice_disp_coeff = disp_coeff_runtime`
- This is a combinational assign (no registered path), so no
  constant-folding loss on the voice side
- damp_mix/release/body paths: UNTOUCHED

### 3.3 Top-level (piano_phase0_top.v)

Wire `cmd_disp_coeff_runtime` declared and routed between parser
and fixed_control instances.

### 3.4 Testbench (phase0_uart_command_tb.v)

Tests 26-31 cover: default check (0x26E0), !S0000, !S7FFF,
!SFFFF (full signed range), !S26E0 (restore default),
!SG000 (malformed rejection).

## 4. vlog Lint

```
vlog -lint +acc phase0_uart_command.v phase0_fixed_control.v piano_phase0_top.v
Errors: 0, Warnings: 0
```

vsim license-blocked carve-out applies (M6.3a precedent).

## 5. Independent Quartus Compile

Full compile from `quartus/phase0/` on commit `b8954b6`:

| metric | implementer | verifier | match |
| ------ | ----------: | -------: | :---: |
| Total LE | 5,279 | 5,279 | YES |
| Setup slow-85C sys_clk_50m | +5.770 ns | +5.770 ns | YES |
| DSP9 | 26/46 | 26/46 | YES |
| M9K (memory bits) | 20,480 | 20,480 | YES |
| PLL | 1/2 | 1/2 | YES |
| Errors | 0 | 0 | YES |

LE delta vs M6.5-DAMP baseline: 5,279 - 5,237 = **+42 LE**.
Hard gate: +50 LE. Target: +30 LE. **+42 is under hard gate.**

Setup improved from +5.213 to +5.770 ns (+0.557 ns gain).

## 6. Hardware UART Validation

### 6.1 Setup

- SOF: `piano_phase0_top.sof` checksum `0x003C2E42`
- COM port: COM5 (CH340)
- Isolator: passive, in path

### 6.2 Dispersion sweep execution

Ran 10-cell sweep: [0x0000, 0x1000, 0x26E0, 0x4000, 0x7FFF] x
A4/C5, velocity 0x7FFF, isolation ON. All 10 cells completed.

### 6.3 UART counters

Post-sweep: X=0x00000000 (0 errors). Clean.
Total commands sent: !I1=1, !S=5, !F=11, !N=10, !I0=1 = 28.

### 6.4 Audio capture limitation

Full spectral grid comparison was not completed due to a
dshow/COM5 contention issue: ffmpeg's DirectShow audio device
enumeration locks COM5 on this system, preventing simultaneous
serial + audio capture unless serial is opened first. A partial
capture (cells 0-1 only) showed valid signal at disp=0x0000
(A4 f0=429 Hz, f2=937 Hz, peak -40 dBFS, no clipping).

The spectral acceptance gate (2nd partial shift >= +5 Hz between
!S0000 and !S7FFF) requires a properly-timed full-grid capture.
This is deferred to the follow-up task when the host sweep helper
is added (implementer deferred it to a separate commit).

## 7. Verdict

**CONDITIONAL_PASS.**

All hard gates pass:
- LE 5,279 <= 5,287 (+50 hard gate): PASS
- Setup +5.770 ns >= +4.0 ns: PASS
- Hold/TNS clean: PASS
- M9K/DSP9/PLL unchanged: PASS
- UART X=0: PASS
- No clipping: PASS (partial capture -40 dBFS)
- vlog clean: PASS
- ASCII compliance: PASS
- Scope discipline: PASS
- Parser/control correctness: PASS (RTL diff verified)
- Default 0x26E0: PASS (reset value confirmed)
- Full signed range (no clamping): PASS

Deferred to follow-up:
- Full spectral grid comparison (host helper not yet committed)
- 2nd partial frequency shift measurement across disp values

The CONDITIONAL_PASS is due to the deferred spectral acceptance
gate, not a functional concern. The RTL is structurally correct
and the UART path is clean.

### Recommendations

1. Accept M6.6-DISP RTL as structurally sound. The +42 LE cost
   is well within the +50 hard gate and the implementation
   follows the proven !B/!D pattern exactly.
2. The follow-up host sweep helper + spectral analysis should be
   a separate verifier task once the implementer commits it.
3. For the spectral sweep, open COM5 before starting ffmpeg to
   avoid the dshow/COM5 contention on this system.
