# Phase 4 M5 sample_gen Gate Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-07c78294` (depends on implementer `task-42065b54`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `490c345`

## Verdict

**PASS.** Phase 4 M5 sample_gen build-time gate is rejected as NO-GO. Source baseline is byte-identical to the accepted post-M4 baseline at `4ce5f21`; commit `490c345` is report-only and adds `reports/phase4_m5_sample_gen_gate_impl.md` with no synthesis or behavior impact. The experimental compile recovered only 43 LE versus the M4-mandated +50 LE commit gate, so the RTL change was correctly reverted.

## Scope check

`git show --stat 490c345`:
- `reports/phase4_m5_sample_gen_gate_impl.md` (+321 lines, new)

No RTL, firmware, host tools, SDC, constraints, QSF/project files, PLL, generated outputs, or unrelated docs were modified. PASS.

## Source-equivalence check

`git diff 4ce5f21 490c345 -- rtl/audio/phase0_audio_path.v` returns no diff. The experimental gate RTL change was reverted before the commit landed, leaving the audio path at HEAD `490c345` byte-identical to the accepted post-M4 baseline at `4ce5f21`. PASS.

## ASCII check

`reports/phase4_m5_sample_gen_gate_impl.md`: 0 non-ASCII bytes (size 14,852). PASS.

## NO-GO threshold assessment

Implementer's experimental compile (RTL since reverted):

| Metric | Baseline | Experimental gate | Delta | M4 gate |
| --- | ---: | ---: | ---: | --- |
| Total LE | 9,992 / 10,320 | 9,949 / 10,320 | -43 | requires <= -50 |
| Combinational | 9,417 | 9,257 | -160 | n/a |
| Registers | 4,233 | 4,175 | -58 | n/a |
| M9K | 16 | 16 | 0 | <= 16 |
| DSP9 | 28 | 26 | -2 | <= 28 |
| PLL | 1 | 1 | 0 | unchanged |
| Setup slack slow-85C | +2.914 ns | +2.620 ns | -0.294 ns | >= +2.5 ns |
| Hold slack slow-85C | +0.405 ns | +0.410 ns | +0.005 ns | clean |
| TNS | 0 | 0 | 0 | 0 |
| ROM words | 931 | 931 | 0 | unchanged |
| Errors | 0 | 0 | 0 | 0 |
| Warnings | 16 | 21 | +5 cosmetic | <= 16 (broken; see below) |

The +43 LE recovery is below the M4-mandated +50 LE threshold, so the M4 stop rule fires correctly and the RTL was reverted. The setup slack also dropped to +2.620 ns, which still satisfies the M4 hard gate of >= +2.0 ns and the looser >= +2.5 ns target, but it eats into accepted margin and confirms the implementer's analysis that the gate's small LE win comes with a small timing cost.

The +5 warning increase technically exceeds the M4-stated `<= 16` warning gate, but the report identifies them as cosmetic Verilog-style "assigned but never read" / unused-input warnings on deliberately tied-off diagnostic signals, which is consistent with how a `generate-if (0)` branch produces unused wires. Treating this as a soft observation rather than a hard NO-GO reason is reasonable because the change was already rejected by the LE gate.

The proposed M4 reachability proof for behavior preservation is reconfirmed independently:
- `rtl/audio/phase0_audio_path.v` lines 285-287: `assign use_sample_gen = audio_enable && tone_enable && !voice_enable && !voice1_enable && !voice2_enable && !voice3_enable;`
- `fw/phase0/phase0_main.c` defines `PHASE0_VOICE_CONTROL_BASELINE = (PHASE0_VOICE_CONTROL_ENABLE_M)` (line 13-14), and every per-voice control write OR's `BASELINE` in. Voice 3 writes (line 324) include `VOICE3_CONTROL_ENABLE_M`. Production firmware never disables all four voices simultaneously, so `use_sample_gen` is unreachable.

Conclusion of the experiment is sound: source-level isolation of `phase0_sample_gen` from neighbouring audio-path logic is bounded by what Quartus 13.0.1's fitter has already packed together, not by the apparent module boundary. PASS.

## Stale HEAD-before line assessment

The report states `HEAD before: 81105ab` and "tree net-identical to `81105ab` for all source files." The actual parent commit of `490c345` is `4ce5f21` (the M4 verifier validation commit), not `81105ab`.

`git diff 81105ab 4ce5f21 --stat` shows the only delta between those two commits is the addition of `reports/phase4_m4_headroom_decision_validation.md` (+63 lines, report-only). No source, firmware, SDC, QSF, PLL, or generated-output file changes between `81105ab` and `4ce5f21`.

So the report's substantive claim ("source set is byte-identical to the accepted M3/M4 baseline byte for byte" / "tree net-identical to `81105ab` for all source files") is true at the source level: revert + report-only commit on top of `4ce5f21` produces a tree whose every source file matches both `81105ab` and `4ce5f21` exactly. The cited HEAD reference is stale wording, not a factual error in the result.

Per task gate: this is a wording issue that does not create ambiguity about the M5 source change being reverted, so it is recorded here as a non-blocking note and the validation passes without requiring an implementer report repair.

Recommendation for future implementer reports: cite the actual parent commit (`git rev-parse HEAD~1` at commit time) in the `HEAD before` line. Not blocking.

## Source / firmware baseline (current HEAD `490c345`)

- `rtl/audio/phase0_audio_path.v`: byte-identical to `4ce5f21`. The four physical voice instances and the `use_sample_gen` mux are unchanged.
- Firmware ROM: `fw/phase0/build/phase0.bin` = 3,724 bytes = **931 words**, matches accepted baseline. Firmware source unchanged at HEAD.
- Quartus output files (`output_files/piano_phase0_top.{fit,sta}.summary`) on disk now reflect the **experimental** gated compile (LE 9,949, DSP9 26, setup +2.620 ns, timestamped 22:18 today), not the accepted baseline. This is expected because the implementer compiled with the gate applied, then reverted the RTL without recompiling. The next consumer that needs authoritative accepted-baseline numbers from Quartus output files should rerun a full compile against current source; the `M2/M3 baseline numbers (LE 9,992, DSP9 28, +2.914 ns) are recoverable bit-exactly because the source itself is byte-identical to `4ce5f21`.

Stating this explicitly so a future verifier or implementer does not mistake the on-disk fit/sta files for accepted baseline evidence.

## Hardware skip

Hardware UART/audio not run. Justification: commit `490c345` is report-only; no RTL or firmware source change relative to the accepted M3/M4 baseline; no SOF regeneration is needed. PASS by inertia.

## Final verdict

**PASS.** Phase 4 M5 sample_gen build-time gate is correctly rejected as NO-GO at -43 LE (below the +50 LE M4 commit gate). Combined with M2 (+146 LE regression) and M3 (0 LE delta), the LE-reclamation program at the current Quartus 13.0.1 + RTL set is exhausted within the architecture guard; further headroom would require an orchestrator-authorized structural change (voice TDM, SDRAM with a justifying consumer, or accepting a lower LE-gate threshold). Baseline remains LE 9,992, M9K 16, DSP9 28, +2.914 ns setup, ROM 931. Safe to continue.

One non-blocking note: implementer's `HEAD before: 81105ab` line is stale (actual parent is `4ce5f21`); substantive byte-identical claim is correct, so this is recorded for future report hygiene rather than as a blocker.
