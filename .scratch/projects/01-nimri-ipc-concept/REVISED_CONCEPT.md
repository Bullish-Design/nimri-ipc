# NIMRI-IPC: Revised Concept

## 1. What This Is

`nimri-ipc` is a Nim library for typed, async communication with the Niri Wayland compositor over its IPC socket. It provides a complete Nim interface to Niri's command, query, and event-stream protocols.

The library is infrastructure. It owns the socket, the JSON, and the types. It does not own policy, planning, persistence, or UI. Any Nim program that needs to talk to Niri should be able to depend on this package alone.

## 2. Why It Exists

- **One protocol implementation.** Every Nim tool that talks to Niri should share one decode/encode path. Protocol bugs get fixed once.
- **Type safety across the boundary.** Niri's wire format is JSON with Rust serde conventions. Nim callers should never need to touch `JsonNode` for normal operations.
- **Event-driven composability.** Higher-level tools (workspace orchestrators, layout managers, status bars) need typed events with reliable framing. This library provides that substrate.

## 3. Scope

### Owns

- Unix socket connection lifecycle (connect, send, receive, close).
- JSON codec for Niri's serde externally-tagged enum wire format.
- Typed Nim models for all Niri domain objects.
- Typed request construction and response decoding.
- Typed action constructors for all compositor actions.
- Event stream framing, incremental parsing, and typed event emission.
- Structured error model covering transport, protocol, and decode failures.
- Forward-compatibility handling for unknown fields and enum variants.

### Does Not Own

- Configuration file formats or loaders.
- Reconciliation, planning, or state diffing logic.
- Persistent state storage.
- CLI commands, UX policy, or orchestration workflows.
- Application-specific integrations (browser tabs, editor sessions, etc.).

## 4. Niri IPC Protocol Summary

This section documents the actual wire protocol that the library must implement. The authoritative source is the `niri-ipc` Rust crate (`niri-ipc/src/lib.rs` in the niri repository).

### 4.1 Transport

Niri exposes a Unix domain socket (stream). The path is provided via the `NIRI_SOCKET` environment variable. There is no default/fallback path.

### 4.2 Wire Format

Newline-delimited JSON. Each message is a single JSON value followed by `\n`. The protocol carries three message types:

- **Request** (client -> niri): A JSON-encoded `Request` enum value.
- **Reply** (niri -> client): A JSON-encoded `Result<Response, String>`, i.e. `{"Ok": <Response>}` or `{"Err": "message"}`.
- **Event** (niri -> client, event stream only): A JSON-encoded `Event` enum value.

### 4.3 Serde Externally-Tagged Enum Encoding

All Niri enum types use Rust serde's default externally-tagged representation:

- **Unit variants** serialize as bare JSON strings: `"FocusedWindow"`, `"Quit"`, `"Version"`
- **Newtype/struct variants** serialize as single-key objects: `{"Action": {"CloseWindow": {"id": null}}}`, `{"Ok": {"Windows": [...]}}`
- **Tuple variants** serialize as single-key objects with array values.

This encoding is pervasive — it applies to `Request`, `Response`, `Reply`, `Event`, `Action`, and all supporting parameter types (`SizeChange`, `WorkspaceReferenceArg`, etc.). The Nim codec must handle this pattern generically.

### 4.4 Connection Modes

A single socket connection operates in one of two modes:

**Command mode** (default): The client sends one `Request`, reads one `Reply`, and may then send another request or close. Standard request-response.

**Event stream mode**: The client sends `"EventStream"` as its request. Niri responds with `{"Ok": "Handled"}`, then stops reading from the connection and begins writing `Event` values continuously, one per line, until the connection closes.

These modes are mutually exclusive on a single connection. A client that needs both commands and events must open separate connections.

### 4.5 Event Stream Initial State

When an event stream opens, Niri sends the full current state as an initial batch before incremental updates:
- `WorkspacesChanged` (all workspaces)
- `WindowsChanged` (all windows)
- `KeyboardLayoutsChanged` (current layouts)
- `CastsChanged` (active screencasts)

Callers can use this to build a complete state snapshot without a separate query.

### 4.6 Blocking Requests

`PickWindow` and `PickColor` enter an interactive compositor mode and block until the user completes or cancels the operation. The response may take arbitrarily long and returns `null` on cancellation. These requests are incompatible with fixed timeouts.

### 4.7 Response Asymmetries

- `Outputs` returns a map keyed by output name (`Table[string, Output]`).
- `Windows` and `Workspaces` return sequences (`seq[Window]`, `seq[Workspace]`).

### 4.8 Upstream Versioning

The `niri-ipc` crate does not follow semver. It tracks niri's version number. New fields and enum variants are added in minor releases without notice. The Nim library must tolerate unknown fields and unknown enum variants to avoid breaking on every niri update.

## 5. Architecture

### 5.1 Module Structure

```text
nimri_ipc/
├── nimri_ipc.nimble          # package manifest
├── src/
│   └── nimri_ipc/
│       ├── nimri_ipc.nim     # public re-exports
│       ├── codec.nim         # tagged-union JSON encode/decode engine
│       ├── models.nim        # all Niri domain types
│       ├── requests.nim      # Request enum, query constructors
│       ├── actions.nim       # Action enum, action constructors
│       ├── events.nim        # Event enum, event types
│       ├── errors.nim        # NimriIpcError type family
│       ├── client.nim        # command connection (send request, get response)
│       └── stream.nim        # event stream connection (subscribe, iterate)
└── tests/
    ├── fixtures/             # captured Niri JSON payloads
    │   ├── responses/
    │   └── events/
    ├── test_codec.nim
    ├── test_models.nim
    ├── test_requests.nim
    ├── test_actions.nim
    ├── test_events.nim
    ├── test_client.nim
    └── test_stream.nim
```

### 5.2 Module Responsibilities

**`codec.nim`** — Internal. The tagged-union JSON engine. Provides macros/templates for encoding Nim object variants to serde externally-tagged JSON and decoding back. Handles the `Reply` wrapper (`Ok`/`Err`). Handles unknown variant tolerance. Every other module that touches JSON depends on this. This is the critical-path module — if this is wrong, everything is wrong.

**`models.nim`** — Public. Canonical Nim types for all Niri domain objects. Pure data definitions, no I/O, no JSON imports in the public interface. Includes codec hooks (e.g., `toJson`/`fromJson` procs or pragma annotations) that wire into `codec.nim`.

**`requests.nim`** — Public. The `NiriRequest` enum and constructor procs for query commands (`requestWindows()`, `requestWorkspaces()`, `requestOutputs()`, etc.). Serialization to JSON via `codec.nim`. Pure, no I/O.

**`actions.nim`** — Public. The `NiriAction` enum and constructor procs for compositor actions (`focusWindowDown()`, `moveColumnRight()`, `closeWindow(id)`, etc.). Returns `NiriRequest` values wrapping the action. Pure, no I/O.

**`events.nim`** — Public. The `NiriEvent` enum and all event payload types. Deserialization from JSON via `codec.nim`. Includes event kind classification for filtering/matching. Pure, no I/O.

**`errors.nim`** — Public. The `NimriIpcError` type hierarchy. Shared across `client.nim` and `stream.nim`.

**`client.nim`** — Public. The command connection. Opens a socket, sends a request, reads a reply, returns a typed result. One connection handles one request-response exchange (or can be reused for sequential commands). Does not handle event streams.

**`stream.nim`** — Public. The event stream connection. Opens a dedicated socket, sends the `EventStream` request, shuts down the write end, and provides an async iterator/pull interface for typed events. Handles incremental frame parsing across chunked reads.

**`nimri_ipc.nim`** — Public. Top-level re-export module. Imports and re-exports everything a typical caller needs so that `import nimri_ipc` is sufficient for most use cases.

### 5.3 Separation of Command and Event Connections

The original concept placed both command sending and event streaming on a single `NiriClient` type. This is architecturally unsound given the protocol's connection semantics.

The revised design uses two distinct types:

- **`NiriClient`** (from `client.nim`): For sending commands and receiving responses. Can be opened, used for one or more sequential request-response exchanges, and closed.
- **`NiriEventStream`** (from `stream.nim`): For receiving events. Opened with a dedicated connection that immediately enters event stream mode. Provides a pull-based event iteration API.

Both types accept the same connection configuration (socket path, timeouts). Both can be created independently. There is no shared mutable state between them.

This separation eliminates an entire class of bugs (sending a command on an event connection, losing events while waiting for a command response, etc.) and makes the API self-documenting.

### 5.4 Dependency Rules

```text
nimri_ipc.nim  →  re-exports all public modules
client.nim     →  codec, models, requests, actions, errors
stream.nim     →  codec, models, events, errors
requests.nim   →  codec, models, actions
actions.nim    →  codec, models
events.nim     →  codec, models
models.nim     →  codec (for serialization hooks)
errors.nim     →  (no internal deps)
codec.nim      →  (no internal deps, only std/json or chosen JSON lib)
```

### 5.5 Forbidden Couplings

- `client.nim` and `stream.nim` MUST NOT depend on each other.
- `actions.nim` MUST NOT perform I/O or import transport modules.
- `events.nim` MUST NOT depend on request/action modules.
- `models.nim` MUST NOT import client, stream, or error modules.
- No module MUST depend on orchestrator, planner, or policy types.

## 6. Domain Model

### 6.1 Core Entities

| Type | Key Fields | Notes |
|---|---|---|
| `Window` | `id: uint64`, `title: Option[string]`, `appId: Option[string]`, `pid: Option[int32]`, `workspaceId: Option[uint64]`, `isFocused: bool`, `isFloating: bool`, `isUrgent: bool`, `layout: WindowLayout` | Primary entity. |
| `WindowLayout` | `tileSize: (float64, float64)`, `windowSize: (int32, int32)`, `posInScrollingLayout: Option[(int, int)]`, `tilePosInWorkspaceView: Option[(float64, float64)]`, `windowOffsetInTile: (float64, float64)` | Sub-object of Window. Tile geometry. |
| `Workspace` | `id: uint64`, `idx: uint8`, `name: Option[string]`, `output: Option[string]`, `isActive: bool`, `isFocused: bool`, `isUrgent: bool`, `activeWindowId: Option[uint64]` | `idx` is per-output, 0-255. |
| `Output` | `name: string`, `make: string`, `model: string`, `serial: Option[string]`, `physicalSize: Option[(uint32, uint32)]`, `modes: seq[Mode]`, `currentMode: Option[int]`, `vrrSupported: bool`, `vrrEnabled: bool`, `logical: Option[LogicalOutput]` | Keyed by name in responses. |
| `LogicalOutput` | `x, y: int32`, `width, height: uint32`, `scale: float64`, `transform: Transform` | Sub-object of Output. |
| `Mode` | `width, height: uint16`, `refreshRate: uint32`, `isPreferred: bool` | `refreshRate` is in millihertz. |
| `Timestamp` | `secs: uint64`, `nanos: uint32` | Used for focus timestamps. |
| `KeyboardLayouts` | `names: seq[string]`, `currentIdx: uint8` | |
| `LayerSurface` | `namespace: string`, `output: string`, `layer: Layer`, `keyboardInteractivity: LayerSurfaceKeyboardInteractivity` | |
| `Cast` | `streamId: uint64`, `sessionId: uint64`, `kind: CastKind`, `target: CastTarget`, `isActive: bool`, `pid: Option[int32]` | Screencast session. |

### 6.2 ID Types

Use distinct types for compile-time safety:

```nim
type
  WindowId* = distinct uint64
  WorkspaceId* = distinct uint64
  OutputName* = distinct string    # e.g., "eDP-1"
  WorkspaceIdx* = distinct uint8   # per-output index, 0-255
```

This prevents mixing window IDs with workspace IDs at the call site. Conversion procs (`uint64(id)`, `$name`) provide escape hatches.

### 6.3 Action Parameter Types

These are tagged unions in the Niri protocol and must be modeled as Nim object variants:

| Type | Variants | Used By |
|---|---|---|
| `SizeChange` | `SetFixed(int32)`, `SetProportion(float64)`, `AdjustFixed(int32)`, `AdjustProportion(float64)` | Window/column resize actions |
| `PositionChange` | `SetFixed(float64)`, `SetProportion(float64)`, `AdjustFixed(float64)`, `AdjustProportion(float64)` | Floating window move |
| `WorkspaceRef` | `ById(WorkspaceId)`, `ByIndex(WorkspaceIdx)`, `ByName(string)` | Workspace targeting |
| `LayoutSwitchTarget` | `Next`, `Prev`, `ByIndex(uint8)` | Layout switching |
| `ColumnDisplay` | `Normal`, `Tabbed` | Column display mode |
| `Transform` | `Normal`, `Rot90`, `Rot180`, `Rot270`, `Flipped`, `FlippedRot90`, `FlippedRot180`, `FlippedRot270` | Output transform. Wire format uses `"_90"`, `"_180"`, etc. |

### 6.4 Model Design Rules

- All public models are value types (not `ref`). Callers copy what they need.
- `Option[T]` for nullable protocol fields. No sentinel values.
- Unknown enum variants decode to an `Unknown` sentinel carrying the raw string, never raising.
- Unknown JSON fields are silently ignored during decode.
- One canonical definition per type in `models.nim`. No parallel definitions elsewhere.

## 7. Request and Action Design

### 7.1 Request Enum

All Niri requests map to a single `NiriRequest` variant type:

```
Query requests:    Version, Outputs, Workspaces, Windows, Layers,
                   KeyboardLayouts, FocusedOutput, FocusedWindow,
                   OverviewState, Casts
Interactive:       PickWindow, PickColor
Action wrapper:    Action(NiriAction)
Control:           EventStream, ReturnError
Config:            LoadConfigFile(path: Option[string])
Output config:     OutputConfig(output: string, action: OutputAction)
```

Constructor procs provide ergonomic creation: `requestWindows()`, `requestAction(focusWindowDown())`, etc.

### 7.2 Action Coverage

V1 targets full coverage of all Niri action variants. The action enum has ~120 variants across these categories:

- **Window focus**: `FocusWindowDown`, `FocusWindowUp`, `FocusColumnLeft`, `FocusColumnRight`, `FocusWindow(id)`, `FocusWindowPrevious`, etc.
- **Window move**: `MoveWindowDown`, `MoveWindowUp`, `MoveColumnLeft`, `MoveColumnRight`, `ConsumeOrExpelWindowLeft`, `SwapWindowLeft`, etc.
- **Window sizing**: `SetWindowWidth(id, SizeChange)`, `SetWindowHeight(id, SizeChange)`, `ResetWindowHeight`, `SwitchPresetColumnWidth`, `MaximizeColumn`, etc.
- **Window state**: `CloseWindow(id)`, `FullscreenWindow(id)`, `ToggleWindowFloating(id)`, `CenterWindow(id)`, etc.
- **Workspace**: `FocusWorkspace(WorkspaceRef)`, `FocusWorkspaceDown`, `MoveWindowToWorkspace(WorkspaceRef)`, `SetWorkspaceName`, etc.
- **Monitor**: `FocusMonitorLeft`, `FocusMonitorRight`, `MoveWindowToMonitor`, `MoveColumnToMonitor`, etc.
- **Layout**: `SwitchLayout(LayoutSwitchTarget)`, `SetColumnDisplay(ColumnDisplay)`, etc.
- **Floating**: `MoveFloatingWindow(id, PositionChange, PositionChange)`, `FocusFloating`, `FocusTiling`, etc.
- **Process**: `Quit`, `Spawn(seq[string])`, `SpawnSh(string)`
- **System**: `ToggleOverview`, `Screenshot`, `PowerOffMonitors`, `PowerOnMonitors`, etc.
- **Debug**: `ToggleDebugTint`, `DebugToggleOpaqueRegions`, `DebugToggleDamage`

Full coverage avoids the ambiguity of "frequently used" and ensures callers never need to fall back to raw JSON for standard operations.

### 7.3 Request-Response Type Pairing

Each query request has a known response type. The API should enforce this at the type level where practical:

```nim
# Typed send that decodes the response to the expected type
let windows = await client.getWindows()    # Result[seq[Window], NimriIpcError]
let outputs = await client.getOutputs()    # Result[Table[string, Output], NimriIpcError]

# Or generic send for actions
let result = await client.send(requestAction(focusWindowDown()))  # Result[void, NimriIpcError]
```

Convenience procs (`getWindows`, `getWorkspaces`, `getOutputs`, `getFocusedWindow`, `getFocusedOutput`) handle the common query-and-decode pattern internally.

## 8. Event Design

### 8.1 Event Enum

All Niri events map to a `NiriEvent` variant type covering ~20 variants:

**Workspace events:**
- `WorkspacesChanged(workspaces: seq[Workspace])` — full state replacement
- `WorkspaceActivated(id: WorkspaceId, focused: bool)`
- `WorkspaceUrgencyChanged(id: WorkspaceId, urgent: bool)`
- `WorkspaceActiveWindowChanged(workspaceId: WorkspaceId, activeWindowId: Option[WindowId])`

**Window events:**
- `WindowsChanged(windows: seq[Window])` — full state replacement
- `WindowOpenedOrChanged(window: Window)`
- `WindowClosed(id: WindowId)`
- `WindowFocusChanged(id: Option[WindowId])`
- `WindowFocusTimestampChanged(id: WindowId, focusTimestamp: Timestamp)`
- `WindowUrgencyChanged(id: WindowId, urgent: bool)`
- `WindowLayoutsChanged(changes: seq[(WindowId, WindowLayout)])` — batch update

**Keyboard events:**
- `KeyboardLayoutsChanged(keyboardLayouts: KeyboardLayouts)`
- `KeyboardLayoutSwitched(idx: uint8)`

**System events:**
- `OverviewOpenedOrClosed(isOpen: bool)`
- `ConfigLoaded(failed: bool)`
- `ScreenshotCaptured(path: Option[string])`

**Cast events:**
- `CastsChanged(casts: seq[Cast])`
- `CastStartedOrChanged(cast: Cast)`
- `CastStopped(streamId: uint64)`

**Forward-compatibility:**
- `UnknownEvent(kind: string, raw: string)` — any event variant not recognized by the current library version.

### 8.2 Event Stream API

Pull-based iteration on a dedicated connection:

```nim
let stream = await openEventStream()

# Simple iteration
while true:
  let event = await stream.next()       # Result[NiriEvent, NimriIpcError]
  case event.get.kind
  of WindowFocusChanged: ...
  of WorkspaceActivated: ...

# Predicate wait for event-confirmed execution
let confirmation = await stream.waitFor(
  proc(e: NiriEvent): bool = e.kind == WindowFocusChanged,
  timeout = 2000.milliseconds
)
```

`waitFor` consumes and discards non-matching events. This supports the action-then-confirm pattern that higher-level tools need.

### 8.3 Initial State Handling

The event stream always delivers full state before incremental updates. The library does not hide or special-case this — callers receive these as normal events and can use them to build initial state. The documentation should clearly describe this behavior so callers know to expect it.

### 8.4 Event Metadata

Niri events do not carry timestamps (the `Timestamp` in `WindowFocusTimestampChanged` is a focus timestamp, not an event timestamp). The library does not fabricate event metadata that doesn't exist in the protocol.

Optional debug mode: when enabled, each decoded event retains a reference to its raw JSON frame for diagnostic purposes. Disabled by default to avoid memory overhead.

## 9. Error Model

### 9.1 Error Type

A single `NimriIpcError` object variant type with a `kind` discriminator:

| Kind | Meaning | Context |
|---|---|---|
| `SocketPathMissing` | No socket path provided and `NIRI_SOCKET` not set. | — |
| `SocketConnectFailed` | Could not connect to the socket. | Socket path, OS error. |
| `SocketReadFailed` | Read from socket failed. | Operation, OS error. |
| `SocketWriteFailed` | Write to socket failed. | Operation, OS error. |
| `ConnectionClosed` | Socket closed unexpectedly (event stream ended, niri exited). | Operation. |
| `Timeout` | Operation exceeded configured timeout. | Operation, duration. |
| `JsonEncodeError` | Failed to serialize a request to JSON. | Request description. |
| `JsonDecodeError` | Failed to parse JSON from a response or event frame. | Raw payload snippet, parse error detail. |
| `ProtocolViolation` | Well-formed JSON but unexpected structure (wrong variant, missing required field). | Expected vs. actual, raw snippet. |
| `NiriError` | Niri returned `{"Err": "..."}`. The protocol succeeded but the compositor rejected the request. | Niri's error message string. |
| `ResponseMismatch` | Response variant does not match the expected type for the request sent. | Expected type, actual variant. |
| `UnsupportedValue` | A known field contains a value outside the expected range/set. | Field, value. |

### 9.2 Error Design Rules

- Every error carries a human-readable `message` and a machine-usable `kind`.
- Errors from niri itself (`NiriError`) are distinct from library errors. Callers can match on kind to differentiate "niri said no" from "the socket broke."
- Raw payload snippets in decode errors are truncated to a safe length to avoid logging massive JSON blobs.
- Environment variable values are not included in error messages by default (security). Debug mode may expose them.

## 10. The Codec Problem

### 10.1 Why This Matters

Serde's externally-tagged enum encoding is the single most important implementation challenge. It affects every type that crosses the JSON boundary:

- `Request` (encode)
- `Reply` / `Response` (decode)
- `Event` (decode)
- `Action` and all parameter types (encode)
- Domain model sub-types like `SizeChange`, `WorkspaceRef`, `Transform` (encode and decode)

Nim has no built-in support for this encoding pattern. `std/json` can parse the JSON, but mapping `{"VariantName": {...}}` to Nim object variants requires custom logic.

### 10.2 Codec Design Direction

`codec.nim` should provide a macro or template system that generates encode/decode procs from annotated Nim object variant types. The goal is to write type definitions once and get correct serde-compatible JSON handling automatically.

Conceptual approach:

```nim
# In models.nim — define the type
type
  SizeChange* {.serdeTagged.} = object
    case kind*: SizeChangeKind
    of SetFixed: fixedVal*: int32
    of SetProportion: propVal*: float64
    of AdjustFixed: adjFixedVal*: int32
    of AdjustProportion: adjPropVal*: float64

# codec.nim generates:
# - toJson(SizeChange) -> {"SetFixed": 42} or {"SetProportion": 0.5}
# - fromJson(JsonNode, SizeChange) -> decoded variant
```

The exact macro API is an implementation detail, but the architectural requirement is clear: tagged-union codec logic lives in one place and is reused everywhere. No hand-written encode/decode per type.

### 10.3 Codec Requirements

- Encode unit variants as bare strings.
- Encode struct/newtype variants as `{"VariantName": <payload>}`.
- Decode both forms.
- Handle the `Reply` wrapper (`{"Ok": ...}` / `{"Err": ...}`) as a special case or as a standard tagged union.
- Tolerate unknown variants by decoding to a sentinel value (not raising).
- Tolerate unknown fields by ignoring them (not raising).
- Provide clear error messages on decode failure: which field, what was expected, what was found.
- Be testable in isolation with unit tests before any domain types are implemented.

## 11. Client API

### 11.1 Connection Configuration

```nim
type
  NiriConnectConfig* = object
    socketPath*: Option[string]     # explicit path, or fall back to NIRI_SOCKET
    commandTimeout*: Duration       # default timeout for command responses
```

Socket path resolution: explicit path > `NIRI_SOCKET` env var > error.

### 11.2 Command Client

```nim
# Open a command connection
proc openClient*(config = NiriConnectConfig()): Future[Result[NiriClient, NimriIpcError]]

# Send a raw request, get the decoded response variant
proc send*(client: NiriClient, request: NiriRequest): Future[Result[NiriResponse, NimriIpcError]]

# Convenience queries
proc getWindows*(client: NiriClient): Future[Result[seq[Window], NimriIpcError]]
proc getWorkspaces*(client: NiriClient): Future[Result[seq[Workspace], NimriIpcError]]
proc getOutputs*(client: NiriClient): Future[Result[Table[string, Output], NimriIpcError]]
proc getFocusedWindow*(client: NiriClient): Future[Result[Option[Window], NimriIpcError]]
proc getFocusedOutput*(client: NiriClient): Future[Result[Option[Output], NimriIpcError]]
proc getVersion*(client: NiriClient): Future[Result[string, NimriIpcError]]

# Execute an action
proc doAction*(client: NiriClient, action: NiriAction): Future[Result[void, NimriIpcError]]

# Close (idempotent)
proc close*(client: NiriClient): Future[void]
```

### 11.3 Event Stream

```nim
# Open a dedicated event stream connection
proc openEventStream*(config = NiriConnectConfig()): Future[Result[NiriEventStream, NimriIpcError]]

# Pull next event
proc next*(stream: NiriEventStream, timeout: Duration = Duration.default): Future[Result[NiriEvent, NimriIpcError]]

# Wait for a specific event matching a predicate
proc waitFor*(stream: NiriEventStream, predicate: proc(e: NiriEvent): bool,
              timeout: Duration): Future[Result[NiriEvent, NimriIpcError]]

# Close
proc close*(stream: NiriEventStream): Future[void]
```

### 11.4 Timeout Behavior

- Command timeout: configurable, default 5 seconds. Applies to all command responses except blocking requests.
- Blocking requests (`PickWindow`, `PickColor`): no timeout by default. Caller can pass an explicit timeout.
- Event stream `next()`: configurable per call. Default: no timeout (wait indefinitely).
- Event stream `waitFor()`: timeout is required (no default) to prevent indefinite hangs.

### 11.5 Reconnect Policy

No implicit reconnect. If the connection drops, the client/stream returns an error. Callers manage reconnection logic. An optional reconnect wrapper may be added later but is not V1 scope.

## 12. Forward Compatibility

### 12.1 Principles

Niri adds fields and enum variants in minor releases. The library must not break when this happens. Rules:

1. Unknown JSON fields in responses and events: **silently ignored** during decode.
2. Unknown enum variants in responses and events: **decoded to `Unknown(rawValue)` sentinel**, never raising.
3. Unknown event types: decoded to `UnknownEvent(kind, raw)`, never dropped.
4. The library tracks a "last verified niri version" in its documentation. Users running newer niri versions should expect unknown variants but not decode failures.

### 12.2 Protocol Tracking

Niri releases add IPC surface regularly. To keep the library current:

- Pin each release to a verified niri version.
- Maintain a `PROTOCOL_VERSION.md` noting which niri version the types were last synced against.
- Test fixtures should be version-tagged and include synthetic "extra field" payloads to validate tolerance.
- Consider a semi-automated script that diffs `niri-ipc/src/lib.rs` between niri releases and flags new types/fields/variants for manual Nim translation.

## 13. Testing Strategy

### 13.1 Test Categories

1. **Codec tests** (`test_codec.nim`): Tagged-union encode/decode in isolation. Unit variant, struct variant, nested variant, unknown variant, unknown field tolerance. This is the foundation — test first, test thoroughly.

2. **Model decode tests** (`test_models.nim`): Decode each domain type from fixture JSON. Cover all fields including optionals.

3. **Request encode tests** (`test_requests.nim`): Verify each request constructor produces correct JSON matching what niri expects.

4. **Action encode tests** (`test_actions.nim`): Verify action constructors produce correct JSON, including parameterized types (`SizeChange`, `WorkspaceRef`, etc.).

5. **Event decode tests** (`test_events.nim`): Decode each event type from fixture JSON. Include `WindowLayoutsChanged` batch format. Include unknown event tolerance.

6. **Frame parser tests** (`test_stream.nim`): Partial frame across multiple reads. Multiple frames in one read. Malformed frame between valid frames. Empty lines. Invalid UTF-8.

7. **Client tests** (`test_client.nim`): Mock socket for request-response round-trips. Timeout behavior. Connection failure paths. Reply wrapper decode (`Ok` and `Err`).

8. **Reply wrapper tests**: `{"Ok": {"Windows": [...]}}` -> decoded response. `{"Err": "message"}` -> `NimriIpcError(kind: NiriError)`.

### 13.2 Fixtures

- Stored in `tests/fixtures/responses/` and `tests/fixtures/events/`.
- Captured from real niri output using `niri msg -j <command>` and `niri msg event-stream`.
- Named by API case: `get_windows.json`, `event_window_opened.json`, etc.
- Include both nominal and malformed samples.
- Include "augmented" fixtures with extra unknown fields to test forward compatibility.
- Tag with the niri version they were captured from.

### 13.3 Integration Tests

- Live-socket tests run when `NIRI_SOCKET` is available.
- Skipped automatically in CI environments without Niri.
- Test real round-trips: query windows, subscribe to events, execute an action.

## 14. Implementation Priorities

The dependency graph dictates build order:

1. **`errors.nim`** — No dependencies. Define the error types first.
2. **`codec.nim`** — No internal dependencies. Build and thoroughly test the tagged-union JSON engine before anything else. This is the highest-risk module.
3. **`models.nim`** — Depends on `codec.nim`. Define all domain types with codec annotations. Test with fixtures.
4. **`requests.nim`** + **`actions.nim`** — Depend on `codec.nim` and `models.nim`. Define request/action enums and constructors. Test encode output.
5. **`events.nim`** — Depends on `codec.nim` and `models.nim`. Define event enum. Test decode from fixtures.
6. **`client.nim`** — Depends on everything above. Implement socket transport, request-response cycle, convenience queries.
7. **`stream.nim`** — Depends on `codec.nim`, `models.nim`, `events.nim`, `errors.nim`. Implement event stream connection and frame parser.
8. **`nimri_ipc.nim`** — Re-export. Wire everything together.

The codec is the critical path. If it works, the rest is mostly mechanical type definitions and straightforward socket I/O.

## 15. Technology Decisions

These must be resolved before implementation begins.

### 15.1 Nim Version

Minimum Nim 2.0. Required for ORC memory management, improved generics, and better object variant support. Nim 1.x is not a target.

### 15.2 Async Framework

**Decision required.** Two options:

- **`std/asyncdispatch`**: Standard library, no extra dependency, widest caller compatibility. Adequate for socket I/O. Simpler.
- **`chronos`**: More capable (cancellation, structured concurrency), better for complex async patterns. Adds a dependency. Used by Status/Nimbus ecosystem.

Recommendation: `std/asyncdispatch` for V1. The library's async needs are straightforward (socket read/write, timeouts). Switching to `chronos` later is possible without API changes if the public interface uses `Future[Result[T, E]]`.

### 15.3 JSON Library

**Decision required.** Options:

- **`std/json`**: Standard library, no dependency. Tree-based (parse to `JsonNode`, then extract). Adequate for correctness. Not the fastest.
- **`jsony`**: Fast, streaming-friendly. But its hook system has quirks with tagged unions that may require workarounds.
- **Custom minimal parser**: Maximum control and performance. Higher implementation cost.

Recommendation: `std/json` for V1. Correctness first, optimize later. The tagged-union codec macros abstract over the JSON library anyway — swapping the backend later is feasible without changing public types.

### 15.4 Result Type

Use Nim's `std/options` for nullable values. For fallible operations, use a `Result[T, NimriIpcError]` type. Options:

- **`results` package** (nim-results): Well-tested, widely used in the Nim ecosystem.
- **Simple custom Result**: Two-field object variant. No dependency.

Recommendation: `results` package. It's small, stable, and idiomatic.

## 16. Non-Goals (V1)

- Dynamic plugin or extension runtime.
- Persistent state or database layer.
- CLI commands, orchestration, or UX policy.
- Application-specific capture/restore logic.
- Implicit reconnection or connection pooling.
- Callback-based or push-based event API (pull-based only in V1).
- Async framework abstraction layer (pick one, commit).

## 17. Acceptance Criteria

The library is complete when:

1. `codec.nim` correctly handles serde externally-tagged encoding for all Niri type patterns (unit, struct, newtype, nested, unknown).
2. All Niri domain types are modeled in `models.nim` with fixture-validated decode.
3. All Niri request types have typed constructors in `requests.nim`.
4. All Niri action types have typed constructors in `actions.nim`.
5. All Niri event types are modeled in `events.nim` with fixture-validated decode.
6. `client.nim` can connect, send requests, and return typed responses.
7. `stream.nim` can connect, receive events, handle partial frames, and provide typed event iteration.
8. Unknown fields and unknown enum variants are tolerated without errors.
9. Error model is structured, contextual, and distinguishes transport/decode/protocol/niri errors.
10. Test suite covers all categories defined in Section 13.
11. No orchestration, planning, or policy logic exists in any module.
12. `import nimri_ipc` provides a complete, usable public API.
