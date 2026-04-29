# Phase 1 Next Scaling Architecture Options

Date: 2026-04-28
Orchestrator: codex-orchestrator
Task: `task-3ffd878d`

## Purpose

Prepare the next controlled scaling decision after the hardware-accepted Phase 1 two-voice baseline.

This memo is decision preparation only. It does not authorize RTL, firmware, clocking, SDRAM, or feature changes.

## Current Accepted Baseline

References:

- `reports/phase1_two_voice_hardware_acceptance_decision.md`
- `reports/phase1_two_voice_hardware_smoke.md`
- `reports/phase1_two_voice_validation.md`
- `reports/phase1_two_voice_impl_report.md`

Accepted build:

- SOF: `quartus/phase0/output_files/piano_phase0_top.sof`
- checksum: `0x00553670`
- SHA-256: `274C3F3178A08E103B500E724ED15E5FDFF0E58D15DD0EFB94514BECC3523A78`

Resources:

| Metric | Two-Voice Build |
| --- | ---: |
| Logic elements | 7,366 / 10,320 |
| Dedicated registers | 3,580 |
| Memory bits | 271,360 / 423,936 |
| M9Ks | 34 / 46 |
| DSP9 elements | 4 / 46 |
| PLLs | 1 / 2 |

Timing:

- fully constrained setup and hold
- all listed TNS values `0.000`
- slow-85C `sys_clk_50m` setup slack `+3.957 ns`
- slow-85C `sys_clk_50m` Fmax `62.33 MHz`

The second voice cost relative to the timing-margin single-voice baseline was:

| Metric | Delta |
| --- | ---: |
| Logic elements | +1,683 |
| Dedicated registers | +992 |
| Memory bits | +4,608 |
| M9Ks | +1 |
| DSP9 elements | +2 |
| PLLs | 0 |

## Option 1: Third Voice By Duplication

Description:

Duplicate the current reduced voice again, extend diagnostics, and mix three voices with saturation.

Approximate resource projection if the third voice costs about the same as the second:

| Metric | Estimated Three-Voice Build |
| --- | ---: |
| Logic elements | about 9,049 / 10,320 |
| Dedicated registers | about 4,572 |
| Memory bits | about 275,968 / 423,936 |
| M9Ks | about 35 / 46 |
| DSP9 elements | about 6 / 46 |
| PLLs | 1 / 2 |

Pros:

- Fastest way to answer "can one more reduced voice fit?"
- Keeps the architecture simple.
- DSP and M9K totals would still look acceptable on paper.

Risks:

- LE utilization would be around 88%, leaving little routing and future debug margin.
- Growth may be worse than linear once mix, diagnostics, fanout, and placement effects are included.
- A pass would not prove a scalable polyphony architecture; it would prove one more duplicated slice.
- A failure might arrive as routing/timing degradation rather than a clean resource exhaustion.

Evidence required before approving:

- resource attribution showing where the second-voice LE/register cost came from
- a stop rule before implementation, for example fail/review if projected LE exceeds 9,100 or slack drops below +1.0 ns
- explicit plan to avoid growing UART/register diagnostics without bound

Assessment:

Useful only as a bounded fit experiment. It is not the recommended next implementation slice.

## Option 2: Optimize Current Two-Voice Kernel First

Description:

Keep two voices and the accepted behavior fixed, then identify and reduce per-voice/control overhead before adding capability.

Candidate focus areas:

- resource attribution by module and by hierarchy
- duplicated status/counter/debug logic
- mix/diagnostic fanout
- register-map decode cost
- voice wrapper/control duplication
- opportunities to push arithmetic or comparisons into DSP-friendly datapaths
- compile-time or build-time trimming of nonessential diagnostics after baseline acceptance

Pros:

- Directly addresses the real constraint: LEs and M9K packing.
- Preserves the now hardware-accepted behavioral baseline.
- Creates a better foundation for any later third voice or scheduler.
- Lower risk than changing the model, clocking, or memory system.

Risks:

- Optimization can accidentally perturb a known-good baseline.
- Savings may be modest if most cost is inherent in the current voice kernel.
- Requires careful before/after verification and artifact discipline.

Evidence required:

- module-level resource report or equivalent fitter hierarchy summary
- exact pre/post resource and timing comparison
- unchanged simulation signatures for the accepted two-voice tests
- hardware smoke only if behavior-affecting changes occur

Assessment:

Best next architecture direction. It improves the odds of future scaling without mixing in new functional risk.

## Option 3: Minimal Scheduler Without More Voices

Description:

Keep the two existing voice engines, but add a small note-event/voice-control layer so the two voices can be triggered independently or staggered.

Pros:

- Adds musical usefulness while keeping the voice count fixed.
- Tests whether the CPU/control interface can manage real note events without entering the sample loop.
- Should be much cheaper than a third full voice if scoped tightly.

Risks:

- Control logic, register map, and firmware can expand if not constrained.
- Scheduler semantics can become a hidden product-design problem.
- Needs clear tests for simultaneous and staggered note events.

Evidence required:

- fixed two-voice resource cap before work starts
- documented event model with no per-sample CPU dependency
- simulation proving independent triggers and overlap
- hardware UART/audio smoke proving staggered events are observable

Assessment:

Good follow-on after resource attribution or a small optimization pass. It should not be combined with a third voice.

## Option 4: Bounded SDRAM Feasibility Experiment

Description:

Investigate whether off-chip SDRAM is viable for future longer delay lines or tables.

Pros:

- Could eventually relieve on-chip memory pressure for longer models.
- Useful if richer physics requires storage beyond M9K capacity.

Risks:

- Adds controller logic, timing closure risk, arbitration, latency, refresh behavior, and verification burden.
- Does not solve current LE pressure by itself.
- Audio real-time behavior becomes harder to reason about if the sample loop depends on variable memory latency.

Evidence required:

- a specific memory need that cannot fit in M9Ks
- standalone SDRAM bandwidth/latency measurement
- proof that audio deadlines survive worst-case refresh/arbitration
- no coupling to a new voice, richer model, or scheduler in the same task

Assessment:

Do not make SDRAM the default next step. Keep it as a separate future experiment triggered by measured memory pressure.

## Recommendation

Do not approve a third voice yet.

Recommended next milestone:

`Phase 1C: two-voice architecture hardening and resource attribution`

Success criteria:

- produce module/hierarchy resource attribution for the accepted two-voice build
- identify the top LE/register/M9K contributors
- propose one narrow optimization target with expected savings and verification cost
- keep the accepted two-voice behavior frozen
- no new features, no SDRAM, no scheduler, and no third voice in the same slice

After that, decide between:

1. a narrow two-voice optimization implementation;
2. a minimal two-voice scheduler;
3. a strictly bounded third-voice fit experiment with explicit stop criteria.

## Decision Needed

The orchestrator should next choose one of these:

- `A`: assign resource-attribution/hardening work first;
- `B`: assign minimal two-voice scheduler design first;
- `C`: authorize a third-voice fit experiment with strict stop criteria;
- `D`: open a standalone SDRAM feasibility study.

Recommended choice: `A`.

