# NIMRI_IPC_SPEC

## 1. Purpose
This document defines the implementation specification for `nimri-ipc`, a reusable Nim library for typed, async interaction with Niri IPC.

This spec is normative for library behavior and interfaces. Higher-level orchestration behavior is explicitly out of scope.

## 2. Scope
### 2.1 In Scope
- IPC socket connection management.
- Request encode and response decode.
- Typed domain models for Niri state objects.
- Typed action constructors.
- Event stream framing and parse.
- Typed error model.
- Test fixtures and validation requirements.

### 2.2 Out of Scope
- Reconciliation/planning logic.
- Profile formats and config loaders.
- State persistence.
- CLI policy (`load`, `freeze`, `diff`, etc.).
- App-specific capture/restore integrations.

## 3. Repository and Module Layout
Required top-level structure:

```text
src/
  nimri_ipc.nim
  client.nim
  models.nim
  requests.nim
  actions.nim
  events.nim
tests/
  fixtures/
  test_client.nim
  test_models.nim
  test_requests.nim
  test_actions.nim
  test_events.nim
```

Equivalent file naming is acceptable if concerns remain separated exactly as above.

## 4. Architecture Contracts
### 4.1 Layer Responsibilities
- `models.nim`: Canonical typed data structures and enums.
- `requests.nim`: Typed request construction and request serialization helpers.
- `actions.nim`: Action-level request constructors over protocol action payloads.
- `events.nim`: Event frame decode, event payload parse, typed event values.
- `client.nim`: Socket lifecycle, async send/receive, request correlation, stream handling.
- `nimri_ipc.nim`: Public exports only; no protocol logic duplication.

### 4.2 Forbidden Couplings
- `client.nim` MUST NOT define business-level planner policy.
- `events.nim` MUST NOT depend on orchestrator state models.
- `actions.nim` MUST NOT perform I/O.
- `nimri_ipc.nim` MUST NOT duplicate decode/encode code from internal modules.

## 5. Public API Surface
The library MUST expose a minimal public API equivalent to:

1. Client lifecycle
- `openClient(config): Future[Result[NiriClient, NimriIpcError]]`
- `close(client): Future[void]`

2. Command/request execution
- `send(client, request): Future[Result[NiriResponse, NimriIpcError]]`
- `sendTyped[T](client, request): Future[Result[T, NimriIpcError]]`

3. Event stream
- `subscribeEvents(client, filter?): Future[Result[NiriEventStream, NimriIpcError]]`
- `nextEvent(stream, timeout?): Future[Result[NiriEvent, NimriIpcError]]`

4. Convenience state queries
- `getWindows(client)`, `getWorkspaces(client)`, `getOutputs(client)` returning typed models.

5. Action helpers
- Constructors for focus/move/layout actions that return typed request objects.

Exact proc names may vary, but these capabilities MUST exist and be exported.

## 6. Socket and Transport Spec
### 6.1 Socket Path Resolution
Resolution precedence MUST be:
1. Explicit caller-provided socket path.
2. `NIRI_SOCKET` environment variable.
3. Error `SocketPathMissing`.

### 6.2 Connection Behavior
- Client open MUST validate socket path format before connect attempt.
- Connect failure MUST return typed transport error with operation context.
- Close MUST be idempotent.

### 6.3 Request/Response Correlation
- Each command call MUST map one request to one response.
- Mismatched or malformed response frames MUST return parse/protocol errors.
- Timeouts MUST be explicit and configurable.

### 6.4 Reconnect Policy
- No implicit reconnect by default.
- Optional reconnect policy MAY be provided, but MUST be opt-in and documented.

## 7. Framing and Serialization
### 7.1 Frame Rules
- Protocol frames are newline-delimited JSON messages.
- Parser MUST support partial frame accumulation across reads.
- Parser MUST support multiple frames received in a single read.
- Invalid UTF-8 or invalid JSON frames MUST surface parse errors with frame context.

### 7.2 Serialization Rules
- Request serialization MUST produce stable field names matching protocol conventions.
- Optional fields MUST be omitted (not emitted as null) unless protocol requires null.
- Unknown response/event fields MUST be retained or tolerated according to compatibility policy.

## 8. Domain Models (`models.nim`)
### 8.1 Required Entity Families
Typed models MUST cover at least:
- Windows
- Workspaces
- Outputs
- Focus state
- IDs for window/workspace/output where protocol uses identifiers

### 8.2 Model Design Rules
- Use explicit Nim object/enum types; avoid untyped `JsonNode` in public API models.
- Enum decoding MUST handle unknown values via one of:
  - `Unknown` sentinel variant, or
  - typed decode error with source value.
- Public models SHOULD preserve protocol fidelity and avoid app-specific projections.

## 9. Requests and Actions
### 9.1 Request Layer (`requests.nim`)
- MUST define typed request envelopes and payload variants.
- MUST provide constructor helpers for query commands.
- MUST expose serialization boundary from typed request to JSON payload.

### 9.2 Action Layer (`actions.nim`)
- MUST provide typed constructors for frequently used Niri actions.
- MUST remain I/O free.
- MUST return request-compatible typed payloads.

### 9.3 Ownership Rule
Protocol command schema definitions MUST live in `requests.nim` and/or `actions.nim` only.

## 10. Events (`events.nim`)
### 10.1 Event Types
- MUST define typed event union/object hierarchy for known event categories.
- MUST include raw metadata needed for debugging (event kind, timestamp if present, source frame reference).

### 10.2 Event Stream Parser
- MUST parse incrementally from byte chunks.
- MUST emit events in receive order.
- MUST not drop valid events silently.
- MUST produce typed parser errors for malformed frames.

### 10.3 Event Filtering
- API MAY support caller-provided event filters.
- Filtering MUST occur after successful parse to preserve parser correctness semantics.

## 11. Error Model
Define a canonical error type family (`NimriIpcError`) with at least:
- `SocketPathMissing`
- `SocketOpenFailed`
- `SocketReadFailed`
- `SocketWriteFailed`
- `Timeout`
- `ProtocolViolation`
- `JsonEncodeError`
- `JsonDecodeError`
- `EventFrameError`
- `UnsupportedValue`

Each error value MUST include:
- operation context (e.g., `open`, `send:GetWindows`, `nextEvent`)
- human-readable message
- machine-usable kind enum
- optional source payload snippet where safe

## 12. Compatibility Policy
- Additive changes are preferred.
- Breaking type/API changes require explicit version bump.
- Unknown fields in inbound payloads SHOULD be tolerated unless safety requires rejection.
- Protocol assumptions MUST be pinned in tests/fixtures.

## 13. Performance and Reliability Requirements
### 13.1 Performance
- Event parse path SHOULD avoid unnecessary allocations.
- Batch reads with multi-frame decode MUST be supported.
- Command round-trip overhead SHOULD be limited to transport + parse cost without extra transformation layers.

### 13.2 Reliability
- Deterministic timeout behavior.
- No hidden retries unless explicitly enabled.
- Predictable behavior under bursty event streams.

## 14. Observability and Diagnostics
- Error values MUST preserve root-cause details.
- Optional debug hooks MAY expose raw frames for development.
- Default API behavior MUST remain clean and typed, not log-noisy.

## 15. Security and Safety
- No shell execution or process launching in this library.
- No filesystem persistence side effects.
- Do not expose environment variables in error text unless explicitly requested in debug mode.

## 16. Testing Specification
### 16.1 Required Test Categories
1. Request serialization tests.
2. Response decode tests from fixtures.
3. Event decode tests from fixtures.
4. Frame parser tests:
- partial frame over multiple chunks
- multiple frames in one chunk
- malformed frame between valid frames
5. Transport error-path tests (connect/read/write timeout/failure).
6. Unknown field/enum compatibility tests.

### 16.2 Fixture Requirements
- Store representative payloads in `tests/fixtures/`.
- Include both nominal and malformed samples.
- Name fixtures by API/event case for traceability.

### 16.3 Optional Integration Tier
- Live-socket tests MAY run when Niri is present.
- Integration tests MUST be skippable in CI environments without Niri.

## 17. Acceptance Criteria
Implementation satisfies this spec when:
1. All required modules and ownership boundaries are present.
2. Public API provides typed client/request/event capabilities.
3. Error model is typed and contextual.
4. Parser handles partial/multi-frame input correctly.
5. Test suite includes all required categories.
6. No orchestration policy has leaked into library modules.

## 18. Open Decisions (To Resolve Before v1.0)
1. Exact exported proc/type names.
2. Result type dependency (`std/result` equivalent vs third-party package).
3. Unknown enum handling mode (`Unknown` sentinel vs strict error).
4. Default timeout values.
5. Whether to expose raw `JsonNode` escape hatch as non-default API.

## 19. Change Control
Any change to this spec MUST:
1. Update this file.
2. State whether change is additive or breaking.
3. List impacted modules and tests.
4. Update `NIMRI_IPC_CONCEPT.md` if architectural intent changes.
