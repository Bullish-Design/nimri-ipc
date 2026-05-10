# NIMRI_IPC_CONCEPT

## Overview
`nimri-ipc` is a standalone Nim library that provides typed, async access to Niri IPC.

This concept is extracted from `REVISED_NIRIP_CONCEPT.md` and narrowed to the shared IPC layer (previously described as `niri-ipc-nim`). The library is intended to be reused by higher-level tools (for example workspace orchestrators) without embedding planner/state policy inside the IPC package.

## Core Intent
- Single reusable implementation of Niri socket protocol in Nim.
- Strongly typed requests, actions, responses, and events.
- Fast, deterministic event-stream parsing suitable for reconciler loops.
- Clean API boundary that supports multiple clients in the same ecosystem.

## Why This Library Exists
From the source concept, the strongest motivation for a shared IPC library is:
- Eliminate duplicated protocol code across projects.
- Share one typed model of windows/workspaces/outputs/actions/events.
- Fix protocol bugs once and propagate to all dependents.
- Keep IPC code independently testable with fixture-driven tests.
- Preserve performance and low-latency behavior for action->observe loops.

## Scope Definition
`nimri-ipc` owns:
- Socket connection lifecycle and async client operations.
- Request serialization and response deserialization.
- Typed domain models for Niri objects.
- Typed action construction helpers.
- Event-stream framing, parsing, and typed event emission.
- Protocol error surface and compatibility handling.

`nimri-ipc` does not own:
- Profile/config formats (TOML/YAML/other).
- Reconciler planning or operation algebra.
- State files / persistence for managed windows.
- Freeze/diff/doctor UX or CLI policy.
- App/plugin integration logic.

## Architectural Position
Higher-level architecture (from source concept) places `nimri-ipc` as infrastructure below:
- config loader
- planner (pure)
- matcher/freezer/diagnostics (pure)
- executor (effectful)

In that architecture, `nimri-ipc` is the only layer that touches compositor transport and protocol JSON.

## Proposed Package Layout
Recommended module layout for `nimri-ipc`:

```text
nimri-ipc/
├── src/
│   ├── nimri_ipc.nim      # public API
│   ├── client.nim         # async socket transport
│   ├── models.nim         # typed Niri models
│   ├── requests.nim       # typed request builders
│   ├── actions.nim        # typed action constructors
│   └── events.nim         # event stream parser + event types
└── tests/
    ├── fixtures/          # recorded Niri JSON payloads
    └── test_*.nim
```

## API and Type Principles
- Prefer closed, explicit Nim types over dynamic maps.
- Treat parse/transport failures as typed results, not hidden exceptions.
- Keep raw JSON at the boundary; decode immediately into typed values.
- Expose an API that is stable and minimal.
- Make event and action types exhaustive enough for compile-time checking.

## Event-Driven Operation Support
The source concept emphasizes event-confirmed execution loops. `nimri-ipc` should directly support this by providing:
- Typed event stream subscription.
- Reliable parsing under chunked/partial socket reads.
- Event classification suitable for confirmation checks (focus changed, window moved, workspace changed, etc.).
- Predictable timeout/error behavior for callers waiting on specific event predicates.

## Transport Responsibilities
Client behavior should include:
- Discover/accept Niri socket path from caller/environment.
- Open/close/reconnect policies with explicit caller control.
- Request/response correlation for command calls.
- Dedicated event stream handling (continuous feed).
- Backpressure-aware async reads/writes.

## Data Model Responsibilities
`models.nim` should define typed structures for at least:
- Windows
- Workspaces
- Outputs
- Focus-related entities
- IDs and protocol enums used across requests/events/actions

Key guideline: one canonical model set for all modules to avoid schema drift.

## Request and Action Layer
Split roles cleanly:
- `requests.nim`: protocol-level request payloads and query commands.
- `actions.nim`: higher-level constructors for action requests (move/focus/layout operations).

The split allows callers to use raw protocol requests when needed while still benefiting from ergonomic typed action helpers.

## Error and Diagnostics Contract
The source concept highlights explainability. For `nimri-ipc` this means:
- Structured parse errors with field/path context.
- Transport errors that preserve socket and operation context.
- Event parser diagnostics that identify malformed frames.
- Optional debug trace hooks without polluting default API behavior.

## Testing Strategy
Extracted testing expectations, applied to library scope:
- Fixture-based decode tests for responses and events.
- Encode/decode round-trip checks for requests/actions.
- Event stream framing tests for split/multi-message chunks.
- Negative tests for malformed payloads and protocol mismatches.
- Integration tests where feasible against a live Niri socket (optional tier).

## Versioning and Compatibility
Because multiple binaries depend on this package:
- Prefer additive schema/API changes.
- Gate breaking changes behind deliberate version bumps.
- Track protocol assumptions in tests and changelog notes.
- Treat unknown/extra fields as compatibility signals and handle intentionally.

## Performance and Reliability Targets
Derived from intended reconciler usage:
- Low-latency event delivery and decode.
- Minimal allocations in hot parsing paths where practical.
- Stable behavior under rapid event bursts.
- Deterministic behavior in timeout and retry edges.

## Integration Expectations for Callers
Callers (for example a `nirip`-style orchestrator) should be able to:
- Fetch typed snapshots (windows/workspaces/outputs).
- Execute typed actions.
- Subscribe to typed events and confirm expected outcomes.
- Compose their own pure planning logic above this library.

## Non-Goals (V1)
- Dynamic plugin runtime.
- Persistence/database layer.
- CLI orchestration commands (`load`, `freeze`, `diff`, etc.) inside this package.
- Application-specific capture/restore logic (browser tabs/editor sessions).

## Migration Note: Naming
This concept intentionally renames the prior `niri-ipc-nim` proposal to `nimri-ipc` for this repository.

Practical implication:
- Keep external API/module names consistent with `nimri-ipc` branding.
- Update internal docs, package manifest, and examples to avoid mixed naming.

## Acceptance Criteria for This Repo Direction
`nimri-ipc` is aligned with the extracted concept when:
1. The package exposes typed request/response/action/event APIs.
2. Socket transport and event parsing are implemented and tested independently.
3. No planner/state/config policy leaks into library modules.
4. Fixture coverage exists for representative real protocol payloads.
5. Documentation clearly positions the library as reusable IPC infrastructure.
