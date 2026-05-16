# Phase 4 M2 Reclamation Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-08208b76`
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `0c83ae3`

## Verdict

**PASS.**

- Candidate A (control_regs decode/strobe consolidation): NO-GO confirmed and reverted; not present in committed source.
- Candidate C (delete dead `rtl/control/phase0_soc_stub.v`): accepted as repo hygiene; zero behavior or synthesis impact.
- Accepted post-M2 baseline matches the prior accepted M3b/M9 build: LE 9,992 / 10,320, M9K 16, DSP9 28 / 46, setup slow-85C `sys_clk_50m` +2.914 ns, hold +0.405 ns, all TNS 0.
- Firmware ROM unchanged at 931 / 1024 words.

## Scope check

`git show --stat 5db0378`:
- delete `rtl/control/phase0_soc_stub.v` (-389 lines)
- add `reports/phase4_m2_reclamation_impl.md` (+155 lines)

`git show --stat 0c83ae3`:
- modify `reports/phase4_m2_reclamation_impl.md` only (+9/-7)

No firmware (`fw/`), host tools (`scripts/`), RTL outside the deleted file, SDC, pin assignments, PLL settings, QSF/project files, generated images, or unrelated baseline reports were touched. Confirmed via `git log -p` inspection of both commits.

## ASCII check

`reports/phase4_m2_reclamation_impl.md`: 0 non-ASCII bytes (size 11,148). PASS.

## Dead-file proof for `phase0_soc_stub.v`

Pre-deletion check across the live build/sim/source surface (commit `5db0378`'s parent):
- `quartus/phase0/piano_phase0_top.qsf` does not list it.
- No build script (`*.ps1`, `*.sh`, `*.bat`, `*.tcl`, `*.do`, `*.f`) references it.
- `rtl/top/piano_phase0_top.v` instantiates `phase0_rv32i_soc`, not the stub.
- No testbench (`rtl/audio/phase1_reduced_voice_tb.v`, `rtl/top/piano_phase0_top_tb.v`) references it.
- No firmware source references it.

Remaining matches are all in historical reports (`reports/phase0_*`, `reports/phase1c_*`, `reports/phase4_m1_reclamation_scope.md`, the M2 impl/validation reports). Per task scope these do not count as live dependencies. Conclusion: the file was not synthesized, not simulated, and not built before deletion. PASS.

## 4-voice integrity proof

`rtl/audio/phase0_audio_path.v` instantiates four physical voices:
- `phase1_reduced_voice phase1_reduced_voice_inst` (line 141)
- `phase1_reduced_voice phase1_reduced_voice1_inst` (line 165)
- `phase1_reduced_voice phase1_reduced_voice2_inst` (line 189)
- `phase1_reduced_voice phase1_reduced_voice3_inst` (line 213)

`fw/phase0/phase0_main.c` periodic telemetry block emits the voice3 tags `V3=`, `VT=`, `VA=`, `VV=`, `S3=`, `ST=`, plus all existing core/voice0/voice1/voice2 tags through `Q/X/CC`. PASS.

## Build / fit / timing evidence

Source artifacts read at HEAD `0c83ae3`:

- `fw/phase0/build/phase0.bin`: 3,724 bytes = **931 words** (matches accepted M3b/M9 baseline).
- `quartus/phase0/output_files/piano_phase0_top.fit.summary` (Sat May 16 14:22:16 2026):
  - Total logic elements: 9,992 / 10,320 (97%)
  - Combinational functions: 9,417 / 10,320 (91%)
  - Dedicated logic registers: 4,233 / 10,320 (41%)
  - Total memory bits: 86,016 / 423,936 (20%)
  - Embedded multiplier 9-bit elements: 28 / 46 (61%)
  - Total PLLs: 1 / 2
- `quartus/phase0/output_files/piano_phase0_top.sta.summary`:
  - Slow 1200mV 85C setup `sys_clk_50m`: +2.914 ns, TNS 0.000
  - Slow 1200mV 85C hold `sys_clk_50m`: +0.405 ns, TNS 0.000
  - Slow 1200mV 0C setup `sys_clk_50m`: +3.832 ns, TNS 0.000
  - Fast 1200mV 0C hold `sys_clk_50m`: +0.132 ns, TNS 0.000
  - All other clocks (`i2c_clk`, `audio_bclk`) clean across all corners.

Justification for not rerunning Quartus: the M2 source change is deletion of a file that was never in the QSF or any synthesis input. Synthesis is byte-identical, so the existing `output_files/` are authoritative for HEAD `0c83ae3`. The fit timestamp predates `5db0378` only because the deleted file was never synthesized. The `phase4_m2_reclamation_impl.md` report records the same numbers as its `Committed Result` (post-revert) build.

ModelSim was not rerun. Justification: the only shipped RTL change is removal of a non-instantiated file, so simulation behavior cannot change. PASS.

## Hardware skip

Hardware UART/audio not run. Justification: no live RTL or firmware behavior changed at HEAD `0c83ae3` versus the accepted M3b/M9 baseline; no SOF regeneration is required. PASS by inertia.

## Final verdict

- Candidate A: **NO-GO** confirmed.
- Candidate C: **ACCEPTED** as inert repo hygiene.
- Accepted Phase 4 M2 baseline = identical-synthesis post-revert build with 9,992 LE, 16 M9K, 28 DSP9, +2.914 ns setup, ROM 931. Safe to continue.
