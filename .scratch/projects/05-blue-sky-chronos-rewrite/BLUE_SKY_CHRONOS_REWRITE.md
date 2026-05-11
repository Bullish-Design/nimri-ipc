# BLUE_SKY_CHRONOS_REWRITE

## Mission
Build a **new** `nimri-ipc` from scratch as a **chronos-native** library with zero compatibility constraints with the current implementation. Priorities are correctness, concurrency safety, performance, and clear typed APIs.

## Blue-Sky Principles
1. Chronos-first design everywhere (runtime, I/O, timers, cancellation, synchronization).
2. Zero legacy asyncdispatch assumptions in API or internals.
3. Strictly typed protocol boundary with forward-compatible decoding.
4. Structured concurrency over ad-hoc task spawning.
5. Explicit lifecycle/state machines for client and stream.
6. Separate transport, codec, protocol, and high-level API layers.
7. High testability via deterministic mock transport and fuzz/property tests.

## Technology Choices (Fresh Stack)
- `chronos` for all async I/O, timers, cancellation, and event loop.
- `stew/results` (or existing `results`) for explicit `Result[T, E]` APIs.
- `json_serialization` (chronos ecosystem) for high-performance typed JSON codecs where practical.
- `chronicles` for structured logging (optional but recommended).
- `metrics`-friendly hooks via callbacks/interfaces (no hard dependency required).
- Optional dev/test tools:
  - `testutils/unittests` + Nim `unittest`
  - property/fuzz harness for decode robustness

## Proposed New Module Layout
Create a clean v2-style layout (can replace existing tree once stable):

- `src/nimri_ipc/runtime/types.nim`
  - core async/socket type aliases (chronos-native)
- `src/nimri_ipc/runtime/cancellation.nim`
  - cancellation tokens, scoped task groups
- `src/nimri_ipc/runtime/timeouts.nim`
  - timeout combinators (`withDeadline`, `withTimeoutResult`)
- `src/nimri_ipc/transport/unix_socket.nim`
  - connect/read/write/shutdown for Niri IPC socket
- `src/nimri_ipc/transport/framing.nim`
  - newline framing + incremental decode buffers
- `src/nimri_ipc/codec/json_codec.nim`
  - protocol JSON encode/decode and unknown-variant handling
- `src/nimri_ipc/protocol/models.nim`
  - domain entities + ID types
- `src/nimri_ipc/protocol/actions.nim`
  - action enum/builders
- `src/nimri_ipc/protocol/requests.nim`
  - request enum/builders
- `src/nimri_ipc/protocol/responses.nim`
  - typed response decode
- `src/nimri_ipc/protocol/events.nim`
  - typed event decode + classification
- `src/nimri_ipc/api/client.nim`
  - command API
- `src/nimri_ipc/api/event_stream.nim`
  - subscription/event API
- `src/nimri_ipc/api/session.nim`
  - optional dual-connection session abstraction (client + stream lifecycle)
- `src/nimri_ipc/errors.nim`
  - rich typed errors with context
- `src/nimri_ipc/nimri_ipc.nim`
  - curated public exports

## API Redesign (No Compatibility Constraints)
### Client
- `proc connect*(cfg: ConnectConfig): Future[Result[NiriClient, NimriIpcError]]`
- `proc request*[T](c: NiriClient, req: NiriRequest[T], timeout: Duration): Future[Result[T, NimriIpcError]]`
- Strongly typed request phantom/generic result mapping instead of broad response unions where beneficial.

### Event Stream
- `proc subscribe*(cfg: ConnectConfig): Future[Result[NiriEventStream, NimriIpcError]]`
- `proc next*(s: NiriEventStream, timeout: Duration): Future[Result[NiriEvent, NimriIpcError]]`
- `proc recvUntil*(s: NiriEventStream, pred: EventPredicate, deadline: Moment): Future[Result[NiriEvent, NimriIpcError]]`

### Session (new opportunity)
- `proc openSession*(cfg: ConnectConfig): Future[Result[NiriSession, NimriIpcError]]`
- manages two independent chronos transports under one scoped lifecycle.

## Error Model (Upgrade)
Use tagged error categories with machine-parseable context:
- `TransportError` (`connect`, `read`, `write`, `closed`, `osError`, `errno`)
- `TimeoutError` (`op`, `deadline`, `elapsed`)
- `ProtocolError` (`unexpectedVariant`, `handshakeFailure`, `framingViolation`)
- `DecodeError` (`jsonPath`, `rawSnippet`, `reason`)
- `InternalInvariantError` (state machine misuse)

Include:
- operation name
- endpoint/socket path
- retryability hint (`bool`)
- optional wrapped cause

## Chronos-First Concurrency Model
1. No shared mutable state across client and stream objects.
2. Per-connection internal state machine:
   - `Init -> Connecting -> Ready -> Closing -> Closed`
3. Use scoped task groups for background receive loops (if introduced).
4. Use explicit cancellation propagation on close.
5. All timeout paths must cancel outstanding operations and await cleanup.

## Performance Opportunities (from scratch)
1. Replace string-heavy line handling with reusable buffers.
2. Centralize framing parser for fewer allocations.
3. Fast-path JSON decode for common responses/events.
4. Optional pooled buffer allocator for high event throughput.
5. Benchmark large event streams (`raw_stream.txt` replay) for throughput/latency.

## Security and Robustness
1. Enforce maximum frame size to prevent unbounded memory growth.
2. Validate UTF-8 and malformed JSON with bounded error payload snippets.
3. Harden against partial lines, rapid reconnect cycles, and abrupt peer closes.
4. Ensure close is idempotent and race-safe.

## Testing Strategy (Rebuilt)
### Unit
- codec roundtrip tests for all request/action/event/response variants
- error mapping tests by operation
- framing tests (partial, multi-frame, oversize frame)

### Integration (mock chronos server)
- handshake success/failure
- timeout/read/write failure paths
- event ordering and backpressure behavior
- cancellation during in-flight operations

### Property/Fuzz
- random JSON/object field order
- unknown enum variants/extra fields
- malformed frame injection

### Live (optional, gated by `NIRI_SOCKET`)
- command queries against real Niri
- event stream decode under real compositor activity

### Concurrency Stress
- repeated connect/send/close loops
- parallel client instances
- stream consumer cancellation storms

## Observability Plan
1. Add structured debug logs for connect, request, response, event, close.
2. Add trace IDs per request/stream connection for correlation.
3. Optional hooks for metrics:
   - request latency
   - timeout count
   - decode failure count
   - reconnect attempts (if reconnection is ever added)

## Dependency Plan
Update `nimri_ipc.nimble` aggressively for new baseline:
- `requires "nim >= 2.0.0"` (or bump if chronos constraints require)
- `requires "chronos >= <pinned-min>"`
- `requires "results >= <min>"` (or move to stew/results and standardize)
- optional: `requires "chronicles >= <min>"`

Pin tested versions in devenv and CI for reproducibility.

## Implementation Phases

### Phase 1: New Skeleton and Contracts
1. Create new module tree (`runtime`, `transport`, `protocol`, `api`).
2. Define canonical core types (`ConnectConfig`, error tags, state enums).
3. Define public API signatures and finalize before implementation.

Exit criteria:
- Compiles with stub implementations.

### Phase 2: Transport + Framing Core
1. Implement chronos Unix socket transport.
2. Implement robust newline framing parser with max-size limits.
3. Implement timeout/cancellation helpers.

Exit criteria:
- Transport/framing tests pass in isolation.

### Phase 3: Protocol Codec Layer
1. Implement request/action encoders.
2. Implement response/event decoders with unknown-variant strategy.
3. Add exhaustive fixture tests and fuzz harness.

Exit criteria:
- Protocol tests pass and fixtures validate.

### Phase 4: Client API
1. Implement `connect`, typed `request`, and convenience query/action wrappers.
2. Implement strict lifecycle transitions and close semantics.

Exit criteria:
- Client unit + mock integration tests pass.

### Phase 5: Event Stream API
1. Implement subscribe handshake and `next`/`recvUntil`.
2. Validate timeout and cancellation behavior.
3. Optional bounded internal queue mode for consumer decoupling.

Exit criteria:
- Stream integration + stress tests pass.

### Phase 6: Session Abstraction + Polish
1. Implement optional `NiriSession` dual-connection abstraction.
2. Add observability hooks.
3. Add benchmarks and profile-driven optimizations.

Exit criteria:
- Session tests pass, benchmark baselines captured.

### Phase 7: Cutover
1. Replace old exports with new API surface.
2. Remove old modules entirely.
3. Rewrite README/docs/examples for chronos-native usage.

Exit criteria:
- No legacy asyncdispatch/asyncnet modules remain.

## Breaking Changes We Should Intentionally Embrace
1. New naming and module paths where clarity improves.
2. New typed request/response API with generics.
3. New error categories and payload format.
4. New timeout/deadline semantics where they improve correctness.
5. Removal of any API that obscures protocol invariants.

## CI and Quality Gates
All commands run inside devenv shell.

1. `devenv shell -- nim c --warningAsError:on --hints:off src/nimri_ipc/nimri_ipc.nim`
2. `devenv shell -- nimble test`
3. `devenv shell -- nim c -r tests/test_client.nim`
4. `devenv shell -- nim c -r tests/test_stream.nim`
5. Add stress target and fixture replay target as separate CI jobs.

Required merge gates:
- 100% pass on unit + integration
- no asyncdispatch/asyncnet imports in repo
- no flaky timeout tests across repeated CI runs

## Definition of Done
1. Entire async stack is chronos-native.
2. Library architecture is cleanly layered and documented.
3. Tests cover happy path, error path, cancellation path, stress path.
4. Benchmarks demonstrate acceptable throughput/latency.
5. Public docs reflect new from-scratch API and semantics.

## Suggested Execution Cadence
- Week 1: Phases 1-2
- Week 2: Phase 3
- Week 3: Phases 4-5
- Week 4: Phases 6-7 + stabilization

## Immediate Next Tasks
1. Finalize dependency set (`chronos`, `results` vs `stew/results`, optional `chronicles`).
2. Draft new public API signatures in `api/*.nim` stubs.
3. Implement transport/framing first and lock timeout semantics with tests before higher layers.
