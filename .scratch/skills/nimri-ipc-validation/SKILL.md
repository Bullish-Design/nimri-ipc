# Skill: nimri-ipc Change Validation

## Purpose
Validate `nimri-ipc` changes with fast, reliable checks before finalizing, and report what is verified vs unverified.

## Use This Skill When
- Any source file in `src/` is edited.
- Public API or protocol mappings change.
- You need a concise validation report.

## Validation Ladder
1. Static sanity checks.
- Confirm edited symbols and references:
  - `rg "<symbol-or-field>" src tests -n`

2. Build validation.
- Run library build using the repo's preferred Nim/Nix workflow.

3. Test validation.
- Run targeted tests first (changed module scope), then broader suite as needed.
- Prioritize fixtures for request/response/event compatibility.

4. Contract checks.
- For protocol changes, verify typed models and decoders align.
- For public API changes, verify exports and downstream compile path.

## Reporting Template
- Files changed:
- Validation run:
- Result:
- Residual risks:

## Guardrails
- Do not claim runtime compositor behavior was tested unless it was.
- If full test suite cannot run, state exactly what was run.
- If protocol behavior changed, explicitly note fixture coverage status.
