# AGENTS.md

## Purpose
This repository builds `nimri-ipc`, a Nim library for typed, async communication with the Niri Wayland compositor over its IPC socket. It is the single source of truth for Niri IPC transport, domain types, request/response encoding, actions, and event-stream parsing for Nim projects.

## Library Scope
`nimri-ipc` owns:
- Unix socket connection lifecycle (connect, send, receive, close).
- JSON codec for Niri's serde externally-tagged enum wire format.
- Typed Nim models for all Niri domain objects (windows, workspaces, outputs, etc.).
- Typed request construction and response decoding.
- Typed action constructors for all compositor actions (~120 variants).
- Event stream framing, incremental parsing, and typed event emission (~20 event types).
- Structured error model covering transport, protocol, and decode failures.
- Forward-compatibility handling for unknown fields and enum variants.

`nimri-ipc` does not own:
- Configuration file formats or loaders.
- Reconciliation, planning, or state diffing logic.
- Persistent state storage.
- CLI commands, UX policy, or orchestration workflows.
- Application-specific integrations (browser tabs, editor sessions, etc.).

## Architecture
Module structure under `src/nimri_ipc/`:

| Module | Role | I/O |
|---|---|---|
| `errors.nim` | `NimriIpcError` type hierarchy | No |
| `codec.nim` | Tagged-union JSON encode/decode engine (internal) | No |
| `models.nim` | All Niri domain types and ID types | No |
| `requests.nim` | `NiriRequest` enum, query constructors, `NiriResponse` decode | No |
| `actions.nim` | `NiriAction` enum, action constructors | No |
| `events.nim` | `NiriEvent` enum, event decode, classification | No |
| `client.nim` | Command connection (send request, get response) | Yes |
| `stream.nim` | Event stream connection (subscribe, iterate events) | Yes |
| `internal/transport.nim` | Shared socket utilities (path resolution, connect) | Yes |
| `nimri_ipc.nim` | Public re-exports only | No |

Key architectural decisions:
- **Separate command and event connections.** `NiriClient` handles request-response. `NiriEventStream` handles event streaming. They share no mutable state and do not depend on each other.
- **`codec.nim` is the critical path.** Niri uses serde externally-tagged enum encoding. This module provides the macro/template system that all other modules depend on for JSON handling.
- **Forward compatibility by default.** Unknown JSON fields are silently ignored. Unknown enum variants decode to `Unknown` sentinels. Unknown events decode to `UnknownEvent`.

## Dependency Rules
```
nimri_ipc.nim  ->  re-exports all public modules
client.nim     ->  codec, models, requests, actions, errors, internal/transport
stream.nim     ->  codec, models, events, errors, internal/transport
requests.nim   ->  codec, models, actions
actions.nim    ->  codec, models
events.nim     ->  codec, models
models.nim     ->  codec
errors.nim     ->  (no internal deps)
codec.nim      ->  (no internal deps)
```

## Forbidden Couplings
- `client.nim` and `stream.nim` MUST NOT depend on each other.
- `actions.nim` MUST NOT perform I/O or import transport modules.
- `events.nim` MUST NOT depend on request/action modules.
- `models.nim` MUST NOT import client, stream, or error modules.
- No module may depend on orchestrator, planner, or policy types.

## Development Environment

**All compilation, testing, and example execution MUST be done inside the devenv shell.** The devenv provides the correct versions of `nim`, `nimble`, and all required tooling. Do not use system-installed Nim or Nimble.

### Entering the devenv shell
```bash
devenv shell
```

This drops you into a shell with `nim`, `nimble`, and `git` available at the correct versions. The `enterShell` hook prints version info to confirm the environment is active.

### Common commands (all run inside devenv shell)
```bash
# Compile the library
nim c --hints:off src/nimri_ipc/nimri_ipc.nim

# Run all tests
nimble test

# Run a single test file
nim c -r tests/test_codec.nim

# Compile with warnings as errors
nim c --warningAsError:on --hints:off src/nimri_ipc/nimri_ipc.nim

# Generate documentation
nim doc --project src/nimri_ipc/nimri_ipc.nim

# Install dependencies
nimble install -d
```

### Why devenv is required
- Ensures consistent Nim and Nimble versions across all contributors and CI.
- Avoids version mismatch bugs between system Nim and project requirements (Nim >= 2.0).
- The nimble package and all test commands assume the devenv-provided toolchain.
- Example scripts and fixture capture commands are written for the devenv environment.

### Agent rule
When an agent needs to compile code, run tests, execute examples, or invoke any Nim/Nimble command, it MUST first enter the devenv shell (or confirm it is already inside one). The simplest approach is to prefix commands:
```bash
devenv shell -- nimble test
devenv shell -- nim c -r tests/test_codec.nim
```

Or enter the shell interactively and run commands within it. Never invoke bare `nim` or `nimble` outside the devenv.

## Technology Stack
- Nim >= 2.0 (ORC memory management)
- `std/asyncdispatch` for async I/O
- `std/json` for JSON parsing
- `results` package for `Result[T, E]` types
- `std/options` for nullable values

## Design Principles
1. Strong typing over ad-hoc JSON maps.
2. Explicit error channels (`Result[T, E]`) for all fallible operations.
3. Deterministic parsing and predictable model evolution.
4. No implicit retries, reconnection, or hidden behavior in transport.
5. Value types for all domain models (not `ref`).
6. `snake_case` JSON field names map to `camelCase` Nim fields.

## Testing Expectations

**All tests MUST be run inside the devenv shell.**

Tests are organized per-module in `tests/`:
- `test_codec.nim` — tagged-union encode/decode, frame buffer, field extraction.
- `test_models.nim` — entity decode from fixtures, ID types, enum mapping.
- `test_requests.nim` — request encoding, response decoding from fixtures.
- `test_actions.nim` — action encoding, parameterized types.
- `test_events.nim` — event decode from fixtures, forward compatibility, classification.
- `test_client.nim` — mock socket round-trips, error paths, live integration.
- `test_stream.nim` — frame parsing, protocol handshake, waitFor, live integration.

Fixtures in `tests/fixtures/responses/` and `tests/fixtures/events/`, captured from real Niri output and tagged with the niri version.

Live integration tests require `NIRI_SOCKET` to be set and skip cleanly otherwise.

### Running tests
```bash
# Enter devenv first
devenv shell

# Full suite
nimble test

# Single module
nim c -r tests/test_codec.nim
nim c -r tests/test_models.nim

# With verbose output
nim c -r -d:nimUnittestOutputLevel=PRINT_ALL tests/test_codec.nim
```

### Fixture capture (inside devenv shell, with Niri running)
```bash
niri msg -j version        > tests/fixtures/responses/version.json
niri msg -j windows        > tests/fixtures/responses/windows.json
niri msg -j workspaces     > tests/fixtures/responses/workspaces.json
niri msg -j outputs        > tests/fixtures/responses/outputs.json
niri msg -j focused-window > tests/fixtures/responses/focused_window.json
niri msg -j focused-output > tests/fixtures/responses/focused_output.json
niri msg -j layers         > tests/fixtures/responses/layers.json
niri msg -j keyboard-layouts > tests/fixtures/responses/keyboard_layouts.json
timeout 10 niri msg event-stream > tests/fixtures/events/raw_stream.txt
```

## Agent Workflow
1. **Enter devenv shell** before any compilation, testing, or example execution.
2. Identify whether change is transport, typing, parsing, or API surface.
3. Keep edits in the narrowest relevant module.
4. Add/update tests with each behavioral change.
5. Run tests inside devenv shell (`devenv shell -- nimble test` or equivalent).
6. Document any protocol assumptions in code comments and commit notes.
7. Respect the dependency rules — never introduce forbidden couplings.
