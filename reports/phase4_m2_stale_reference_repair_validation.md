# Phase 4 M2 Stale-Reference Repair Validation

Verifier: kiro-verifier `143ef321-d70f-4f01-97f3-e44e31022699`
Task: `task-9bb223d8` (depends on implementer `task-1cdcc0c9`)
Branch: `codex/phase1c-uart-boundary-fix`
HEAD: `80b3a17`

## Verdict

**PASS.**

Implementer commit `80b3a17` repairs the two remaining live references to the deleted `rtl/control/phase0_soc_stub.v` without touching any synthesized or simulated code path. The cleanup is authoritative-current-state in the docs and header, leaves prior mentions clearly historical, and preserves the firmware ROM word count at 931.

## Artifact reference note

Orchestrator attached `reports/phase4_m2_stale_reference_repair.md` as artifact `737602b6-86cb-473b-8412-96f50de04d72` for the implementer task. The report exists at HEAD `80b3a17` and matches the commit (added in the same commit, +110 lines).

## Scope check

`git show --stat 80b3a17`:

| File | Change |
| --- | --- |
| `docs/phase0_impl_notes.md` | +7 / -1 |
| `fw/phase0/phase0_hw.h` | +9 / -2 |
| `reports/phase4_m2_stale_reference_repair.md` | +110 (new) |

No RTL, host tools, scripts, constraints, QSF, generated outputs, firmware semantics, or stale untracked files were modified. PASS.

## Current-state correctness

`fw/phase0/phase0_hw.h` header comment (post-repair) now reads:

> "Phase 0 memory map for the live RV32I control subsystem ... The earlier deterministic bring-up agent rtl/control/phase0_soc_stub.v was retired in Phase 0 task-9d00cc2f and the dead file was removed in Phase 4 M2 (commit 5db0378)."

`docs/phase0_impl_notes.md` adds a new section:

> "Update for Phase 4 M2 (`task-0692867c`, commit `5db0378`): rtl/control/phase0_soc_stub.v has been removed from the source tree ... All earlier update sections in this document that mention rtl/control/phase0_soc_stub.v describe historical Phase 0 milestones ... They are kept as accurate records of how the design got here, but the file itself no longer exists in the live tree."

That section is appended at the end of the existing update chain, so prior `task-9d00cc2f` / `task-8ee45684` / `task-4ad912d3` / `task-e5e0096b` paragraphs are explicitly framed as historical.

The diff also incidentally replaced prior GBK mojibake with plain ASCII double quotes around the phrase "request queued for handoff" on line 269 of `docs/phase0_impl_notes.md`. Same hygiene goal, consistent with the report's ASCII-only claim.

PASS.

## Stub-reference grep gate

`grep_search "phase0_soc_stub" excluding reports/, tmp/, sim*/`:

| Path | Lines | Live? |
| --- | --- | --- |
| `fw/phase0/phase0_hw.h` | 11 | Authoritative current-state note describing the deletion. Safe. |
| `docs/phase0_impl_notes.md` | 202, 261, 294, 302, 311, 322, 323 | Two are inside the new authoritative current-state section (322, 323); the rest sit under explicit historical "Update for `task-...`" headers. The new section reclassifies them as historical records. Safe. |

No live RTL/scripts/QSF/test-bench reference remains. PASS.

## ASCII check

All three edited files: 0 non-ASCII bytes.

| File | Size | Non-ASCII |
| --- | --- | --- |
| `docs/phase0_impl_notes.md` | 48,860 | 0 |
| `fw/phase0/phase0_hw.h` | 6,761 | 0 |
| `reports/phase4_m2_stale_reference_repair.md` | 5,189 | 0 |

PASS.

## Firmware / ROM

Existing `fw/phase0/build/phase0.bin` = 3,724 bytes = **931 words**, matching the accepted M3b/M9/M2 baseline. Source firmware is unchanged at HEAD; the existing artifact remains authoritative. PASS.

A fresh firmware rebuild was not run because the only firmware-side change is a header comment with no preprocessor or symbol effect; image bytes cannot change.

## Hardware skip

Hardware UART/audio is not required and not run. The change is docs/comment/report-only and cannot affect synthesis or runtime behavior. PASS by inertia.

## Final verdict

**PASS.** Implementer commit `80b3a17` repairs the stale stub references cleanly. Phase 4 M2 cleanup chain is now self-consistent and ready for next-step planning.
