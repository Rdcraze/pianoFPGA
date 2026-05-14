# Phase 1C First Measurement Hook Contract Validation

Verifier: claude-verifier `e8db32f8-3c5f-4a11-bf2d-8f6e3ad76c4c`
Task: `task-366405b7` (re-validation)
Implementation task: `task-f9ffb452`
Implementation commit: `709081d`
Reviewed artifact: `reports/phase1c_first_measurement_hook_contract.md`
Prior validation: `task-fc35ad1e` (FAIL, three issues)

## Verdict

PASS.

All three issues from the original FAIL verdict are resolved. The contract is acceptable as design guidance only. Recommend orchestrator accept and create a distinct implementation task referencing this contract.

## Scope Review

PASS.

Commit `709081d` modifies one file only:

```
reports/phase1c_first_measurement_hook_contract.md | 38 +++++++++++++++++-----
1 file changed, 29 insertions(+), 9 deletions(-)
```

No RTL, firmware, constraints, build scripts, project files, bitstreams, host tools, existing reports, register behavior, or resource-affecting files were changed. `git status --short --untracked-files=normal` shows only unrelated untracked files.

## Issue Resolution

### Issue 1: CC/C parser collision (FIXED)

Original finding: contract claimed "CC does not collide with any single-character tag" — incorrect, the `([A-Z])` regex matches `C` from `CC`.

Revision (lines 57-72):
- Explicitly acknowledges the collision with a concrete code example showing the spurious `C` match.
- States "This is a blocking collision. The contract's earlier claim was incorrect."
- Specifies exact mitigation: `([A-Z])=` to `([A-Z]+)=` (greedy multi-character match).
- Declares parser update "a hard prerequisite for any firmware that emits CC."
- Requires regression tests on all accepted baseline captures.

Verified: `([A-Z]+)=` regex correctly parses `CC=00000064` as tag `CC`, preserves all existing single-character tags.

### Issue 2: CC value format (FIXED)

Original finding: contract described "up to 10 decimal digits" — inconsistent with existing 8-digit hex convention.

Revision (line 107): CC format is now `CC=NNNNNNNN` (tag + '=' + 8 hex digits, 12 characters total). Matches existing telemetry convention.

### Issue 3: Non-prefix UART change ambiguity (FIXED)

Original finding: ambiguous whether a multi-character tag constitutes a "non-prefix UART change."

Revision (lines 74-81):
- Defines "non-prefix" explicitly: tag insertion or reordering between existing tags that shifts byte offsets.
- Distinguishes from suffix extension: appending after the frozen order preserves all existing byte-offset expectations.
- CC is categorized as a suffix extension, not a non-prefix change.
- No-go gate updated with parenthetical clarification.

## Re-verified Items

### Single hook selection (PASS)

Unchanged from original: firmware report-service CPU cycle counter, exactly one hook.

### Lowest-risk choice (PASS)

Unchanged. Firmware-only, no RTL, no MMIO, no timing impact.

### Clear/set/snapshot semantics (PASS)

Unchanged. Unambiguous.

### Resource/timing/ROM risk estimates (PASS)

Unchanged from original, with updated UART bandwidth estimate (12 chars vs prior 15, reflecting hex format).

### Rollback criteria (PASS)

Unchanged. Seven concrete, measurable criteria.

### Blocked feature discipline (PASS)

Unchanged. All 16+ blocked features remain untouched. No-go gate #2 updated to reference the non-prefix clarification.

### Go/no-go gates (PASS)

Go gates unchanged. No-go gate #2 now includes parenthetical clarification referencing the suffix-extension definition.

## Residual Risks

- Parser regex `([A-Z]+)` is greedy — if a future tag name is a prefix of another tag (e.g., `CA` vs `CAT`), the greedy match would correctly match the longest form. This is the desired behavior and is safe as long as all tag names are prefix-free. `CC` is prefix-free relative to all existing single-letter tags.
- Software calibration loop (if CPU lacks hardware cycle counter) remains underspecified — calibration constant and approximation error must be documented during implementation.
- The contract does not specify whether `CC` uses uppercase or lowercase hex digits (`[0-9A-F]` vs `[0-9a-f]`). Existing telemetry uses uppercase. Implementation should match.

## Recommendation

Accept the contract as design guidance. Proceed to create a distinct implementation task scoped to:
- Firmware: counter variable, increment logic, UART formatting for `CC` tag (8-digit uppercase hex).
- Host parser: regex update `([A-Z])=` to `([A-Z]+)=` with regression tests on accepted baseline captures.
- Validation evidence bundle as specified in the contract (9 items).
