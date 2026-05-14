# Phase 3 M3a Guard Optimization

Date: 2026-05-14 | Agent: claude-implementer | Commit: `40c1f47`

**ROM: 791/1024 (under 800). Unconditional reset guard.**

Replaced 4 conditional status-check+reset blocks with unconditional resets. Resetting an idle voice is harmless (delay line already zero). Saved 21 words (812→791).

Verifier: `!N006A7FFF\r\n` (A4), `!N00407FFF\r\n` (higher), `!N007F4000\r\n` (lower, soft). Bare `!N\r\n` unchanged M2a behavior.
