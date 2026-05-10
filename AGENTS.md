# AGENTS.md

## Purpose
This repository builds `nimri-ipc`, a Nim library for Niri IPC. It is extracted from the broader `nirip`/`sidebard` concept and provides a reusable, typed, async client layer.

Primary goal:
- Be the single source of truth for Niri IPC transport, request/response types, actions, and event-stream parsing for Nim projects.

## Library Scope
`nimri-ipc` owns:
- Unix socket connection management to the Niri IPC socket.
- Typed request builders.
- Typed response models for windows/workspaces/outputs and related objects.
- Event stream parser and typed event model.
- Action constructors and execution helpers.
- Serialization/deserialization boundaries and protocol compatibility checks.

`nimri-ipc` does not own:
- Workspace/profile orchestration policy.
- Reconciliation/planning loops.
- State persistence for higher-level tools.
- App-level plugins and launch semantics.

## Architecture Targets
Suggested module shape for this repo:
- `src/nimri_ipc.nim` (public API)
- `src/client.nim` (async socket transport)
- `src/models.nim` (typed Niri domain models)
- `src/requests.nim` (typed request builders)
- `src/actions.nim` (typed action constructors)
- `src/events.nim` (event stream parse + event types)

If implementation paths differ, preserve this separation of concerns.

## Design Principles
1. Strong typing over ad-hoc JSON maps.
2. Explicit error channels (`Result[T, E]`-style patterns) for all fallible operations.
3. Deterministic parsing and predictable model evolution.
4. Minimal hidden behavior in transport (no implicit retries without opt-in).
5. Backward-compatible public API changes unless a version bump is intentional.

## Protocol Boundaries
- Treat raw JSON as an edge concern.
- Convert to typed models immediately after decode.
- Keep request/response/event schemas versioned and testable.
- Prefer additive model evolution; gate breaking changes.

## Testing Expectations
Focus tests on:
- Decode/encode round trips for requests/responses/events.
- Event stream framing and partial/chunked message handling.
- Error behavior for malformed payloads and socket failures.
- Compatibility fixtures from real Niri responses when available.

Recommended layout:
- `tests/fixtures/` for captured protocol payloads.
- Unit tests per module (`client`, `models`, `events`, `actions`, `requests`).

## Agent Workflow
1. Identify whether change is transport, typing, parsing, or API surface.
2. Keep edits in the narrowest relevant module.
3. Add/update tests with each behavioral change.
4. Validate build/tests locally before finalizing.
5. Document any protocol assumptions in code comments and commit notes.

## Skills In This Repo
Skills live under `.scratch/skills` and are repurposed for `nimri-ipc`:
- `nimri-ipc-structure`: library architecture navigation.
- `nimri-ipc-contracts`: IPC request/action/event consistency and ownership.
- `nimri-ipc-diagnostics`: event/model diagnostics and explainability guidance.
- `nimri-ipc-validation`: Nim build/test validation ladder.

## Practical Conventions
- Keep public API small and explicit.
- Avoid leaking internal transport types through exported signatures.
- Prefer immutable model transforms in parsing code.
- Do not couple this repo to sidebard/nirip-specific planner/state logic.
- When uncertain about protocol fields, add fixture-driven tests before refactors.
