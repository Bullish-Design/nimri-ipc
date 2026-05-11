# CHRONOS_REFACTOR_PLAN

## Objective
Refactor `nimri-ipc` so **all async runtime, socket I/O, timeouts, and async tests** use `chronos`, eliminating `std/asyncdispatch` and `std/asyncnet` from production code and tests.

## Current Async Surface (Baseline)
The async runtime is currently concentrated in:
- `src/nimri_ipc/internal/transport.nim` (`connectSocket`, `readLineWithTimeout`, `writeLine`)
- `src/nimri_ipc/client.nim` (`openClient`, `send`, typed request helpers, `close`)
- `src/nimri_ipc/stream.nim` (`openEventStream`, `next`, `waitFor`, `close`)
- Async tests using `waitFor`, `newAsyncSocket`, and `Future` in:
  - `tests/test_client.nim`
  - `tests/test_stream.nim`
  - `tests/test_nimri_ipc.nim`

Non-async modules (`codec`, `models`, `requests`, `actions`, `events`, `errors`) are runtime-agnostic and should remain unchanged unless type imports need cleanup.

## Target State
- `chronos` is the only async runtime dependency.
- Public async APIs return chronos futures and compile/run without `asyncdispatch`.
- Socket transport uses chronos stream/server primitives for Unix sockets.
- Timeout behavior is preserved (or improved with explicit chronos cancellation semantics).
- Test suite runs entirely on chronos event loop.
- No hidden compatibility shim requiring `asyncdispatch` at runtime.

## Non-Goals
- No behavior changes to Niri protocol encoding/decoding.
- No API redesign of domain models/actions/events.
- No transport-level retries/reconnect behavior changes.

## Migration Strategy
Use a **phased, compile-green migration** with one async boundary at a time, starting at transport and moving upward. Keep each phase independently testable.

---

## Phase 0: Preparation and Branch Hygiene
1. Create dedicated branch for chronos migration.
2. Capture baseline results:
   - `devenv shell -- nim c --hints:off src/nimri_ipc/nimri_ipc.nim`
   - `devenv shell -- nimble test`
3. Record current public async signatures from:
   - `client.nim`
   - `stream.nim`
   - `internal/transport.nim`
4. Freeze fixtures and note any currently skipped live tests.

Acceptance:
- Baseline compile/test status documented in project notes.

---

## Phase 1: Add Chronos Dependency and Runtime Guardrails
1. Update `nimri_ipc.nimble`:
   - Add `requires "chronos >= <chosen-min-version>"`.
   - Keep `results` requirement unchanged.
2. Decide minimum chronos version based on Nim 2.0 compatibility in devenv.
3. Add temporary compile-time guard in async modules (optional but recommended):
   - Explicitly fail if `asyncdispatch` is imported in production modules during migration.

Acceptance:
- `nimble install -d` resolves with chronos available.
- No behavioral changes yet.

---

## Phase 2: Transport Layer Port (`internal/transport.nim`)
This is the highest-leverage step; all higher layers depend on it.

1. Replace imports:
   - Remove `std/asyncdispatch`, `std/asyncnet`.
   - Add chronos primitives (future, async macro, stream transport, timers/cancellation APIs).
2. Replace socket type:
   - `AsyncSocket` -> chronos socket/stream type (single canonical type used across library).
3. Port `connectSocket`:
   - Use chronos Unix domain connect flow.
   - Preserve existing `Result[SocketType, NimriIpcError]` behavior.
4. Port `writeLine`:
   - Ensure full line + `\n` framing remains unchanged.
5. Port `readLineWithTimeout`:
   - Implement equivalent timeout semantics with chronos (`withTimeout` equivalent or `race` + timer).
   - Ensure timeout maps to `errors.timeout(operation, timeoutMs)`.
   - Ensure EOF maps to `connectionClosed(operation)`.
6. Ensure cancellation safety:
   - If timeout wins race, cancel/cleanup pending read future.

Acceptance:
- Transport module compiles using only chronos for async/runtime concerns.
- Existing transport behavior preserved for:
  - connect failure
  - read timeout
  - EOF/closed socket
  - write failure

---

## Phase 3: Client Layer Port (`client.nim`)
1. Replace imports:
   - Remove asyncdispatch/asyncnet dependencies.
   - Import chronos future/async APIs.
2. Update `NiriClient.socket` field to chronos socket type from transport.
3. Port async procs:
   - `openClient`
   - `send`
   - `getWindows/getWorkspaces/getOutputs/getFocusedWindow/getFocusedOutput/getVersion`
   - `doAction`
   - `close`
4. Preserve error model exactly:
   - `connectionClosed("send")`
   - decode/encode/protocol errors unchanged.
5. Verify request/response framing unchanged (`JSON + newline`).

Acceptance:
- `client.nim` compiles with chronos only.
- Unit/integration tests that touch client pass after test port (Phase 5).

---

## Phase 4: Event Stream Layer Port (`stream.nim`)
1. Replace imports with chronos equivalents.
2. Update `NiriEventStream.socket` type to chronos socket type.
3. Port:
   - `openEventStream` handshake (`"EventStream"` request and expected `{"Ok":"Handled"}` response)
   - `next(timeout)`
   - `waitFor(predicate, timeout)`
   - `close`
4. Preserve frame parsing and unknown-event behavior.
5. Preserve timeout semantics:
   - `next` with zero duration = no timeout (current behavior)
   - `waitFor` deadline logic retains remaining-time calculation behavior.

Acceptance:
- Stream API compiles and behavior matches current tests/fixtures.

---

## Phase 5: Test Suite Port to Chronos
1. Update async test imports:
   - Remove `std/asyncdispatch`, `std/asyncnet`.
   - Add chronos test/runtime imports.
2. Replace `waitFor(...)` usage with chronos blocking helper (chronos equivalent).
3. Replace mock server/client socket creation and accept loops to chronos Unix server APIs.
4. Port helper procs signatures from std `Future` to chronos future types.
5. Keep all fixture assertions unchanged.

Files:
- `tests/test_client.nim`
- `tests/test_stream.nim`
- `tests/test_nimri_ipc.nim`

Acceptance:
- `devenv shell -- nimble test` passes with no asyncdispatch dependency.

---

## Phase 6: Remove Legacy Asyncdispatch/Asyncnet Usage Completely
1. Repository-wide search and remove leftovers:
   - `asyncdispatch`
   - `asyncnet`
   - `waitFor` (std version)
2. Ensure public re-export module still exposes required client/stream APIs without leaking removed types.
3. Verify no module imports forbidden runtime accidentally.

Acceptance:
- `rg -n "asyncdispatch|asyncnet" src tests` returns no runtime usage.
- Full suite compiles/tests green.

---

## Phase 7: API Compatibility and Versioning Decision
Chronos migration may alter public type signatures (future/socket concrete types).

1. Evaluate compatibility:
   - If signatures are source-compatible for callers, keep minor bump.
   - If callers must change imports/types, treat as breaking and bump major.
2. Update:
   - `nimri_ipc.nimble` version
   - `README.md` async usage examples
   - migration notes in changelog/release notes.

Acceptance:
- Version strategy documented and implemented.

---

## Phase 8: Validation Matrix
Run all commands inside devenv shell.

1. Compile checks:
   - `devenv shell -- nim c --hints:off src/nimri_ipc/nimri_ipc.nim`
   - `devenv shell -- nim c --warningAsError:on --hints:off src/nimri_ipc/nimri_ipc.nim`
2. Test checks:
   - `devenv shell -- nimble test`
   - Targeted:
     - `devenv shell -- nim c -r tests/test_client.nim`
     - `devenv shell -- nim c -r tests/test_stream.nim`
3. Optional live checks (if `NIRI_SOCKET` set):
   - `devenv shell -- nim c -r tests/test_client.nim`
   - `devenv shell -- nim c -r tests/test_stream.nim`

Acceptance:
- Green compile/test matrix and no regressions in mock/live flows.

---

## Detailed Task Breakdown (Execution Order)
1. Add chronos dependency in nimble file.
2. Introduce chronos imports and type aliases in `internal/transport.nim`.
3. Port `connectSocket`.
4. Port `writeLine`.
5. Port `readLineWithTimeout` with timeout race/cancellation.
6. Compile transport-only dependent files.
7. Port `client.nim` socket field and all async procs.
8. Compile client call chain.
9. Port `stream.nim` and `waitFor` logic.
10. Compile full library.
11. Port async tests + mock servers.
12. Run full tests.
13. Remove all asyncdispatch/asyncnet leftovers.
14. Update docs/examples/versioning.
15. Final verification and release notes.

## Risks and Mitigations
- Risk: Timeout behavior differs subtly under chronos.
  - Mitigation: Add explicit timeout unit tests around boundary values (0ms, 1ms, 2s).
- Risk: Cancellation leaks pending recv futures.
  - Mitigation: Explicit cancellation and cleanup in timeout path; run stress loop tests.
- Risk: Unix socket API differences in chronos complicate mock server setup.
  - Mitigation: Isolate test server helper and migrate once; reuse across client/stream tests.
- Risk: Public API break due to future type changes.
  - Mitigation: Decide and document semver impact before release.

## Additional Test Cases to Add During Migration
1. Transport timeout test asserts exact `Timeout` error kind and operation label.
2. Transport EOF test asserts `ConnectionClosed` mapping after peer close.
3. Stream `waitFor` timeout path with no matching event.
4. Stream unknown event passthrough after chronos port.
5. Client send on closed client returns `ConnectionClosed("send")`.

## Done Criteria
The refactor is complete when all are true:
1. Production async code uses chronos exclusively.
2. Tests use chronos exclusively.
3. No `asyncdispatch`/`asyncnet` imports remain in source/tests.
4. Full devenv compile + test matrix passes.
5. Public docs and package metadata reflect chronos runtime.
6. Version bump aligns with API compatibility impact.

## Suggested Implementation Timeline
- Day 1: Phases 0-2 (prep + transport)
- Day 2: Phases 3-4 (client + stream)
- Day 3: Phases 5-6 (tests + cleanup)
- Day 4: Phases 7-8 (compat docs/version + full validation)

## Notes for Implementers
- Keep all protocol/domain parsing untouched unless required for compilation.
- Preserve `Result[T, NimriIpcError]` channels exactly; avoid throwing exceptions across API boundaries.
- Do not mix runtimes during final state; temporary coexistence is allowed only during active migration.
- Every behavior-affecting change in transport/client/stream should include a focused test update in the same commit.
