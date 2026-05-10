# CONCEPT_ANALYSIS_REVIEW

Analysis and review of `NIMRI_IPC_CONCEPT.md` and `NIMRI_IPC_SPEC.md` against the actual Niri IPC protocol and practical implementation considerations.

---

## 1. Overall Assessment

Both documents are well-structured, clearly scoped, and demonstrate strong architectural discipline. The concept establishes a clean separation between IPC infrastructure and higher-level orchestration, and the spec translates that intent into concrete, testable requirements. The scope boundaries are appropriate and the "forbidden couplings" in the spec are particularly valuable for preventing scope creep.

However, there are several gaps, ambiguities, and protocol-specific concerns that should be addressed before implementation begins.

---

## 2. Protocol Accuracy and Gaps

### 2.1 Framing: Correctly Identified
The spec correctly identifies newline-delimited JSON (Section 7.1). This matches Niri's actual wire format: one JSON object per line, with the stream continuing indefinitely for events.

### 2.2 Missing: Serde Externally-Tagged Enum Encoding
Neither document addresses how Niri serializes its Rust enums. Niri uses serde's **default externally-tagged representation**, which means:

- Unit variants serialize as bare strings: `"FocusedWindow"`
- Struct variants serialize as `{"VariantName": { ...fields... }}`: `{"Action": {"CloseWindow": {"id": null}}}`
- The `Reply` wrapper is `{"Ok": <Response>}` or `{"Err": "message"}`

This has direct implications for the Nim JSON decoder. Nim's `std/json` and common serialization libraries don't natively handle this tagged-union pattern. The spec should explicitly document this encoding and require the decoder to handle it, as it affects every module that touches JSON.

### 2.3 Missing: Reply Wrapper Type
The spec defines `NiriResponse` but doesn't mention the `Reply` wrapper (`Result<Response, String>` in Rust). On the wire, every response is wrapped in `{"Ok": ...}` or `{"Err": "..."}`. This is a protocol-level detail that the decode layer must handle before producing typed responses. The spec's error model should account for this: `{"Err": "..."}` is a *protocol-level error from niri*, distinct from transport or parse errors.

### 2.4 Missing: EventStream Connection Semantics
The spec mentions event stream subscription but omits a critical protocol detail: **once `EventStream` is sent, the connection becomes unidirectional**. Niri stops reading from the socket and only writes events. This means:

- Event streaming requires a **dedicated, separate connection** from command connections.
- The client cannot send further requests on an event stream connection.
- The client should shut down the write end of the socket after sending the request.

This has significant architectural impact on `client.nim` — a single `NiriClient` must either manage two connections internally or the API must make the separation explicit.

### 2.5 Missing: Initial State Delivery on Event Stream
When an event stream is opened, Niri sends the **full current state** as a batch of initial events (`WorkspacesChanged`, `WindowsChanged`, `KeyboardLayoutsChanged`, `CastsChanged`) before incremental updates begin. This is not mentioned in either document but is important for callers that want to build an initial state snapshot from events alone.

### 2.6 Missing: Outputs Response Asymmetry
`Response::Outputs` returns a `HashMap<String, Output>` keyed by output name, while `Response::Workspaces` and `Response::Windows` return `Vec`. The spec's convenience query section (`getOutputs`) should note this and decide whether the Nim API normalizes this or preserves the asymmetry.

### 2.7 Missing: Blocking Requests (PickWindow, PickColor)
Some requests (`PickWindow`, `PickColor`) block until the user completes an interactive picker. The response may take arbitrarily long or return `null` on cancellation. The spec's timeout model (Section 6.3) should address this — a fixed timeout would be inappropriate for these.

---

## 3. Domain Model Review

### 3.1 Required Entity Coverage
The spec requires models for Windows, Workspaces, Outputs, Focus state, and IDs. Based on the actual protocol, additional entities that should be considered:

- **LayerSurface**: Returned by `Request::Layers`. Relevant for some compositor interactions.
- **Cast**: Screencast sessions, returned by `Request::Casts` and delivered via events.
- **KeyboardLayouts**: Returned and evented. Simple but distinct from the core spatial entities.
- **WindowLayout**: A sub-object of Window with tile geometry, column/row positions. Complex enough to warrant its own type.
- **LogicalOutput**: Sub-object of Output with position, scale, transform.
- **Mode**: Output display mode with refresh rate.
- **Timestamp**: `{secs: u64, nanos: u32}` used for focus timestamps.

The spec should clarify whether V1 targets full protocol coverage or a practical subset. If subset, the criteria for inclusion should be stated.

### 3.2 Supporting Types for Actions
The action system uses several parameterized types that need Nim models:

- **SizeChange**: `SetFixed(i32)`, `SetProportion(f64)`, `AdjustFixed(i32)`, `AdjustProportion(f64)`
- **PositionChange**: Similar variants for floating window moves.
- **WorkspaceReferenceArg**: `Id(u64)`, `Index(u8)`, `Name(String)` — for targeting workspaces by different identifiers.
- **LayoutSwitchTarget**: `Next`, `Prev`, `Index(u8)`
- **ColumnDisplay**: `Normal`, `Tabbed`
- **Transform**: Rotation enum with variants like `_90`, `_180` (serialized with leading underscore).

These are tagged unions in Rust. The spec should address how these are represented in Nim (object variants, distinct enums, etc.).

### 3.3 ID Types
Niri uses `u64` for window and workspace IDs and `String` for output names (e.g., `"eDP-1"`). Workspace `idx` is `u8`. The spec mentions "IDs for window/workspace/output" but should specify whether to use distinct types (e.g., `WindowId = distinct uint64`) for type safety or plain primitives.

---

## 4. Event Model Review

### 4.1 Event Coverage
The spec requires a "typed event union/object hierarchy" but doesn't enumerate events. The actual protocol has ~20 event variants across these categories:

- **Workspace events**: `WorkspacesChanged`, `WorkspaceActivated`, `WorkspaceUrgencyChanged`, `WorkspaceActiveWindowChanged`
- **Window events**: `WindowsChanged`, `WindowOpenedOrChanged`, `WindowClosed`, `WindowFocusChanged`, `WindowFocusTimestampChanged`, `WindowUrgencyChanged`, `WindowLayoutsChanged`
- **Keyboard events**: `KeyboardLayoutsChanged`, `KeyboardLayoutSwitched`
- **System events**: `OverviewOpenedOrClosed`, `ConfigLoaded`, `ScreenshotCaptured`
- **Cast events**: `CastsChanged`, `CastStartedOrChanged`, `CastStopped`

The spec should decide whether all events are modeled in V1 or if some are deferred.

### 4.2 Event Metadata
The spec requires "raw metadata needed for debugging (event kind, timestamp if present, source frame reference)." Note that **Niri events do not include timestamps** — only `WindowFocusTimestampChanged` carries a `Timestamp` field, and that is the *focus timestamp*, not an event timestamp. The "source frame reference" idea (preserving the raw JSON) is good for debugging but should be optional to avoid doubling memory per event.

### 4.3 WindowLayoutsChanged: Batch Event
`WindowLayoutsChanged` carries `changes: Vec<(u64, WindowLayout)>` — a batch of layout updates for multiple windows in a single event. This is notably different from other events that carry single-entity updates. The Nim model needs to handle this tuple-in-array structure cleanly.

---

## 5. API Design Review

### 5.1 Client Lifecycle
The proposed `openClient(config)` API is reasonable. Considerations:

- What goes in `config`? At minimum: optional socket path, optional timeout defaults. Should be a simple object, not an opaque builder.
- The spec should clarify whether a `NiriClient` manages one connection or two (command + event). Given the event stream's unidirectional nature, a single-connection client that transparently switches to event mode is error-prone.

**Recommendation**: Either make the event stream a separate type (e.g., `openEventStream(config): Future[Result[NiriEventStream, ...]]` as a standalone function, not a method on `NiriClient`) or clearly document that `subscribeEvents` consumes the client's ability to send commands.

### 5.2 sendTyped Generic
`sendTyped[T](client, request): Future[Result[T, NimriIpcError]]` implies the caller specifies the expected response type. This is clean but raises questions:

- How does the library verify the response variant matches `T`? A `getWindows` request should return `seq[Window]`, not silently decode something else.
- Consider whether request types should carry their response type as a phantom/associated type, enabling the compiler to enforce correct pairing.

### 5.3 Event Stream API
`nextEvent(stream, timeout?)` is a pull-based API. This is simpler than callback-based but consider:

- Should there be a `waitForEvent(stream, predicate, timeout?)` convenience for the common "execute action then wait for confirmation event" pattern? The concept mentions "event-confirmed execution loops" as a core use case.
- How does the caller handle the initial state dump? If the stream emits 4+ full-state events immediately, callers need to know whether to process or skip them.

### 5.4 Missing: Action Inventory
The spec requires "typed constructors for frequently used Niri actions" but doesn't define what "frequently used" means. Niri has ~120 action variants. The spec should either:

- Commit to full coverage (all actions get typed constructors), or
- Define the V1 subset with criteria (e.g., "all focus, move, workspace, and window-state actions; defer debug/screenshot/cast actions").

---

## 6. Error Model Review

### 6.1 Error Variants: Mostly Sound
The proposed error variants cover the important cases. Additions to consider:

- **`NiriError`**: For errors returned by Niri itself (`{"Err": "..."}` responses). These are distinct from parse/transport errors — the protocol succeeded but the compositor rejected the request.
- **`ConnectionClosed`**: For when the socket closes unexpectedly during event streaming. Distinct from `SocketReadFailed` in that it's an expected end-of-stream condition.
- **`ResponseMismatch`**: For when a response variant doesn't match the expected type (if `sendTyped` is implemented).

### 6.2 Error Context
The spec requires "operation context (e.g., `open`, `send:GetWindows`, `nextEvent`)" which is good. Consider also including the raw JSON snippet for decode errors — this is invaluable for diagnosing protocol version mismatches.

---

## 7. Compatibility and Versioning

### 7.1 Critical: niri-ipc Does Not Follow Semver
The spec's compatibility policy (Section 12) should note that the upstream `niri-ipc` crate follows niri's version numbering, not semver. New fields and enum variants are added freely in minor releases. This means:

- The Nim library **will** encounter unknown fields and unknown enum variants in practice.
- The unknown-enum handling decision (Open Decision #3) is not optional — it's a hard requirement for production use.
- The library should be designed to be updated frequently to track niri releases.

### 7.2 Unknown Enum Handling: Strong Recommendation
Of the two options listed (sentinel variant vs. strict error), **sentinel variant (`Unknown`) is strongly recommended**. Strict errors would cause the library to break on every niri update that adds a new event type or action variant, which happens frequently.

### 7.3 Unknown Field Handling
The spec says unknown fields "SHOULD be tolerated." This should be strengthened to MUST. Niri adds fields regularly; strict field checking would be a constant source of breakage.

---

## 8. Architecture and Module Design

### 8.1 Module Split: Sound
The `models / requests / actions / events / client` split is clean and appropriate. The separation of `requests.nim` (protocol-level) from `actions.nim` (ergonomic constructors) is a good design choice that mirrors how `niri-ipc` itself separates `Request` from `Action`.

### 8.2 nimri_ipc.nim: Needs Clarification
"Public exports only; no protocol logic duplication" is correct, but the spec should clarify whether this module also provides any convenience re-exports or type aliases. In Nim, the top-level module is the primary import path — it should export enough that most users only need `import nimri_ipc`.

### 8.3 Missing: Internal JSON Utilities
Neither document mentions where JSON encode/decode utilities live. The tagged-union serialization pattern will require custom decode logic that is reused across `models.nim`, `requests.nim`, `actions.nim`, and `events.nim`. Consider:

- A private `protocol.nim` or `codec.nim` module for shared serialization helpers.
- Or, macros/templates that generate the tagged-union decode pattern per type.

This is a meaningful implementation concern that should be addressed in the spec.

### 8.4 Missing: nimble Package Configuration
Neither document mentions `nimri_ipc.nimble` or dependencies. Key decisions:

- Nim version constraint (>= 2.0?)
- JSON library: `std/json`, `jsony`, `packedjson`, or custom?
- Async framework: `std/asyncdispatch` or `chronos`?
- Result type: `std/options` + exceptions, or `results` package?

These choices significantly affect API design and caller compatibility. The spec's Open Decision #2 (Result type dependency) is important but incomplete — the async framework choice is equally impactful.

---

## 9. Testing Strategy Review

### 9.1 Fixture Strategy: Good
Fixture-based testing is the right approach. Recommendations for fixture collection:

- Capture real Niri output using `niri msg -j <command>` for response fixtures.
- Capture event stream output by running `niri msg event-stream` and piping to a file.
- Include fixtures from multiple niri versions to validate compatibility handling.
- Fixtures should be stored as `.json` files, one per test case, named by command (e.g., `response_windows.json`, `event_window_opened.json`).

### 9.2 Missing: Tagged-Union Decode Tests
Given the non-trivial JSON encoding, the test suite should explicitly test:

- Unit variant decode: `"FocusedWindow"` (bare string)
- Struct variant decode: `{"Action": {"CloseWindow": {"id": null}}}` (nested object)
- Reply wrapper decode: `{"Ok": {"Windows": [...]}}` and `{"Err": "message"}`
- Unknown variant tolerance: an event type added in a future niri version should not crash the parser.

### 9.3 Missing: Concurrency / Async Tests
The spec requires async client operations but the testing section doesn't mention async testing. Consider:

- Mock socket tests using in-memory streams.
- Tests for concurrent command sends (if supported).
- Tests for event stream behavior when the connection drops mid-frame.

---

## 10. Performance Considerations

### 10.1 Event Parse Path
The spec correctly identifies this as performance-sensitive. For a Niri compositor running at 60+ fps with many windows, layout change events can arrive in rapid bursts. Key recommendations:

- Parse JSON lazily if possible — for filtered event streams, skip full decode of irrelevant events.
- Avoid `string` copies for IDs and enum values during hot-path parsing.
- Consider a streaming JSON parser rather than full-document parse for large responses (the `Windows` response can be substantial with many open windows).

### 10.2 Memory Model
The spec doesn't address memory ownership. In Nim, this matters:

- Are domain objects `ref` or value types? Value types are more cache-friendly but expensive to copy in collections.
- Event objects passed to callers: copy or move semantics?
- For the event stream buffer, a ring buffer of raw bytes with zero-copy JSON views would be optimal but complex.

---

## 11. Open Decisions: Priority Assessment

The spec lists 5 open decisions. Prioritized assessment:

| # | Decision | Priority | Recommendation |
|---|---|---|---|
| 1 | Exact proc/type names | Low | Defer to implementation; follow Nim naming conventions (`camelCase` procs, `PascalCase` types) |
| 2 | Result type dependency | **High** | Use `results` package or `std` Result. This affects every public API signature. Decide before implementation. |
| 3 | Unknown enum handling | **High** | Use `Unknown(string)` sentinel. Required for forward compatibility. Non-negotiable for production use. |
| 4 | Default timeout values | Medium | 5s for commands, no timeout for event stream, configurable per-call. |
| 5 | Raw JsonNode escape hatch | Medium | Yes, expose it. Useful for protocol debugging and for accessing fields added in newer niri versions before the library catches up. |

**Additional open decisions that should be added:**

| # | Decision | Priority | Notes |
|---|---|---|---|
| 6 | Async framework (`asyncdispatch` vs `chronos`) | **High** | Determines caller compatibility. `chronos` is more capable but adds a dependency. |
| 7 | JSON library choice | **High** | `std/json` is convenient but slow; `jsony` is fast but has quirks with tagged unions. |
| 8 | Client connection model (single vs dual) | **High** | Must resolve the event stream connection architecture. |
| 9 | V1 action/event coverage scope | Medium | Full or subset? |
| 10 | Nim version floor | Medium | Nim 2.0+ enables important features (ORC, better generics). |

---

## 12. Risks and Concerns

### 12.1 Protocol Tracking Burden
Niri is actively developed and adds IPC capabilities regularly. The library will need ongoing maintenance to stay current. Without a code generation approach (e.g., generating Nim types from the Rust source or a shared schema), this is manual work for every niri release.

**Mitigation**: Consider a script that extracts type definitions from `niri-ipc/src/lib.rs` and generates Nim type stubs, or at minimum a checklist for version bumps.

### 12.2 Tagged-Union Serialization Complexity
Serde's externally-tagged enum encoding is the single biggest implementation challenge. Every domain type, request, response, action, and event uses this pattern. Getting the codec right (and making it maintainable) is critical path work.

**Mitigation**: Invest in a robust macro or template system for tagged-union decode/encode before writing individual type decoders. Test it thoroughly in isolation.

### 12.3 Async Ecosystem Fragmentation in Nim
Nim's async ecosystem is split between `std/asyncdispatch` and `chronos`. Choosing one limits interoperability with callers using the other. Neither is clearly dominant.

**Mitigation**: Consider making the transport layer abstract enough that both backends could be supported, or pick one and document the rationale.

### 12.4 Test Fixture Staleness
JSON fixtures captured from one niri version will not reflect fields added in later versions. Tests that pass against old fixtures may miss decode failures on real niri output.

**Mitigation**: Version-tag fixtures. Periodically re-capture from current niri. Include "extra field" tolerance tests using synthetically augmented fixtures.

---

## 13. Summary of Recommended Changes

### To NIMRI_IPC_CONCEPT.md:
1. Add a section on Niri's tagged-union JSON encoding and its implications.
2. Mention the event stream's unidirectional nature and the need for separate connections.
3. Note that niri-ipc does not follow semver.
4. Expand the domain model list to include `WindowLayout`, `KeyboardLayouts`, `Cast`, and supporting action types.

### To NIMRI_IPC_SPEC.md:
1. **Section 5** (Public API): Address the dual-connection architecture for commands vs. events. Clarify whether `NiriClient` manages this internally or exposes it.
2. **Section 5**: Add `waitForEvent(stream, predicate, timeout?)` to the API surface for event-confirmed execution loops.
3. **Section 6.3**: Add an exception for blocking requests (`PickWindow`, `PickColor`) that may take arbitrarily long.
4. **Section 7**: Add a subsection on serde externally-tagged enum encoding and require the decoder to handle it.
5. **Section 8**: Expand required entity list to include `WindowLayout`, `LogicalOutput`, `Mode`, `Timestamp`, `KeyboardLayouts`, `Cast`, and action parameter types (`SizeChange`, `PositionChange`, `WorkspaceReferenceArg`).
6. **Section 8.2**: Strengthen unknown field tolerance from SHOULD to MUST.
7. **Section 10.1**: Enumerate the event categories or reference the niri-ipc source as authoritative.
8. **Section 10.2**: Note that events do not carry timestamps (except `WindowFocusTimestampChanged`).
9. **Section 11**: Add `NiriError` variant for compositor-returned errors (distinct from transport/parse errors). Add `ConnectionClosed` for event stream termination.
10. **Section 16**: Add test categories for tagged-union decode, Reply wrapper decode, and async/mock-socket tests.
11. **Section 18**: Add open decisions for async framework, JSON library, client connection model, V1 scope, and Nim version floor.
12. Add a new section on internal codec/serialization architecture (where tagged-union helpers live).

---

## 14. Conclusion

The concept and spec provide a strong foundation. The scope is appropriately narrow, the architectural boundaries are well-defined, and the testing strategy is sound. The main gaps are protocol-specific details (tagged-union encoding, event stream connection semantics, Reply wrapper) and implementation-level decisions (async framework, JSON library, connection model) that become critical once coding begins.

The single highest-risk item is the tagged-union JSON codec — it is pervasive, non-trivial, and has no off-the-shelf Nim solution. Addressing this early (potentially with a prototype) would de-risk the entire project.

With the recommended additions, these documents would be implementation-ready.
