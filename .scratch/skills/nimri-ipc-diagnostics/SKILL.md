# Skill: Diagnostics and Explainability

## Purpose
Keep `nimri-ipc` diagnostics clear for downstream consumers by ensuring typed errors, event traces, and formatted debug output stay consistent with protocol behavior.

## Use This Skill When
- Editing error types/messages.
- Adding debug/trace formatting for requests/events.
- Improving developer-facing explanations for parse or transport failures.
- Auditing consistency between raw protocol data and surfaced diagnostics.

## Primary Targets
- `src/events.nim`
- `src/client.nim`
- `src/models.nim`
- `src/nimri_ipc.nim`
- `tests/**` (especially failure-path fixtures)

## Workflow
1. Locate current behavior.
- Identify where errors are produced and wrapped.
- Confirm whether diagnostics are public API or internal logs.

2. Make cohesive edits.
- Keep low-level parse errors close to decode boundaries.
- Add context at API edges without hiding root cause.

3. Keep error contracts stable.
- Preserve machine-readable structures where possible.
- If message text changes, keep semantic fields stable.

4. Validate.
- Run targeted tests for parse/transport failures.
- Confirm no regressions in success-path behavior.

## Guardrails
- Do not replace typed error channels with opaque strings.
- Do not lose source payload context needed for debugging.
- Do not leak sensitive environment details in user-facing output.

## Done Criteria
- Diagnostics remain precise and actionable.
- Error surfaces are consistent with typed contracts.
- Failure-path coverage is updated.
