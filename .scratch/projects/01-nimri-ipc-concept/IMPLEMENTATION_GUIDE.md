# NIMRI-IPC: Implementation Guide

Step-by-step implementation plan for `nimri-ipc`, ordered by the dependency graph defined in the revised concept. Each step includes the work to be done, the types and procs to implement, and the full testing requirements that must pass before proceeding to the next step.

---

## Prerequisites

Before starting implementation:

1. **Nim >= 2.0** installed and on PATH. Verify with `devenv shell -- nim --version`.
2. **Nimble** package manager available. Verify with `devenv shell -- nimble --version`.
3. **Niri** compositor running (for fixture capture and integration tests). Verify with `devenv shell -- printenv NIRI_SOCKET`.
4. **`results`** package available: `devenv shell -- nimble install results`.

---

## Step 0: Project Scaffold

### 0.1 Work

Create the project directory structure, nimble package file, and empty module stubs.

#### 0.1.1 Create directory tree

```text
nimri_ipc/
├── nimri_ipc.nimble
├── src/
│   └── nimri_ipc/
│       ├── nimri_ipc.nim
│       ├── codec.nim
│       ├── models.nim
│       ├── requests.nim
│       ├── actions.nim
│       ├── events.nim
│       ├── errors.nim
│       ├── client.nim
│       └── stream.nim
└── tests/
    ├── fixtures/
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

#### 0.1.2 Create `nimri_ipc.nimble`

```nim
# Package
version       = "0.1.0"
author        = "<author>"
description   = "Typed async Nim client for Niri compositor IPC"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"
requires "results >= 0.4.0"
```

#### 0.1.3 Create empty module stubs

Each `.nim` file under `src/nimri_ipc/` should contain a module docstring comment and nothing else. For example:

```nim
## nimri_ipc/errors - Error type definitions for nimri-ipc
```

Each `test_*.nim` file should contain:

```nim
import unittest
suite "<module> tests":
  discard
```

#### 0.1.4 Capture test fixtures

This is a critical prerequisite that feeds into multiple later steps. Run these commands on a machine with Niri running and at least one window open:

```bash
# Response fixtures
devenv shell -- zsh -lc 'niri msg -j version > tests/fixtures/responses/version.json'
devenv shell -- zsh -lc 'niri msg -j outputs > tests/fixtures/responses/outputs.json'
devenv shell -- zsh -lc 'niri msg -j workspaces > tests/fixtures/responses/workspaces.json'
devenv shell -- zsh -lc 'niri msg -j windows > tests/fixtures/responses/windows.json'
devenv shell -- zsh -lc 'niri msg -j focused-window > tests/fixtures/responses/focused_window.json'
devenv shell -- zsh -lc 'niri msg -j focused-output > tests/fixtures/responses/focused_output.json'
devenv shell -- zsh -lc 'niri msg -j layers > tests/fixtures/responses/layers.json'
devenv shell -- zsh -lc 'niri msg -j keyboard-layouts > tests/fixtures/responses/keyboard_layouts.json'

# Event fixtures - run briefly, switch windows/workspaces to generate events, then Ctrl-C
devenv shell -- zsh -lc 'timeout 10 niri msg event-stream > tests/fixtures/events/raw_stream.txt'

# Record the niri version
devenv shell -- zsh -lc 'niri msg version > tests/fixtures/NIRI_VERSION.txt'
```

After capturing, split `raw_stream.txt` into individual event fixture files, one JSON object per file, named by event type (e.g., `window_opened_or_changed.json`, `window_focus_changed.json`, `workspaces_changed.json`, etc.).

Also create synthetic fixtures:

- `tests/fixtures/responses/windows_extra_fields.json` — copy of `windows.json` with extra unknown fields added to a window object (e.g., `"futureField": 42`).
- `tests/fixtures/events/unknown_event.json` — a fabricated event with an unknown variant name: `{"FutureEventType": {"data": 123}}`.

### 0.2 Verification

Run from the project root:

```bash
devenv shell -- nimble check                    # validates nimble file
devenv shell -- nim c --hints:off src/nimri_ipc/nimri_ipc.nim  # compiles empty module
devenv shell -- nimble test                     # runs empty test suites (all should pass)
```

**Pass criteria:**
- `devenv shell -- nimble check` exits 0.
- All stub modules compile without errors.
- All test suites run and report 0 failures.
- Fixture files exist and contain valid JSON (verify with `devenv shell -- jq . tests/fixtures/responses/windows.json`).

---

## Step 1: Error Types (`errors.nim`)

### 1.1 Work

Define the `NimriIpcError` object variant type and supporting types. This module has no internal dependencies.

#### 1.1.1 Define error kind enum

```nim
type
  NimriIpcErrorKind* = enum
    SocketPathMissing
    SocketConnectFailed
    SocketReadFailed
    SocketWriteFailed
    ConnectionClosed
    Timeout
    JsonEncodeError
    JsonDecodeError
    ProtocolViolation
    NiriError
    ResponseMismatch
    UnsupportedValue
```

#### 1.1.2 Define error object

```nim
type
  NimriIpcError* = object
    kind*: NimriIpcErrorKind
    message*: string            ## human-readable description
    operation*: string          ## what was being done (e.g., "send:GetWindows", "nextEvent")
    detail*: string             ## additional context (raw JSON snippet, OS error, etc.)
```

#### 1.1.3 Define constructor procs

Provide convenience constructors for each error kind to ensure consistent message formatting:

```nim
proc socketPathMissing*(): NimriIpcError
proc socketConnectFailed*(path, osError: string): NimriIpcError
proc socketReadFailed*(operation, osError: string): NimriIpcError
proc socketWriteFailed*(operation, osError: string): NimriIpcError
proc connectionClosed*(operation: string): NimriIpcError
proc timeout*(operation: string, durationMs: int): NimriIpcError
proc jsonEncodeError*(operation, detail: string): NimriIpcError
proc jsonDecodeError*(operation, detail, snippet: string): NimriIpcError
proc protocolViolation*(operation, expected, actual, snippet: string): NimriIpcError
proc niriError*(niriMessage: string): NimriIpcError
proc responseMismatch*(expected, actual: string): NimriIpcError
proc unsupportedValue*(field, value: string): NimriIpcError
```

#### 1.1.4 Define `$` for string conversion

Implement `proc $(e: NimriIpcError): string` that produces a readable single-line error message including kind, operation, and message.

#### 1.1.5 Snippet truncation utility

Implement a private `proc truncateSnippet(s: string, maxLen = 200): string` used by constructors to cap raw JSON in `detail` fields.

### 1.2 Testing (`test_errors.nim`)

```
Suite: error construction and formatting

Test 1: "each error kind has a working constructor"
  - Call each constructor proc with representative arguments.
  - Assert the returned error has the correct `kind`.
  - Assert `message` is non-empty.
  - Assert `operation` is set where applicable.

Test 2: "$ produces readable output"
  - Construct several error variants.
  - Call `$` on each.
  - Assert the string contains the kind name and the message.
  - Assert no string is empty.

Test 3: "snippet truncation"
  - Call `jsonDecodeError` with a `snippet` string longer than 200 characters.
  - Assert `detail` field length is <= 200 + length of any ellipsis suffix.
  - Call with a short snippet and assert it is preserved verbatim.

Test 4: "kind enum is exhaustive"
  - Iterate over all values of `NimriIpcErrorKind`.
  - Assert each has at least one constructor or can be constructed manually.
```

**Pass criteria:** All 4 tests pass. `errors.nim` compiles independently with no imports from other nimri_ipc modules.

---

## Step 2: Tagged-Union Codec (`codec.nim`)

This is the critical-path module. It must be thoroughly tested before any domain types are built on top of it.

### 2.1 Work

Build a JSON encode/decode engine for Rust serde externally-tagged enums. The codec operates on `std/json` `JsonNode` values.

#### 2.1.1 Core decode logic

Implement procs that classify and destructure a `JsonNode` according to the serde externally-tagged pattern:

```nim
type
  TaggedVariant* = object
    tag*: string              ## variant name
    payload*: JsonNode        ## inner value (JNull for unit variants)
    isUnit*: bool             ## true if the source was a bare string

proc parseTaggedVariant*(node: JsonNode): Result[TaggedVariant, string]
```

Behavior:
- If `node` is a `JString`, return `TaggedVariant(tag: node.str, payload: newJNull(), isUnit: true)`.
- If `node` is a `JObject` with exactly one key, return `TaggedVariant(tag: key, payload: value, isUnit: false)`.
- Otherwise, return an error describing what was found.

#### 2.1.2 Core encode logic

```nim
proc encodeUnitVariant*(tag: string): JsonNode
  ## Returns a JString with the tag name.

proc encodeStructVariant*(tag: string, payload: JsonNode): JsonNode
  ## Returns {"tag": payload}.
```

#### 2.1.3 Reply wrapper decode

The `Reply` type is `{"Ok": <Response>}` or `{"Err": "message"}`. Implement:

```nim
proc parseReply*(node: JsonNode): Result[JsonNode, string]
  ## Returns the inner Response JsonNode on Ok,
  ## or an error string (niri's message) on Err.
```

This uses `parseTaggedVariant` internally. An `"Ok"` tag returns the payload. An `"Err"` tag returns the payload string as an error.

#### 2.1.4 Field extraction helpers

Provide typed extraction procs that pull fields from a `JObject` with clear error messages on missing/wrong-type fields:

```nim
proc getField*(node: JsonNode, field: string): Result[JsonNode, string]
proc getStr*(node: JsonNode, field: string): Result[string, string]
proc getInt*(node: JsonNode, field: string): Result[int, string]
proc getUint64*(node: JsonNode, field: string): Result[uint64, string]
proc getFloat*(node: JsonNode, field: string): Result[float64, string]
proc getBool*(node: JsonNode, field: string): Result[bool, string]
proc getOptionalField*(node: JsonNode, field: string): Option[JsonNode]
proc getOptionalStr*(node: JsonNode, field: string): Option[string]
proc getOptionalInt*(node: JsonNode, field: string): Option[int]
proc getOptionalUint64*(node: JsonNode, field: string): Option[uint64]
```

These helpers silently ignore unknown fields (they only extract what's asked for). Missing required fields produce a `Result` error with the field name and parent context.

#### 2.1.5 Enum decode with unknown tolerance

```nim
proc decodeEnum*[T: enum](node: JsonNode, fallback: T): Result[T, string]
  ## Decodes a JString to an enum value.
  ## If the string doesn't match any known variant, returns `fallback`
  ## (the Unknown sentinel) instead of failing.
```

#### 2.1.6 JSON line framing utility

For the event stream parser (used later in `stream.nim`):

```nim
type
  FrameBuffer* = object
    buf: string
    pos: int

proc initFrameBuffer*(): FrameBuffer
proc feed*(fb: var FrameBuffer, data: string)
proc nextFrame*(fb: var FrameBuffer): Option[string]
  ## Extracts the next complete newline-delimited frame.
  ## Returns none if no complete frame is available yet.
```

This handles:
- Partial frames accumulated across multiple `feed` calls.
- Multiple frames delivered in a single `feed` call (returns them one at a time via successive `nextFrame` calls).
- Empty lines (skipped).

### 2.2 Testing (`test_codec.nim`)

This is the most important test suite in the project. Every pattern that will appear in real protocol data must be covered here.

```
Suite: tagged variant parsing

Test 1: "decode unit variant from bare string"
  - Input: parseJson("\"FocusedWindow\"")
  - Assert tag == "FocusedWindow", isUnit == true, payload is JNull.

Test 2: "decode struct variant from single-key object"
  - Input: parseJson("""{"Windows": []}""")
  - Assert tag == "Windows", isUnit == false, payload is JArray.

Test 3: "decode nested struct variant"
  - Input: parseJson("""{"Action": {"CloseWindow": {"id": null}}}""")
  - Assert tag == "Action", payload is JObject with key "CloseWindow".

Test 4: "decode newtype variant (single value payload)"
  - Input: parseJson("""{"SetFixed": 42}""")
  - Assert tag == "SetFixed", payload is JInt with value 42.

Test 5: "error on empty object"
  - Input: parseJson("{}")
  - Assert parseTaggedVariant returns error.

Test 6: "error on multi-key object"
  - Input: parseJson("""{"A": 1, "B": 2}""")
  - Assert parseTaggedVariant returns error.

Test 7: "error on non-string, non-object input"
  - Input: parseJson("42"), parseJson("[1,2]"), parseJson("null")
  - Assert each returns error.

Suite: tagged variant encoding

Test 8: "encode unit variant"
  - Assert encodeUnitVariant("Quit") == parseJson("\"Quit\"").

Test 9: "encode struct variant"
  - Assert encodeStructVariant("Windows", parseJson("[]")) == parseJson("""{"Windows": []}""").

Test 10: "encode then decode round-trip - unit"
  - Encode "Version" as unit, decode, assert tag == "Version" and isUnit.

Test 11: "encode then decode round-trip - struct"
  - Encode "Action" with payload, decode, assert tag and payload match.

Suite: Reply wrapper

Test 12: "decode Ok reply with response payload"
  - Input: parseJson("""{"Ok": {"Windows": []}}""")
  - Assert parseReply returns Ok, inner node has key "Windows".

Test 13: "decode Ok reply with Handled (unit response)"
  - Input: parseJson("""{"Ok": "Handled"}""")
  - Assert parseReply returns Ok, inner node is JString "Handled".

Test 14: "decode Err reply"
  - Input: parseJson("""{"Err": "Unknown request"}""")
  - Assert parseReply returns error with message "Unknown request".

Test 15: "decode malformed reply (not Ok or Err)"
  - Input: parseJson("""{"Something": 1}""")
  - Assert parseReply returns error (neither Ok nor Err tag).

Suite: field extraction

Test 16: "getStr on present field"
  - Input: parseJson("""{"name": "eDP-1"}""")
  - Assert getStr(node, "name") == ok("eDP-1").

Test 17: "getStr on missing field"
  - Assert getStr(node, "missing") returns error.

Test 18: "getStr on wrong type field"
  - Input: parseJson("""{"name": 42}""")
  - Assert getStr(node, "name") returns error.

Test 19: "getOptionalStr on present field"
  - Assert getOptionalStr returns some("eDP-1").

Test 20: "getOptionalStr on missing field"
  - Assert getOptionalStr returns none.

Test 21: "getOptionalStr on null field"
  - Input: parseJson("""{"name": null}""")
  - Assert getOptionalStr returns none.

Test 22: "getUint64 on large value"
  - Input with value near uint64 max.
  - Assert correct decode.

Test 23: "getBool on true/false"
  - Assert correct decode for both values.

Test 24: "unknown fields do not cause errors"
  - Input: parseJson("""{"name": "x", "futureField": 99, "another": []}""")
  - Assert getStr(node, "name") succeeds.
  - No proc call fails due to the extra fields.

Suite: enum decode with unknown tolerance

Test 25: "decode known enum value"
  - Define a test enum: type TestEnum = enum teA, teB, teUnknown
  - Input: parseJson("\"teA\"")
  - Assert decodeEnum[TestEnum](node, teUnknown) == ok(teA).

Test 26: "decode unknown enum value returns fallback"
  - Input: parseJson("\"teNeverHeardOfThis\"")
  - Assert decodeEnum[TestEnum](node, teUnknown) == ok(teUnknown).

Test 27: "decode enum from non-string returns error"
  - Input: parseJson("42")
  - Assert error.

Suite: frame buffer

Test 28: "single complete frame"
  - Feed: """{"event": 1}\n"""
  - Assert nextFrame returns some("""{"event": 1}""").
  - Assert subsequent nextFrame returns none.

Test 29: "partial frame accumulated"
  - Feed: """{"event": """
  - Assert nextFrame returns none.
  - Feed: """1}\n"""
  - Assert nextFrame returns some("""{"event": 1}""").

Test 30: "multiple frames in one feed"
  - Feed: """{"a": 1}\n{"b": 2}\n{"c": 3}\n"""
  - Assert nextFrame returns "a", then "b", then "c", then none.

Test 31: "mixed partial and complete"
  - Feed: """{"a": 1}\n{"b":"""
  - Assert nextFrame returns "a", then none.
  - Feed: """ 2}\n"""
  - Assert nextFrame returns "b", then none.

Test 32: "empty lines are skipped"
  - Feed: """\n\n{"a": 1}\n\n"""
  - Assert nextFrame returns "a", then none.

Test 33: "frame with embedded newline in string value"
  - Note: Niri does not embed literal newlines in JSON strings (they'd be escaped as \n).
  - Feed: """{"title": "hello\\nworld"}\n"""
  - Assert nextFrame returns the full frame with the escaped newline intact.
```

**Pass criteria:** All 33 tests pass. `codec.nim` compiles with only `std/json`, `std/options`, and `results` as dependencies. No imports from other nimri_ipc modules.

---

## Step 3: Domain Models (`models.nim`)

### 3.1 Work

Define all Niri domain types. This module depends on `codec.nim` for JSON decode/encode procs but must not import transport or error modules.

#### 3.1.1 ID types

```nim
type
  WindowId* = distinct uint64
  WorkspaceId* = distinct uint64
  OutputName* = distinct string
  WorkspaceIdx* = distinct uint8
```

Implement `==`, `$`, `hash` for each distinct type. Implement `toJson`/`fromJson` for each (WindowId encodes as a JSON number, OutputName as a JSON string).

#### 3.1.2 Simple enums

Define enums for:

- `Transform` — `Normal`, `Rot90`, `Rot180`, `Rot270`, `Flipped`, `FlippedRot90`, `FlippedRot180`, `FlippedRot270`, `Unknown`
- `Layer` — `Background`, `Bottom`, `Top`, `Overlay`, `Unknown`
- `LayerSurfaceKeyboardInteractivity` — `None`, `Exclusive`, `OnDemand`, `Unknown`
- `CastKind` — `Monitor`, `Window`, `Unknown`
- `ColumnDisplay` — `Normal`, `Tabbed`
- `LayoutSwitchTarget` — as object variant: `Next`, `Prev`, `ByIndex(uint8)`

Each enum must include an `Unknown` variant as the last member (except `ColumnDisplay` and `LayoutSwitchTarget` which are encode-only types used in actions).

Implement wire-format name mapping for `Transform` (the Rust side uses `"_90"`, `"_180"`, `"_270"`, `"Flipped90"`, etc.). This requires custom decode/encode procs rather than relying on Nim enum name stringification.

#### 3.1.3 Action parameter types

Define as object variants:

```nim
type
  SizeChangeKind* = enum
    sckSetFixed, sckSetProportion, sckAdjustFixed, sckAdjustProportion

  SizeChange* = object
    case kind*: SizeChangeKind
    of sckSetFixed: fixedVal*: int32
    of sckSetProportion: propVal*: float64
    of sckAdjustFixed: adjFixedVal*: int32
    of sckAdjustProportion: adjPropVal*: float64

  PositionChangeKind* = enum
    pckSetFixed, pckSetProportion, pckAdjustFixed, pckAdjustProportion

  PositionChange* = object
    case kind*: PositionChangeKind
    of pckSetFixed: fixedVal*: float64
    of pckSetProportion: propVal*: float64
    of pckAdjustFixed: adjFixedVal*: float64
    of pckAdjustProportion: adjPropVal*: float64

  WorkspaceRefKind* = enum
    wrkById, wrkByIndex, wrkByName

  WorkspaceRef* = object
    case kind*: WorkspaceRefKind
    of wrkById: id*: WorkspaceId
    of wrkByIndex: idx*: WorkspaceIdx
    of wrkByName: name*: string
```

Implement `toJson` for each (these are encode-only — used when constructing action requests). The wire format follows serde externally-tagged: `{"SetFixed": 42}`, `{"Id": 5}`, etc.

Also implement `fromJson` for `SizeChange` and `PositionChange` (needed if these appear in responses/events, and for round-trip testing).

#### 3.1.4 Core entity types

Define as plain objects (not variants):

```nim
type
  Timestamp* = object
    secs*: uint64
    nanos*: uint32

  Mode* = object
    width*: uint16
    height*: uint16
    refreshRate*: uint32        ## millihertz
    isPreferred*: bool

  LogicalOutput* = object
    x*: int32
    y*: int32
    width*: uint32
    height*: uint32
    scale*: float64
    transform*: Transform

  Output* = object
    name*: string
    make*: string
    model*: string
    serial*: Option[string]
    physicalSize*: Option[tuple[w: uint32, h: uint32]]
    modes*: seq[Mode]
    currentMode*: Option[int]
    vrrSupported*: bool
    vrrEnabled*: bool
    logical*: Option[LogicalOutput]

  WindowLayout* = object
    tileSize*: tuple[w: float64, h: float64]
    windowSize*: tuple[w: int32, h: int32]
    posInScrollingLayout*: Option[tuple[col: int, win: int]]
    tilePosInWorkspaceView*: Option[tuple[x: float64, y: float64]]
    windowOffsetInTile*: tuple[x: float64, y: float64]

  Window* = object
    id*: WindowId
    title*: Option[string]
    appId*: Option[string]
    pid*: Option[int32]
    workspaceId*: Option[WorkspaceId]
    isFocused*: bool
    isFloating*: bool
    isUrgent*: bool
    layout*: WindowLayout
    focusTimestamp*: Option[Timestamp]

  Workspace* = object
    id*: WorkspaceId
    idx*: WorkspaceIdx
    name*: Option[string]
    output*: Option[string]
    isActive*: bool
    isFocused*: bool
    isUrgent*: bool
    activeWindowId*: Option[WindowId]

  KeyboardLayouts* = object
    names*: seq[string]
    currentIdx*: uint8

  LayerSurface* = object
    namespace*: string
    output*: string
    layer*: Layer
    keyboardInteractivity*: LayerSurfaceKeyboardInteractivity

  CastTarget* = object
    # Structure depends on niri version; may need tagged variant handling

  Cast* = object
    streamId*: uint64
    sessionId*: uint64
    kind*: CastKind
    target*: CastTarget
    isActive*: bool
    pid*: Option[int32]
```

#### 3.1.5 Implement `fromJson` for each entity

Each entity needs a `proc fromJson*(node: JsonNode, T: typedesc[EntityType]): Result[EntityType, string]` that:
- Extracts known fields using `codec.getStr`, `codec.getUint64`, etc.
- Ignores unknown fields.
- Handles optional fields via `codec.getOptionalStr`, etc.
- Decodes nested objects recursively.
- Handles JSON field name mapping (Niri uses `snake_case`; Nim types use `camelCase`). The `fromJson` procs must map `"app_id"` -> `appId`, `"is_focused"` -> `isFocused`, etc.

#### 3.1.6 Implement `toJson` for each entity

Needed for entities that appear in requests (primarily action parameters). For response-only entities like `Window`, `toJson` is optional but useful for testing round-trips.

The `toJson` procs must produce `snake_case` field names to match the protocol.

### 3.2 Testing (`test_models.nim`)

```
Suite: ID types

Test 1: "WindowId and WorkspaceId are distinct"
  - Assert that WindowId(5) does not compile when assigned to a WorkspaceId variable.
  - (Or: test that they are separate types via typeof checks.)

Test 2: "ID round-trip through JSON"
  - Encode WindowId(12345) to JSON, decode back, assert equal.
  - Encode WorkspaceId(67890) to JSON, decode back, assert equal.
  - Encode OutputName("eDP-1") to JSON, decode back, assert equal.

Suite: enum types

Test 3: "Transform decode from wire names"
  - Assert decode of "_90" -> Rot90, "_180" -> Rot180, "_270" -> Rot270.
  - Assert decode of "Normal" -> Normal, "Flipped" -> Flipped.
  - Assert decode of "Flipped90" -> FlippedRot90, etc.

Test 4: "Transform unknown variant"
  - Assert decode of "FutureTransform" -> Unknown.

Test 5: "Layer decode"
  - Assert decode of "Background", "Bottom", "Top", "Overlay" to correct variants.
  - Assert unknown string -> Unknown.

Suite: action parameter types

Test 6: "SizeChange encode"
  - Assert SizeChange(kind: sckSetFixed, fixedVal: 100).toJson == parseJson("""{"SetFixed": 100}""").
  - Assert SizeChange(kind: sckSetProportion, propVal: 0.5).toJson == parseJson("""{"SetProportion": 0.5}""").
  - Assert SizeChange(kind: sckAdjustFixed, adjFixedVal: -50).toJson == parseJson("""{"AdjustFixed": -50}""").

Test 7: "SizeChange round-trip"
  - Encode each variant, decode back, assert equal.

Test 8: "WorkspaceRef encode"
  - Assert ById(WorkspaceId(5)).toJson == parseJson("""{"Id": 5}""").
  - Assert ByIndex(WorkspaceIdx(2)).toJson == parseJson("""{"Index": 2}""").
  - Assert ByName("main").toJson == parseJson("""{"Name": "main"}""").

Test 9: "LayoutSwitchTarget encode"
  - Assert Next, Prev, ByIndex encode to "Next", "Prev", {"Index": N}.

Suite: entity decode from fixtures

Test 10: "Window decode from fixture"
  - Load tests/fixtures/responses/windows.json.
  - Parse the Reply wrapper, extract the Windows array.
  - Decode the first window.
  - Assert id, title, appId, isFocused, isFloating, layout fields are populated.
  - Assert all decoded fields match the raw JSON values.

Test 11: "Window decode with extra unknown fields"
  - Load tests/fixtures/responses/windows_extra_fields.json.
  - Assert decode succeeds (no error from unknown fields).
  - Assert known fields still decode correctly.

Test 12: "Workspace decode from fixture"
  - Load tests/fixtures/responses/workspaces.json.
  - Parse Reply wrapper, extract Workspaces array.
  - Decode all workspaces.
  - Assert id, idx, name, output, isActive, isFocused fields.

Test 13: "Output decode from fixture"
  - Load tests/fixtures/responses/outputs.json.
  - Parse Reply wrapper. Note: this is a map, not an array.
  - Decode each output.
  - Assert name, modes, logical output fields.

Test 14: "Output with LogicalOutput and Mode sub-objects"
  - Assert LogicalOutput fields (x, y, width, height, scale, transform) decode.
  - Assert Mode fields (width, height, refreshRate, isPreferred) decode.

Test 15: "WindowLayout decode"
  - Extract layout from a decoded Window.
  - Assert tileSize, windowSize fields.
  - Check posInScrollingLayout optional field handling.

Test 16: "KeyboardLayouts decode from fixture"
  - Load fixture, decode, assert names and currentIdx.

Test 17: "Optional fields decode as none when absent"
  - Construct a minimal JSON window object with optional fields missing.
  - Assert title == none, appId == none, pid == none, etc.

Test 18: "Optional fields decode as none when null"
  - Construct a JSON window object with optional fields set to null.
  - Assert they decode as none.

Suite: field name mapping

Test 19: "snake_case JSON fields map to camelCase Nim fields"
  - Decode a Window from JSON with "app_id", "is_focused", "workspace_id", etc.
  - Assert corresponding Nim fields are populated.

Test 20: "toJson produces snake_case field names"
  - Encode a Window to JSON.
  - Assert the output contains "app_id", not "appId".
```

**Pass criteria:** All 20 tests pass. `models.nim` compiles with only `codec.nim`, `std/json`, `std/options`, and `results` as dependencies. No imports from errors, client, stream, or transport modules.

---

## Step 4: Requests (`requests.nim`)

### 4.1 Work

Define the `NiriRequest` type and constructor procs. Depends on `codec.nim`, `models.nim`, and `actions.nim` (for the `NiriAction` type — but since actions and requests are co-dependent, implement them in tandem; see Step 4+5 note below).

**Note on co-dependency:** `requests.nim` needs `NiriAction` to wrap actions into `Request::Action`. `actions.nim` needs to return `NiriRequest` values. To break the cycle, either:
- Define `NiriAction` in `actions.nim` and import it from `requests.nim`. `actions.nim` provides action constructors that return `NiriAction` values. `requests.nim` provides `requestAction(action: NiriAction): NiriRequest`.
- Or define `NiriAction` in `models.nim` if preferred.

The cleaner approach: `actions.nim` defines `NiriAction` and its constructors. `requests.nim` imports `actions.nim` and wraps actions. This keeps the dependency one-way: `requests -> actions`.

#### 4.1.1 Define NiriRequest

```nim
type
  NiriRequestKind* = enum
    nrVersion, nrOutputs, nrWorkspaces, nrWindows, nrLayers,
    nrKeyboardLayouts, nrFocusedOutput, nrFocusedWindow,
    nrOverviewState, nrCasts,
    nrPickWindow, nrPickColor,
    nrAction,
    nrEventStream, nrReturnError,
    nrLoadConfigFile, nrOutputConfig

  NiriRequest* = object
    case kind*: NiriRequestKind
    of nrAction: action*: NiriAction
    of nrLoadConfigFile: configPath*: Option[string]
    of nrOutputConfig:
      outputName*: string
      outputAction*: OutputAction
    else: discard
```

#### 4.1.2 Constructor procs

```nim
proc requestVersion*(): NiriRequest
proc requestOutputs*(): NiriRequest
proc requestWorkspaces*(): NiriRequest
proc requestWindows*(): NiriRequest
proc requestLayers*(): NiriRequest
proc requestKeyboardLayouts*(): NiriRequest
proc requestFocusedOutput*(): NiriRequest
proc requestFocusedWindow*(): NiriRequest
proc requestOverviewState*(): NiriRequest
proc requestCasts*(): NiriRequest
proc requestPickWindow*(): NiriRequest
proc requestPickColor*(): NiriRequest
proc requestAction*(action: NiriAction): NiriRequest
proc requestEventStream*(): NiriRequest
proc requestLoadConfig*(path = none(string)): NiriRequest
```

#### 4.1.3 Implement `toJson` for NiriRequest

Serialization follows the serde externally-tagged pattern:

- `requestVersion()` -> `"Version"`
- `requestWindows()` -> `"Windows"`
- `requestAction(someAction)` -> `{"Action": <action json>}`
- `requestLoadConfig(some("/path"))` -> `{"LoadConfigFile": {"path": "/path"}}`
- `requestLoadConfig(none)` -> `{"LoadConfigFile": {"path": null}}`

### 4.2 Testing (`test_requests.nim`)

```
Suite: query request encoding

Test 1: "unit query requests encode as bare strings"
  - Assert requestVersion().toJson == parseJson("\"Version\"")
  - Assert requestWindows().toJson == parseJson("\"Windows\"")
  - Assert requestWorkspaces().toJson == parseJson("\"Workspaces\"")
  - Assert requestOutputs().toJson == parseJson("\"Outputs\"")
  - Assert requestFocusedWindow().toJson == parseJson("\"FocusedWindow\"")
  - Assert requestFocusedOutput().toJson == parseJson("\"FocusedOutput\"")
  - Assert requestLayers().toJson == parseJson("\"Layers\"")
  - Assert requestKeyboardLayouts().toJson == parseJson("\"KeyboardLayouts\"")
  - Assert requestOverviewState().toJson == parseJson("\"OverviewState\"")
  - Assert requestCasts().toJson == parseJson("\"Casts\"")
  - Assert requestPickWindow().toJson == parseJson("\"PickWindow\"")
  - Assert requestPickColor().toJson == parseJson("\"PickColor\"")

Test 2: "EventStream request encodes as bare string"
  - Assert requestEventStream().toJson == parseJson("\"EventStream\"")

Test 3: "action request wraps action in tagged object"
  - Let action = some NiriAction (e.g., quit action).
  - Assert requestAction(action).toJson == parseJson("""{"Action": "Quit"}""")

Test 4: "LoadConfigFile with path"
  - Assert requestLoadConfig(some("/etc/niri/config.kdl")).toJson produces
    {"LoadConfigFile": {"path": "/etc/niri/config.kdl"}}

Test 5: "LoadConfigFile without path"
  - Assert requestLoadConfig().toJson produces
    {"LoadConfigFile": {"path": null}}

Suite: request JSON matches niri expectations

Test 6: "each request produces valid JSON that parses"
  - For every constructor, call toJson, call $, parse back with parseJson.
  - Assert no parse error.

Test 7: "request JSON has correct top-level structure"
  - Unit requests: top-level is JString.
  - Struct requests: top-level is JObject with exactly 1 key.
```

**Pass criteria:** All 7 tests pass. `requests.nim` compiles with only `codec.nim`, `models.nim`, `actions.nim`, `std/json`, and `std/options` as dependencies.

---

## Step 5: Actions (`actions.nim`)

### 5.1 Work

Define the `NiriAction` type and constructor procs for all ~120 Niri action variants. This is the largest module by variant count but is mechanically straightforward.

#### 5.1.1 Define NiriAction

Due to Nim's object variant limitations with very large case statements, consider organizing as a flat enum + object variant, or as a smaller set of category sub-types. The key requirement is that `toJson` produces the correct serde externally-tagged output.

Design approach:

```nim
type
  NiriActionKind* = enum
    # Window focus
    naFocusWindowDown, naFocusWindowUp,
    naFocusColumnLeft, naFocusColumnRight,
    naFocusColumnFirst, naFocusColumnLast,
    naFocusWindowOrMonitorLeft, naFocusWindowOrMonitorRight,
    naFocusWindow, naFocusWindowPrevious,
    # Window move
    naMoveWindowDown, naMoveWindowUp,
    naMoveColumnLeft, naMoveColumnRight,
    # ... (all variants)
    # Process
    naQuit, naSpawn, naSpawnSh,
    # etc.

  NiriAction* = object
    case kind*: NiriActionKind
    of naFocusWindow, naCloseWindow, naFullscreenWindow,
       naToggleWindowFloating, naCenterWindow:
      windowId*: Option[WindowId]
    of naSetWindowWidth, naSetWindowHeight:
      sizeWindowId*: Option[WindowId]
      sizeChange*: SizeChange
    of naSpawn:
      args*: seq[string]
    of naSpawnSh:
      command*: string
    of naFocusWorkspace, naMoveWindowToWorkspace, naMoveColumnToWorkspace:
      workspaceRef*: WorkspaceRef
    of naMoveFloatingWindow:
      floatWindowId*: Option[WindowId]
      xChange*: PositionChange
      yChange*: PositionChange
    of naSwitchLayout:
      layoutTarget*: LayoutSwitchTarget
    of naSetColumnDisplay:
      columnDisplay*: ColumnDisplay
    of naSetWorkspaceName:
      wsNameId*: WorkspaceId
      wsName*: string
    # ... unit variants share a common branch:
    else: discard
```

The exact variant grouping depends on which actions carry parameters. Most actions (~80%) are unit variants with no parameters.

#### 5.1.2 Constructor procs

Provide an ergonomic constructor for each action:

```nim
# Unit actions
proc focusWindowDown*(): NiriAction
proc focusWindowUp*(): NiriAction
proc focusColumnLeft*(): NiriAction
proc focusColumnRight*(): NiriAction
proc moveWindowDown*(): NiriAction
proc moveWindowUp*(): NiriAction
proc moveColumnLeft*(): NiriAction
proc moveColumnRight*(): NiriAction
proc quit*(): NiriAction
proc toggleOverview*(): NiriAction
proc screenshot*(): NiriAction
proc powerOffMonitors*(): NiriAction
# ... etc. for all unit actions

# Parameterized actions
proc focusWindow*(id: WindowId): NiriAction
proc closeWindow*(id: Option[WindowId] = none(WindowId)): NiriAction
proc fullscreenWindow*(id: Option[WindowId] = none(WindowId)): NiriAction
proc setWindowWidth*(change: SizeChange, id: Option[WindowId] = none(WindowId)): NiriAction
proc setWindowHeight*(change: SizeChange, id: Option[WindowId] = none(WindowId)): NiriAction
proc spawn*(args: seq[string]): NiriAction
proc spawnSh*(command: string): NiriAction
proc focusWorkspace*(ref: WorkspaceRef): NiriAction
proc moveWindowToWorkspace*(ref: WorkspaceRef): NiriAction
proc switchLayout*(target: LayoutSwitchTarget): NiriAction
proc setColumnDisplay*(display: ColumnDisplay): NiriAction
proc moveFloatingWindow*(x, y: PositionChange, id: Option[WindowId] = none(WindowId)): NiriAction
# ... etc.
```

#### 5.1.3 Implement `toJson` for NiriAction

Maps each action to its serde externally-tagged JSON:

- Unit actions: `"FocusWindowDown"`, `"Quit"`, etc.
- Parameterized actions: `{"CloseWindow": {"id": null}}`, `{"Spawn": ["cmd", "arg"]}`, `{"SetWindowWidth": {"id": null, "change": {"SetFixed": 100}}}`, etc.

The wire name must match the Rust variant name exactly (PascalCase).

#### 5.1.4 Wire name mapping table

Maintain a compile-time or const mapping from `NiriActionKind` to the protocol string. Example:

```nim
const ActionWireNames: array[NiriActionKind, string] = [
  naFocusWindowDown: "FocusWindowDown",
  naFocusWindowUp: "FocusWindowUp",
  naQuit: "Quit",
  naSpawn: "Spawn",
  # ...
]
```

### 5.2 Testing (`test_actions.nim`)

```
Suite: unit action encoding

Test 1: "unit actions encode as bare string in Action wrapper"
  - Assert focusWindowDown().toJson == parseJson("\"FocusWindowDown\"")
  - Assert quit().toJson == parseJson("\"Quit\"")
  - Assert toggleOverview().toJson == parseJson("\"ToggleOverview\"")
  - Test at least 10 representative unit actions across different categories.

Test 2: "all unit actions produce valid JSON"
  - Iterate over all unit action constructors.
  - Assert each produces a JString with a non-empty value.

Suite: parameterized action encoding

Test 3: "CloseWindow with no ID"
  - Assert closeWindow().toJson == parseJson("""{"CloseWindow": {"id": null}}""")

Test 4: "CloseWindow with specific ID"
  - Assert closeWindow(some(WindowId(42))).toJson == parseJson("""{"CloseWindow": {"id": 42}}""")

Test 5: "Spawn with args"
  - Assert spawn(@["alacritty", "--title", "test"]).toJson ==
    parseJson("""{"Spawn": ["alacritty", "--title", "test"]}""")

Test 6: "SpawnSh with command"
  - Assert spawnSh("echo hello").toJson == parseJson("""{"SpawnSh": "echo hello"}""")

Test 7: "SetWindowWidth with SizeChange"
  - Assert setWindowWidth(SizeChange(kind: sckSetFixed, fixedVal: 800)).toJson ==
    parseJson("""{"SetWindowWidth": {"id": null, "change": {"SetFixed": 800}}}""")

Test 8: "FocusWorkspace by name"
  - Assert focusWorkspace(WorkspaceRef(kind: wrkByName, name: "main")).toJson ==
    parseJson("""{"FocusWorkspace": {"reference": {"Name": "main"}}}""")

Test 9: "FocusWorkspace by index"
  - Assert focusWorkspace(WorkspaceRef(kind: wrkByIndex, idx: WorkspaceIdx(2))).toJson ==
    parseJson("""{"FocusWorkspace": {"reference": {"Index": 2}}}""")

Test 10: "SwitchLayout"
  - Assert switchLayout(LayoutSwitchTarget next).toJson == parseJson("""{"SwitchLayout": "Next"}""") (or appropriate tagged format)

Test 11: "MoveFloatingWindow with position changes"
  - Assert correct nested tagged-union encoding for x and y PositionChange values.

Suite: action-to-request integration

Test 12: "action wrapped in request produces correct nesting"
  - Let req = requestAction(closeWindow(some(WindowId(7))))
  - Assert req.toJson == parseJson("""{"Action": {"CloseWindow": {"id": 7}}}""")

Test 13: "unit action wrapped in request"
  - Let req = requestAction(quit())
  - Assert req.toJson == parseJson("""{"Action": "Quit"}""")
```

**Pass criteria:** All 13 tests pass. `actions.nim` compiles with only `codec.nim`, `models.nim`, `std/json`, and `std/options` as dependencies. No I/O imports.

---

## Step 6: Response Types and Decode

### 6.1 Work

Define the `NiriResponse` type and decode logic. This can live in `requests.nim` (since responses are the reply to requests) or in a separate `responses.nim`. For simplicity, add to `requests.nim`.

#### 6.1.1 Define NiriResponse

```nim
type
  NiriResponseKind* = enum
    nresHandled, nresVersion, nresOutputs, nresWorkspaces, nresWindows,
    nresLayers, nresKeyboardLayouts, nresFocusedOutput, nresFocusedWindow,
    nresOverviewState, nresCasts, nresPickWindow, nresPickColor,
    nresUnknown

  NiriResponse* = object
    case kind*: NiriResponseKind
    of nresHandled: discard
    of nresVersion: version*: string
    of nresOutputs: outputs*: Table[string, Output]
    of nresWorkspaces: workspaces*: seq[Workspace]
    of nresWindows: windows*: seq[Window]
    of nresLayers: layers*: seq[LayerSurface]
    of nresKeyboardLayouts: keyboardLayouts*: KeyboardLayouts
    of nresFocusedOutput: focusedOutput*: Option[Output]
    of nresFocusedWindow: focusedWindow*: Option[Window]
    of nresOverviewState: isOverviewOpen*: bool
    of nresCasts: casts*: seq[Cast]
    of nresPickWindow: pickedWindow*: Option[Window]
    of nresPickColor: pickedColor*: Option[???]  # check niri type
    of nresUnknown:
      unknownKind*: string
      unknownRaw*: string
```

#### 6.1.2 Implement `fromReplyJson`

```nim
proc decodeResponse*(node: JsonNode): Result[NiriResponse, NimriIpcError]
  ## Takes the raw reply JSON (before Reply wrapper unwrap).
  ## 1. Calls parseReply to handle Ok/Err wrapper.
  ##    - If Err, returns NimriIpcError(kind: NiriError, ...).
  ## 2. Calls parseTaggedVariant on the inner Response.
  ## 3. Based on the tag, decodes the payload into the appropriate NiriResponse variant.
  ## 4. Unknown response tags -> NiriResponse(kind: nresUnknown, ...).
```

### 6.2 Testing (`test_requests.nim` — add to existing)

```
Suite: response decoding

Test 14: "decode Version response"
  - Input: parseJson("""{"Ok": {"Version": "0.1.9"}}""")
  - Assert decodeResponse returns NiriResponse with kind nresVersion, version == "0.1.9".

Test 15: "decode Handled response"
  - Input: parseJson("""{"Ok": "Handled"}""")
  - Assert decodeResponse returns NiriResponse with kind nresHandled.

Test 16: "decode Windows response from fixture"
  - Load tests/fixtures/responses/windows.json.
  - Assert decodeResponse returns kind nresWindows.
  - Assert windows seq is non-empty.
  - Assert first window has valid fields.

Test 17: "decode Workspaces response from fixture"
  - Load tests/fixtures/responses/workspaces.json.
  - Assert decodeResponse returns kind nresWorkspaces.

Test 18: "decode Outputs response from fixture"
  - Load tests/fixtures/responses/outputs.json.
  - Assert decodeResponse returns kind nresOutputs.
  - Assert outputs table has at least one entry.
  - Assert each output has a name matching its table key.

Test 19: "decode FocusedWindow response from fixture"
  - Load tests/fixtures/responses/focused_window.json.
  - Assert decodeResponse returns kind nresFocusedWindow.

Test 20: "decode FocusedOutput response from fixture"
  - Load tests/fixtures/responses/focused_output.json.
  - Assert decodeResponse returns kind nresFocusedOutput.

Test 21: "decode Err response"
  - Input: parseJson("""{"Err": "Unknown request"}""")
  - Assert decodeResponse returns an error with kind NiriError.
  - Assert the error message contains "Unknown request".

Test 22: "decode unknown response variant"
  - Input: parseJson("""{"Ok": {"FutureResponse": {"data": 1}}}""")
  - Assert decodeResponse returns kind nresUnknown, unknownKind == "FutureResponse".

Test 23: "decode KeyboardLayouts response from fixture"
  - Load fixture, decode, assert non-empty names list.

Test 24: "decode Layers response from fixture"
  - Load fixture, decode, assert kind nresLayers.
```

**Pass criteria:** All response decode tests pass (Tests 14-24). The decode path handles all captured fixtures without error.

---

## Step 7: Events (`events.nim`)

### 7.1 Work

Define the `NiriEvent` type and decode logic. Depends on `codec.nim` and `models.nim`.

#### 7.1.1 Define NiriEvent

```nim
type
  NiriEventKind* = enum
    # Workspace
    neWorkspacesChanged, neWorkspaceActivated,
    neWorkspaceUrgencyChanged, neWorkspaceActiveWindowChanged,
    # Window
    neWindowsChanged, neWindowOpenedOrChanged, neWindowClosed,
    neWindowFocusChanged, neWindowFocusTimestampChanged,
    neWindowUrgencyChanged, neWindowLayoutsChanged,
    # Keyboard
    neKeyboardLayoutsChanged, neKeyboardLayoutSwitched,
    # System
    neOverviewOpenedOrClosed, neConfigLoaded, neScreenshotCaptured,
    # Cast
    neCastsChanged, neCastStartedOrChanged, neCastStopped,
    # Unknown
    neUnknown

  NiriEvent* = object
    case kind*: NiriEventKind
    of neWorkspacesChanged: workspaces*: seq[Workspace]
    of neWorkspaceActivated:
      activatedId*: WorkspaceId
      activatedFocused*: bool
    of neWorkspaceUrgencyChanged:
      urgentWsId*: WorkspaceId
      wsUrgent*: bool
    of neWorkspaceActiveWindowChanged:
      wsActiveWinWsId*: WorkspaceId
      wsActiveWinId*: Option[WindowId]
    of neWindowsChanged: windows*: seq[Window]
    of neWindowOpenedOrChanged: window*: Window
    of neWindowClosed: closedId*: WindowId
    of neWindowFocusChanged: focusedId*: Option[WindowId]
    of neWindowFocusTimestampChanged:
      focusTsId*: WindowId
      focusTimestamp*: Timestamp
    of neWindowUrgencyChanged:
      urgentWinId*: WindowId
      winUrgent*: bool
    of neWindowLayoutsChanged:
      layoutChanges*: seq[tuple[id: WindowId, layout: WindowLayout]]
    of neKeyboardLayoutsChanged: kbLayouts*: KeyboardLayouts
    of neKeyboardLayoutSwitched: kbIdx*: uint8
    of neOverviewOpenedOrClosed: isOverviewOpen*: bool
    of neConfigLoaded: configFailed*: bool
    of neScreenshotCaptured: screenshotPath*: Option[string]
    of neCastsChanged: casts*: seq[Cast]
    of neCastStartedOrChanged: cast*: Cast
    of neCastStopped: stoppedStreamId*: uint64
    of neUnknown:
      unknownEventKind*: string
      unknownEventRaw*: string
```

#### 7.1.2 Implement `decodeEvent`

```nim
proc decodeEvent*(node: JsonNode): Result[NiriEvent, string]
  ## Decodes a single event JSON value into a typed NiriEvent.
  ## Uses parseTaggedVariant to identify the event kind.
  ## Unknown event types -> neUnknown variant.
```

#### 7.1.3 Implement `decodeEventLine`

```nim
proc decodeEventLine*(line: string): Result[NiriEvent, NimriIpcError]
  ## Convenience: parses a JSON string and decodes as event.
  ## Wraps JSON parse errors into NimriIpcError.
```

#### 7.1.4 Event kind classification

```nim
proc isWindowEvent*(event: NiriEvent): bool
proc isWorkspaceEvent*(event: NiriEvent): bool
proc isKeyboardEvent*(event: NiriEvent): bool
proc isSystemEvent*(event: NiriEvent): bool
proc isCastEvent*(event: NiriEvent): bool
```

### 7.2 Testing (`test_events.nim`)

```
Suite: event decoding — workspace events

Test 1: "WorkspacesChanged decode"
  - Input: fixture or synthetic JSON: {"WorkspacesChanged": {"workspaces": [...]}}
  - Assert kind == neWorkspacesChanged.
  - Assert workspaces seq is populated with valid Workspace objects.

Test 2: "WorkspaceActivated decode"
  - Input: {"WorkspaceActivated": {"id": 5, "focused": true}}
  - Assert kind == neWorkspaceActivated, activatedId == WorkspaceId(5), activatedFocused == true.

Test 3: "WorkspaceUrgencyChanged decode"
  - Input: {"WorkspaceUrgencyChanged": {"id": 3, "urgent": false}}
  - Assert correct fields.

Test 4: "WorkspaceActiveWindowChanged decode"
  - Input with activeWindowId present and absent (null).

Suite: event decoding — window events

Test 5: "WindowsChanged decode"
  - Input from fixture: full windows array.
  - Assert all windows decode.

Test 6: "WindowOpenedOrChanged decode"
  - Input from fixture: single window.
  - Assert window fields populated.

Test 7: "WindowClosed decode"
  - Input: {"WindowClosed": {"id": 42}}
  - Assert closedId == WindowId(42).

Test 8: "WindowFocusChanged with window ID"
  - Input: {"WindowFocusChanged": {"id": 7}}
  - Assert focusedId == some(WindowId(7)).

Test 9: "WindowFocusChanged with no focus (null)"
  - Input: {"WindowFocusChanged": {"id": null}}
  - Assert focusedId == none(WindowId).

Test 10: "WindowLayoutsChanged batch decode"
  - Input: {"WindowLayoutsChanged": {"changes": [[42, {...layout...}], [43, {...layout...}]]}}
  - Assert layoutChanges has 2 entries.
  - Assert each tuple has correct WindowId and decoded WindowLayout.

Test 11: "WindowUrgencyChanged decode"
  - Assert correct id and urgent fields.

Test 12: "WindowFocusTimestampChanged decode"
  - Assert correct id and Timestamp fields (secs, nanos).

Suite: event decoding — keyboard events

Test 13: "KeyboardLayoutsChanged decode"
  - Assert names and currentIdx.

Test 14: "KeyboardLayoutSwitched decode"
  - Assert kbIdx.

Suite: event decoding — system events

Test 15: "OverviewOpenedOrClosed decode"
  - Assert isOverviewOpen for both true and false.

Test 16: "ConfigLoaded decode"
  - Assert configFailed for both true and false.

Test 17: "ScreenshotCaptured decode with path"
  - Assert screenshotPath == some("/path/to/screenshot.png").

Test 18: "ScreenshotCaptured decode without path (null)"
  - Assert screenshotPath == none.

Suite: event decoding — cast events

Test 19: "CastsChanged decode"
  - Assert casts seq.

Test 20: "CastStopped decode"
  - Assert stoppedStreamId.

Suite: forward compatibility

Test 21: "unknown event type decodes to neUnknown"
  - Input: {"FutureEventType": {"data": 123}}
  - Assert kind == neUnknown, unknownEventKind == "FutureEventType".
  - Assert unknownEventRaw contains the original JSON.

Test 22: "known event with extra unknown fields"
  - Input: {"WindowClosed": {"id": 42, "futureField": "abc", "anotherField": [1,2,3]}}
  - Assert decodes successfully to neWindowClosed with closedId == WindowId(42).

Test 23: "decodeEventLine from raw string"
  - Input: """{"WindowClosed": {"id": 42}}"""
  - Assert decodes to correct event.

Test 24: "decodeEventLine with invalid JSON"
  - Input: "not json at all"
  - Assert returns NimriIpcError with kind JsonDecodeError.

Suite: event classification

Test 25: "isWindowEvent returns true for window events"
  - Assert true for neWindowClosed, neWindowFocusChanged, neWindowsChanged, etc.
  - Assert false for neWorkspaceActivated, neKeyboardLayoutSwitched.

Test 26: "isWorkspaceEvent returns true for workspace events"
  - Assert true for neWorkspacesChanged, neWorkspaceActivated, etc.
  - Assert false for neWindowClosed.

Suite: event decode from captured fixtures

Test 27: "decode all events from captured raw_stream"
  - Load each individual event fixture file.
  - Assert decodeEventLine succeeds for each.
  - Assert no event decodes to neUnknown (since these are from the current niri version).
```

**Pass criteria:** All 27 tests pass. `events.nim` compiles with only `codec.nim`, `models.nim`, `std/json`, `std/options`, and `results` as dependencies. No I/O imports, no dependency on requests/actions/client/stream.

---

## Step 8: Command Client (`client.nim`)

### 8.1 Work

Implement the socket transport for command request-response exchanges. Depends on `codec.nim`, `models.nim`, `requests.nim`, `actions.nim`, and `errors.nim`.

#### 8.1.1 Socket path resolution

```nim
const NiriSocketEnv* = "NIRI_SOCKET"

proc resolveSocketPath*(config: NiriConnectConfig): Result[string, NimriIpcError]
  ## 1. If config.socketPath is some, return it.
  ## 2. Else read NIRI_SOCKET env var. If set and non-empty, return it.
  ## 3. Else return SocketPathMissing error.
```

#### 8.1.2 NiriConnectConfig

```nim
type
  NiriConnectConfig* = object
    socketPath*: Option[string]
    commandTimeout*: Duration    ## default 5.seconds
```

Provide a default initializer:
```nim
proc initNiriConnectConfig*(
  socketPath = none(string),
  commandTimeout = initDuration(seconds = 5)
): NiriConnectConfig
```

#### 8.1.3 NiriClient type

```nim
type
  NiriClient* = ref object
    socket: AsyncSocket
    config: NiriConnectConfig
    connected: bool
```

#### 8.1.4 openClient

```nim
proc openClient*(config = initNiriConnectConfig()): Future[Result[NiriClient, NimriIpcError]] {.async.}
  ## 1. Resolve socket path.
  ## 2. Create AsyncSocket (AF_UNIX, SOCK_STREAM).
  ## 3. Connect to socket path.
  ## 4. On failure, return SocketConnectFailed error.
  ## 5. Return NiriClient.
```

#### 8.1.5 send (raw)

```nim
proc send*(client: NiriClient, request: NiriRequest): Future[Result[NiriResponse, NimriIpcError]] {.async.}
  ## 1. Serialize request to JSON via toJson.
  ## 2. Write JSON string + "\n" to socket.
  ## 3. Read response line from socket (with timeout).
  ## 4. Parse JSON.
  ## 5. Call decodeResponse to unwrap Reply and decode Response.
  ## 6. Return typed NiriResponse.
```

Read logic must handle:
- Reading until a `\n` delimiter is found.
- Timeout via `withTimeout` or `sleepAsync` + `race`.
- Partial reads accumulated into a buffer.

#### 8.1.6 Convenience query procs

```nim
proc getWindows*(client: NiriClient): Future[Result[seq[Window], NimriIpcError]] {.async.}
  ## Sends requestWindows(), asserts response kind is nresWindows, extracts windows.

proc getWorkspaces*(client: NiriClient): Future[Result[seq[Workspace], NimriIpcError]] {.async.}
proc getOutputs*(client: NiriClient): Future[Result[Table[string, Output], NimriIpcError]] {.async.}
proc getFocusedWindow*(client: NiriClient): Future[Result[Option[Window], NimriIpcError]] {.async.}
proc getFocusedOutput*(client: NiriClient): Future[Result[Option[Output], NimriIpcError]] {.async.}
proc getVersion*(client: NiriClient): Future[Result[string, NimriIpcError]] {.async.}
```

Each:
1. Calls `send` with the appropriate request.
2. Checks response kind matches expected.
3. On mismatch, returns `ResponseMismatch` error.
4. Extracts and returns the typed payload.

#### 8.1.7 doAction

```nim
proc doAction*(client: NiriClient, action: NiriAction): Future[Result[void, NimriIpcError]] {.async.}
  ## Sends requestAction(action), expects Handled response.
```

#### 8.1.8 close

```nim
proc close*(client: NiriClient) {.async.}
  ## Idempotent close. Sets connected = false.
```

### 8.2 Testing (`test_client.nim`)

Client tests require either a mock socket or a live Niri connection. Implement both tiers.

#### 8.2.1 Mock socket tests

Create a helper that sets up a Unix socket pair (or uses `socketpair`) where the test controls one end:

```nim
proc createMockPair(): (AsyncSocket, AsyncSocket)
  ## Returns (clientSide, serverSide) connected pair.
```

```
Suite: socket path resolution

Test 1: "explicit path used when provided"
  - Config with socketPath = some("/tmp/test.sock").
  - Assert resolveSocketPath returns "/tmp/test.sock".

Test 2: "NIRI_SOCKET env var used as fallback"
  - Set env var, config with no socketPath.
  - Assert resolveSocketPath returns the env var value.
  - Clean up env var.

Test 3: "error when no path available"
  - Unset env var, no socketPath in config.
  - Assert resolveSocketPath returns SocketPathMissing error.

Suite: request-response round-trip (mock)

Test 4: "send Version request, receive response"
  - Create mock pair.
  - Construct NiriClient with client-side socket.
  - In a parallel async task, read from server-side, assert received "\"Version\"\n".
  - Write back """{"Ok": {"Version": "0.1.9"}}\n""" from server-side.
  - Assert send(requestVersion()) returns NiriResponse(kind: nresVersion, version: "0.1.9").

Test 5: "send Windows request, receive response"
  - Similar to Test 4 but with a Windows response payload (use fixture data).

Test 6: "send action, receive Handled"
  - Write """{"Ok": "Handled"}\n""" from server-side.
  - Assert doAction returns ok(void).

Test 7: "niri error response"
  - Write """{"Err": "Unknown request"}\n""" from server-side.
  - Assert send returns NimriIpcError(kind: NiriError, message contains "Unknown request").

Suite: error paths (mock)

Test 8: "connection refused"
  - Attempt openClient with a path to a non-existent socket.
  - Assert returns SocketConnectFailed error.

Test 9: "read timeout"
  - Create mock pair. Don't write anything from server side.
  - Call send with a short timeout.
  - Assert returns Timeout error.

Test 10: "malformed JSON response"
  - Write "not json\n" from server-side.
  - Assert returns JsonDecodeError.

Test 11: "close is idempotent"
  - Call close twice. Assert no error on second call.

Suite: convenience procs (mock)

Test 12: "getWindows returns typed seq[Window]"
  - Mock server returns a valid Windows response.
  - Assert getWindows returns ok with non-empty seq.

Test 13: "getOutputs returns typed Table"
  - Mock server returns a valid Outputs response.
  - Assert getOutputs returns ok with non-empty table.

Test 14: "response mismatch error"
  - Send requestWindows but mock server returns a Version response.
  - Assert getWindows returns ResponseMismatch error.
```

#### 8.2.2 Live integration tests (conditional)

```
Suite: live integration (skip if NIRI_SOCKET not set)

Test 15: "connect to live niri"
  - openClient with default config.
  - Assert connection succeeds.

Test 16: "getVersion from live niri"
  - Assert returns a non-empty version string.

Test 17: "getWindows from live niri"
  - Assert returns ok (may be empty seq if no windows).

Test 18: "getWorkspaces from live niri"
  - Assert returns ok with at least one workspace.

Test 19: "getOutputs from live niri"
  - Assert returns ok with at least one output.

Test 20: "getFocusedWindow from live niri"
  - Assert returns ok (value may be none).

Test 21: "getFocusedOutput from live niri"
  - Assert returns ok (value should be some).
```

**Pass criteria:**
- All mock tests (1-14) pass in all environments.
- Live tests (15-21) pass when `NIRI_SOCKET` is set, skip cleanly otherwise.
- `client.nim` compiles with `codec`, `models`, `requests`, `actions`, `errors`, `std/asyncdispatch`, `std/asyncnet`, `std/json`, `std/options`, `std/os`, `results`.
- `client.nim` does not import `events.nim` or `stream.nim`.

---

## Step 9: Event Stream (`stream.nim`)

### 9.1 Work

Implement the event stream connection. Depends on `codec.nim`, `models.nim`, `events.nim`, and `errors.nim`. Must NOT depend on `client.nim`.

#### 9.1.1 NiriEventStream type

```nim
type
  NiriEventStream* = ref object
    socket: AsyncSocket
    config: NiriConnectConfig
    frameBuffer: FrameBuffer    ## from codec.nim
    connected: bool
```

#### 9.1.2 openEventStream

```nim
proc openEventStream*(config = initNiriConnectConfig()): Future[Result[NiriEventStream, NimriIpcError]] {.async.}
  ## 1. Resolve socket path (reuse resolveSocketPath from client.nim, or
  ##    extract to a shared internal utility).
  ## 2. Create and connect AsyncSocket.
  ## 3. Send "\"EventStream\"\n" to the socket.
  ## 4. Read response line. Expect {"Ok": "Handled"}.
  ## 5. Shut down the write end of the socket (socket.shutdownWrite or similar).
  ## 6. Return NiriEventStream with initialized FrameBuffer.
```

**Note on shared code:** `resolveSocketPath` is needed by both `client.nim` and `stream.nim`. Since they must not depend on each other, extract socket path resolution to a small internal module (e.g., `internal/transport.nim` or add it to `errors.nim` since it only depends on `NimriIpcError` and `os`), or duplicate the simple logic.

#### 9.1.3 next

```nim
proc next*(stream: NiriEventStream,
           timeout = initDuration(milliseconds = 0)): Future[Result[NiriEvent, NimriIpcError]] {.async.}
  ## 1. Check frameBuffer for a buffered complete frame.
  ## 2. If none, read from socket into frameBuffer.
  ##    - If timeout > 0, apply timeout to the read.
  ##    - If timeout == 0 (default), wait indefinitely.
  ## 3. On read EOF, return ConnectionClosed error.
  ## 4. On read failure, return SocketReadFailed error.
  ## 5. Feed data to frameBuffer.
  ## 6. Extract next frame.
  ## 7. Parse JSON, decode event via decodeEventLine.
  ## 8. Return typed NiriEvent.
```

Loop internally until a complete frame is available (partial reads may require multiple socket reads).

#### 9.1.4 waitFor

```nim
proc waitFor*(stream: NiriEventStream,
              predicate: proc(e: NiriEvent): bool,
              timeout: Duration): Future[Result[NiriEvent, NimriIpcError]] {.async.}
  ## 1. Record start time.
  ## 2. Loop:
  ##    a. Calculate remaining timeout.
  ##    b. Call next() with remaining timeout.
  ##    c. If error, return error.
  ##    d. If predicate(event) is true, return event.
  ##    e. Otherwise, discard event and continue.
  ## 3. If total elapsed >= timeout, return Timeout error.
```

#### 9.1.5 close

```nim
proc close*(stream: NiriEventStream) {.async.}
  ## Idempotent close.
```

### 9.2 Testing (`test_stream.nim`)

#### 9.2.1 Frame parsing tests (using FrameBuffer from codec, tested here in stream context)

```
Suite: frame parsing in stream context

Test 1: "single event frame"
  - Create a mock socket pair.
  - Server writes: """{"WindowClosed": {"id": 1}}\n"""
  - Assert next() returns WindowClosed event.

Test 2: "multiple events in rapid succession"
  - Server writes 3 event lines in one write.
  - Assert 3 successive next() calls each return the correct event.

Test 3: "partial frame across reads"
  - Server writes first half of an event JSON, flush.
  - Server writes second half + newline, flush.
  - Assert next() returns the complete event (blocking until frame complete).

Test 4: "empty lines between events"
  - Server writes: """\n\n{"WindowClosed": {"id": 1}}\n\n"""
  - Assert next() returns the event, skipping empty lines.

Test 5: "malformed JSON frame"
  - Server writes: """not json\n"""
  - Assert next() returns JsonDecodeError.
```

#### 9.2.2 Event stream protocol tests (mock)

```
Suite: event stream lifecycle (mock)

Test 6: "openEventStream sends EventStream request"
  - Create a mock socket pair.
  - Server reads from its end and asserts it received "\"EventStream\"\n".
  - Server writes """{"Ok": "Handled"}\n""".
  - Assert openEventStream returns ok.

Test 7: "openEventStream fails on niri error"
  - Server responds with """{"Err": "Not supported"}\n""".
  - Assert openEventStream returns NiriError.

Test 8: "connection closed returns ConnectionClosed error"
  - Server closes socket after handshake.
  - Assert next() returns ConnectionClosed error.

Test 9: "timeout on next()"
  - Server sends nothing after handshake.
  - Call next(timeout = 100.milliseconds).
  - Assert returns Timeout error.
```

#### 9.2.3 waitFor tests (mock)

```
Suite: waitFor predicate matching

Test 10: "waitFor returns first matching event"
  - Server sends: WorkspacesChanged, WindowsChanged, WindowFocusChanged(id=7).
  - Call waitFor with predicate matching WindowFocusChanged.
  - Assert returns the WindowFocusChanged event (skipping first two).

Test 11: "waitFor times out if no match"
  - Server sends: WorkspacesChanged, WindowsChanged (no focus event).
  - Server stops sending.
  - Call waitFor with predicate matching WindowFocusChanged, timeout 200ms.
  - Assert returns Timeout error.

Test 12: "waitFor returns first match even if multiple qualify"
  - Server sends: WindowFocusChanged(id=1), WindowFocusChanged(id=2).
  - Call waitFor matching WindowFocusChanged.
  - Assert returns the first one (id=1).
```

#### 9.2.4 Live integration tests (conditional)

```
Suite: live event stream (skip if NIRI_SOCKET not set)

Test 13: "open event stream from live niri"
  - Assert openEventStream succeeds.

Test 14: "receive initial state events"
  - Open stream, call next() 4 times with timeout.
  - Assert at least WorkspacesChanged and WindowsChanged are received in the initial batch.

Test 15: "close event stream cleanly"
  - Open stream, close immediately, assert no error.
```

**Pass criteria:**
- All mock tests (1-12) pass in all environments.
- Live tests (13-15) pass when `NIRI_SOCKET` is set, skip cleanly otherwise.
- `stream.nim` does not import `client.nim`, `requests.nim`, or `actions.nim`.

---

## Step 10: Public API Module (`nimri_ipc.nim`)

### 10.1 Work

Wire everything together as re-exports. This module contains no logic — only imports and re-exports.

```nim
## nimri-ipc: Typed async Nim client for Niri compositor IPC.
##
## Usage:
##   import nimri_ipc
##
##   let client = (await openClient()).get
##   let windows = (await client.getWindows()).get
##   echo windows
##   await client.close()

import nimri_ipc/errors
export errors

import nimri_ipc/codec
# codec is internal — do NOT export. Only export if a raw JsonNode escape
# hatch is desired (see open decision #5 in concept).

import nimri_ipc/models
export models

import nimri_ipc/actions
export actions

import nimri_ipc/requests
export requests

import nimri_ipc/events
export events

import nimri_ipc/client
export client

import nimri_ipc/stream
export stream
```

### 10.2 Testing

```
Suite: public API surface

Test 1: "import nimri_ipc compiles"
  - A file containing only `import nimri_ipc` compiles without error.

Test 2: "all public types are accessible"
  - Assert the following types are accessible after import:
    NimriIpcError, NimriIpcErrorKind,
    WindowId, WorkspaceId, OutputName, WorkspaceIdx,
    Window, WindowLayout, Workspace, Output, LogicalOutput, Mode,
    Timestamp, KeyboardLayouts, LayerSurface, Cast,
    SizeChange, PositionChange, WorkspaceRef, LayoutSwitchTarget,
    ColumnDisplay, Transform,
    NiriRequest, NiriResponse,
    NiriAction,
    NiriEvent, NiriEventKind,
    NiriClient, NiriEventStream, NiriConnectConfig.

Test 3: "all public procs are accessible"
  - Assert the following procs resolve:
    openClient, send, getWindows, getWorkspaces, getOutputs,
    getFocusedWindow, getFocusedOutput, getVersion, doAction, close,
    openEventStream, next, waitFor,
    requestWindows, requestWorkspaces, requestAction, requestEventStream,
    focusWindowDown, closeWindow, quit, spawn, (representative sample).

Test 4: "codec internals are not exported"
  - Assert that `parseTaggedVariant`, `FrameBuffer`, `encodeUnitVariant`
    are NOT accessible from `import nimri_ipc`.
  - (This may require a compile-time check or a separate test file that
    tries to use these symbols and asserts a compile error.)

Suite: end-to-end workflow (mock)

Test 5: "full command workflow"
  - Using only `import nimri_ipc`:
  - Create mock socket pair.
  - openClient, getWindows, doAction, close.
  - Assert all operations succeed with mock responses.

Test 6: "full event stream workflow"
  - Using only `import nimri_ipc`:
  - Create mock socket pair.
  - openEventStream, next (3 events), waitFor, close.
  - Assert correct event decoding.
```

**Pass criteria:** All 6 tests pass. The public API module compiles. The import provides everything a caller needs.

---

## Step 11: Final Validation

### 11.1 Full test suite

Run the complete test suite:

```bash
devenv shell -- nimble test
```

**All tests across all modules must pass.** The total count should be approximately:
- `test_errors.nim`: 4 tests
- `test_codec.nim`: 33 tests
- `test_models.nim`: 20 tests
- `test_requests.nim`: 24 tests (7 encode + 11 response decode + 6 added with response work)
- `test_actions.nim`: 13 tests
- `test_events.nim`: 27 tests
- `test_client.nim`: 14 mock + 7 live = 21 tests
- `test_stream.nim`: 12 mock + 3 live = 15 tests
- `test_nimri_ipc.nim`: 6 tests
- **Total: ~163 tests**

### 11.2 Dependency rule verification

Verify no forbidden couplings exist:

```bash
# client.nim must not import stream or events
devenv shell -- grep -n "import.*stream\|import.*events" src/nimri_ipc/client.nim
# Should return nothing

# stream.nim must not import client, requests, or actions
devenv shell -- grep -n "import.*client\|import.*requests\|import.*actions" src/nimri_ipc/stream.nim
# Should return nothing

# actions.nim must not import asyncdispatch, asyncnet, os
devenv shell -- grep -n "import.*asyncdispatch\|import.*asyncnet\|import.*net\|import.*os" src/nimri_ipc/actions.nim
# Should return nothing

# events.nim must not import requests, actions, client, stream
devenv shell -- grep -n "import.*requests\|import.*actions\|import.*client\|import.*stream" src/nimri_ipc/events.nim
# Should return nothing

# models.nim must not import client, stream, errors
devenv shell -- grep -n "import.*client\|import.*stream\|import.*errors" src/nimri_ipc/models.nim
# Should return nothing
```

### 11.3 Live integration test (full)

On a machine with Niri running:

```bash
devenv shell -- env NIMRI_IPC_LIVE_TESTS=1 nimble test
```

All live tests should pass.

### 11.4 Compile with warnings as errors

```bash
devenv shell -- nim c --warningAsError:on --hints:off src/nimri_ipc/nimri_ipc.nim
```

Must compile with no warnings.

### 11.5 Documentation check

Verify that all public procs and types have doc comments:

```bash
devenv shell -- nim doc --project src/nimri_ipc/nimri_ipc.nim
# Review generated docs for completeness
```

---

## Appendix A: Fixture File Reference

| Fixture Path | Source Command | Used By |
|---|---|---|
| `responses/version.json` | `devenv shell -- niri msg -j version` | test_requests (response decode) |
| `responses/outputs.json` | `devenv shell -- niri msg -j outputs` | test_models, test_requests |
| `responses/workspaces.json` | `devenv shell -- niri msg -j workspaces` | test_models, test_requests |
| `responses/windows.json` | `devenv shell -- niri msg -j windows` | test_models, test_requests |
| `responses/windows_extra_fields.json` | Synthetic (hand-edited) | test_models (forward compat) |
| `responses/focused_window.json` | `devenv shell -- niri msg -j focused-window` | test_requests |
| `responses/focused_output.json` | `devenv shell -- niri msg -j focused-output` | test_requests |
| `responses/layers.json` | `devenv shell -- niri msg -j layers` | test_requests |
| `responses/keyboard_layouts.json` | `devenv shell -- niri msg -j keyboard-layouts` | test_models, test_requests |
| `events/workspaces_changed.json` | Extracted from event stream | test_events |
| `events/windows_changed.json` | Extracted from event stream | test_events |
| `events/window_opened_or_changed.json` | Extracted from event stream | test_events |
| `events/window_closed.json` | Synthetic or extracted | test_events |
| `events/window_focus_changed.json` | Extracted from event stream | test_events |
| `events/window_layouts_changed.json` | Extracted from event stream | test_events |
| `events/keyboard_layouts_changed.json` | Extracted from event stream | test_events |
| `events/keyboard_layout_switched.json` | Extracted from event stream | test_events |
| `events/unknown_event.json` | Synthetic | test_events (forward compat) |

## Appendix B: Step Dependency Graph

```text
Step 0: Scaffold
  │
  ├─> Step 1: errors.nim
  │     │
  │     └─> Step 2: codec.nim
  │           │
  │           └─> Step 3: models.nim
  │                 │
  │                 ├─> Step 5: actions.nim ──┐
  │                 │                         │
  │                 ├─> Step 4: requests.nim <─┘
  │                 │     │
  │                 │     └─> Step 6: responses (in requests.nim)
  │                 │           │
  │                 │           └─> Step 8: client.nim
  │                 │
  │                 └─> Step 7: events.nim
  │                       │
  │                       └─> Step 9: stream.nim
  │
  └─> Step 10: nimri_ipc.nim (after 8 + 9)
        │
        └─> Step 11: Final validation
```

## Appendix C: Shared Code Extraction

Steps 8 and 9 both need socket path resolution. To avoid violating the forbidden coupling rule (client must not import stream, stream must not import client), extract shared transport utilities:

**Option A:** Add `resolveSocketPath` to `errors.nim` (it only needs `NimriIpcError` and `std/os`). Simple, no new module.

**Option B:** Create `src/nimri_ipc/internal/transport.nim` with:
```nim
proc resolveSocketPath*(config: NiriConnectConfig): Result[string, NimriIpcError]
proc connectSocket*(path: string): Future[Result[AsyncSocket, NimriIpcError]]
proc readLine*(socket: AsyncSocket, timeout: Duration): Future[Result[string, NimriIpcError]]
```

Both `client.nim` and `stream.nim` import this internal module. It is not re-exported by `nimri_ipc.nim`.

**Recommendation:** Option B. It keeps `errors.nim` pure (no I/O, no OS imports) and consolidates socket utilities. Add `internal/transport.nim` during Step 8 and use it in Step 9.
