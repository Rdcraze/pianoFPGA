# Phase 3 M3b Bare-Command Compatibility Review

Date: 2026-05-14
Agent: codex-orchestrator `1c005a25-956c-4b69-9b69-9bf3cd9a8d68`
Related tasks: `task-98960f31`, `task-8b603dfd`

## Verdict

M3b is verifier-ready with a narrow firmware ROM exception.

The firmware slice correctly made parameterized `!NLLLLVVVV` commands write loop length and velocity to the selected physical voice. The follow-up compatibility fix correctly restores fixed-note behavior for bare `!N\r\n` by writing default per-voice loop length and velocity to the selected physical voice before triggering.

## Exception

The M3b firmware hard gate was 900 ROM words. The compatibility fix builds at 902 / 1,024 words, exceeding the gate by 2 words.

This exception is accepted for hardware validation because the extra write is required to preserve M2a/M3a bare `!N` compatibility after parameterized commands. Without it, a bare `!N` could reuse a previously retuned physical voice and fail the fixed-note contract.

The verifier must record this exception explicitly and treat 902 words as a candidate M3b baseline only if hardware validation passes.

## Verifier Focus

- Confirm bare `!N\r\n` remains fixed-note-compatible after at least one parameterized command retunes a voice.
- Confirm rapid parameterized commands can create simultaneous different-pitch physical voices.
- Confirm malformed parameterized commands still reject cleanly.
- Confirm UART compatibility and `K=0`, `X=0` for valid command profiles.
