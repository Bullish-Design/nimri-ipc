# Skill: IPC Contract System (Requests, Actions, Events)

## Purpose
Implement and maintain the repository's protocol ownership model for `nimri-ipc`:
- Requests and actions are typed and canonical.
- Responses and events decode into typed models.
- Transport is isolated from planner/app policy.

## Use This Skill When
- Adding/changing/removing IPC requests.
- Adding/changing action payload helpers.
- Extending event stream parsing or event types.
- Auditing ownership drift between modules.
- Investigating protocol regressions.

## Canonical Ownership
- Public exports: `src/nimri_ipc.nim`
- Socket transport/lifecycle: `src/client.nim`
- Requests: `src/requests.nim`
- Actions: `src/actions.nim`
- Models: `src/models.nim`
- Events: `src/events.nim`

## Ownership Rules (Normative)
1. Request payload schema lives in `requests`.
2. Action constructors live in `actions`.
3. Event decoding/framing logic lives in `events`.
4. Transport/retry/socket details live in `client`.
5. Shared domain types live in `models`.
6. Orchestration logic (planning/reconciliation/state policy) must not be added here.

## Workflow
1. Classify change.
- New protocol command -> `requests` and possibly `actions`.
- New event payload -> `events` + `models`.
- Connection behavior -> `client`.

2. Edit canonical files only.
- Keep protocol constants and field mappings in one place.
- Preserve backward compatibility in exported APIs when possible.

3. Add fixture-driven tests.
- Record/author representative JSON payloads.
- Assert parse and typed mapping behavior.

4. Validate.
- Build library and run tests (see `nimri-ipc-validation`).

5. Report.
- Files changed, protocol assumptions, tests run, residual risks.

## Guardrails
- Never duplicate schema definitions across modules.
- Never silently drop unknown protocol fields without intent.
- Never couple client internals to app-specific behavior.
- Never make breaking API changes without explicit note.

## Done Criteria
- Protocol behavior implemented in canonical modules only.
- Typed request/action/event boundaries remain clear.
- Tests cover new/changed protocol surface.
