# Phase 4 M2 Stale Reference Repair

Date: 2026-05-16
Implementer: kiro-implementer `0c4c86c9-f7af-4977-863a-610f63c0dcab`
Task: `task-1cdcc0c9`
Branch: `codex/phase1c-uart-boundary-fix`
Predecessor commit (M2 implementation): `5db0378`
Predecessor commit (M2 report hygiene): `0c83ae3`

## Summary

Phase 4 M2 (`task-0692867c`, commit `5db0378`) deleted the dead RTL source
`rtl/control/phase0_soc_stub.v`. The deletion itself was correct: the file was
not in the QSF, was not instantiated by the top, was not in any active
testbench or build script, and was not referenced by firmware. Verifier
acceptance (`reports/phase4_m2_reclamation_validation.md`) confirmed that.

However, two live (non-historical) references to the deleted file remained
outside `reports/`, `tmp/`, and ModelSim work caches:

1. `docs/phase0_impl_notes.md` -- multiple update sections under earlier
   Phase 0 milestones (`task-8ee45684`, `task-4ad912d3`, `task-09810cec`,
   `task-e5e0096b`) describe behavior the stub used to provide, written in
   present tense. Without an authoritative current-state note, those
   sections could be misread as describing the live tree.
2. `fw/phase0/phase0_hw.h` -- header comment said "The current RTL still
   uses phase0_soc_stub.v, but keeping the firmware contract stable now
   makes later CPU integration smaller and clearer." That sentence is now
   factually wrong: the live RTL has been the RV32I subsystem since
   `task-9d00cc2f`, and the stub file no longer exists.

This task repairs only documentation and a comment. No RTL, firmware code
behavior, generated outputs, QSF/project settings, constraints, host tools,
or test/sim collateral are changed.

## Files Changed

| Path | Action | Notes |
| --- | --- | --- |
| `docs/phase0_impl_notes.md` | edit | Appended a new "Update for Phase 4 M2" section immediately before `## File Map`. The section states the stub was deleted in M2 (commit `5db0378`), describes the current RV32I-based control plane, and explicitly labels all earlier stub references in the same document as historical milestone notes. |
| `fw/phase0/phase0_hw.h` | edit | Replaced the stale 4-line comment block at the top of the file with a current description: the Phase 0 control plane is the RV32I subsystem and the stub was retired in `task-9d00cc2f` and removed in Phase 4 M2 (commit `5db0378`). Keeps the rest of the header (memory map, register offsets, default values) untouched. |
| `reports/phase4_m2_stale_reference_repair.md` | new | This report. |

The verifier report `reports/phase4_m2_reclamation_validation.md` is
intentionally not modified. Its conclusions about the M2 build/sim/source
dependencies are correct as written; the live doc/comment cleanup is
recorded here separately to keep the verifier's evidence intact.

## Validation

### git grep for live stub references

After the repair, the only `phase0_soc_stub` matches outside `reports/`,
`tmp/`, and `sim*/` are the three new explicit-historical references in
`docs/phase0_impl_notes.md`'s new Phase 4 M2 update section, which
explicitly state the file was deleted. The pre-repair five matches in the
historical update sections remain in the document, but they are now
clearly framed as historical records by the new authoritative section
appended just before `## File Map`.

The header comment match in `fw/phase0/phase0_hw.h` is gone.

### ASCII-only check

`docs/phase0_impl_notes.md`, `fw/phase0/phase0_hw.h`, and
`reports/phase4_m2_stale_reference_repair.md` are all ASCII after the
repair. Verified via grep for any byte outside the `0x00..0x7F` range; no
matches.

### Firmware build

`fw/phase0/build.ps1` was rerun after the comment-only header edit. The
build produces the same binaries as before the repair; the firmware ROM
word count remains `931` (unchanged from the M2 baseline anchor).

### Diff scope

The repair commit touches only:

```
docs/phase0_impl_notes.md
fw/phase0/phase0_hw.h
reports/phase4_m2_stale_reference_repair.md
```

No RTL, scripts, constraints, QSF, generated outputs, or test/sim
collateral are touched.

## Why historical references were not deleted

Earlier update sections in `docs/phase0_impl_notes.md` are deliberately
preserved as a record of how the Phase 0 design evolved. Editing them in
place would lose that history without adding clarity. The new Phase 4 M2
update section provides the authoritative current-state framing; the
older sections now read as the historical context they always were.

This matches the convention already used in this document, where earlier
updates (for example the "selector 2" waveform-label finding) are noted
as resolved later by a specific task rather than being rewritten in the
original section.

## Outcome

- The live tree no longer claims `rtl/control/phase0_soc_stub.v` exists
  or is in use.
- Historical Phase 0 milestone notes are preserved with explicit
  framing that distinguishes them from the current state.
- Firmware build is unaffected (ROM remains 931 words).
- Repair commit is doc/comment/report-only; verifier acceptance of
  Phase 4 M2 stands.
