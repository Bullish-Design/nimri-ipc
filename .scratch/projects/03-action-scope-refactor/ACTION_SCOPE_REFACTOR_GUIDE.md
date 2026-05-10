# ACTION_SCOPE_REFACTOR_GUIDE.md

## Overview

This guide walks you through completing the `nimri-ipc` action surface from 23 variants to the full Niri IPC protocol (141 action variants). It also fixes critical wire format bugs in the existing implementation.

**Read this entire document before writing any code.**

---

## Critical Wire Format Bugs (Fix First)

Before expanding the action surface, you must fix these wire format mismatches. The current implementation does NOT match Niri's actual serde wire format in several places.

### Bug 1: Empty struct variants encoded as unit variants

**The problem:** Every action in Niri's Rust `Action` enum is a **struct variant** (even the ones with no fields). Rust serde serializes empty struct variants as `{"VariantName": {}}`, NOT as `"VariantName"`.

Current (WRONG):
```json
"FocusWindowDown"
```

Correct (Niri wire format):
```json
{"FocusWindowDown": {}}
```

**Where it lives:** `actions.nim:101-102` — the `else` branch calls `encodeUnitVariant()` which produces a JSON string. It should call `encodeStructVariant()` with an empty object.

**Fix:** Change the `else` branch from:
```nim
else:
  encodeUnitVariant(ActionWireNames[a.kind])
```
to:
```nim
else:
  encodeStructVariant(ActionWireNames[a.kind], newJObject())
```

### Bug 2: `Quit` is not a unit action

**The problem:** `Quit` has a `skip_confirmation: bool` field in the protocol. The current code treats it as unit.

Current (WRONG):
```json
"Quit"
```

Correct:
```json
{"Quit": {"skip_confirmation": false}}
```

**Fix:** Add `skip_confirmation` parameter to `naQuit` in the `NiriAction` object and the `quit()` constructor. Default to `false`.

### Bug 3: `Screenshot` is parameterized

**The problem:** `Screenshot` has `show_pointer: bool` and `path: Option<String>`. Current code treats it as unit.

Correct:
```json
{"Screenshot": {"show_pointer": false, "path": null}}
```

**Fix:** Remove `naScreenshot` from the unit branch. Add fields and encode properly.

### Bug 4: `Spawn` field name missing

**The problem:** Spawn has a `command` field wrapping the array.

Current (WRONG):
```json
{"Spawn": ["alacritty", "--title", "test"]}
```

Correct:
```json
{"Spawn": {"command": ["alacritty", "--title", "test"]}}
```

**Where:** `actions.nim:84` — wraps `%a.args` directly instead of `%*{"command": %a.args}`.

### Bug 5: `SpawnSh` field name missing

Current (WRONG): `{"SpawnSh": "echo hello"}`
Correct: `{"SpawnSh": {"command": "echo hello"}}`

**Where:** `actions.nim:86`

### Bug 6: `SetColumnDisplay` field name missing

Current (WRONG): `{"SetColumnDisplay": "Tabbed"}`
Correct: `{"SetColumnDisplay": {"display": "Tabbed"}}`

**Where:** `actions.nim:92-93`

### Bug 7: `SwitchLayout` field name missing

Current (WRONG): `{"SwitchLayout": "Next"}`
Correct: `{"SwitchLayout": {"layout": "Next"}}`

**Where:** `actions.nim:90`

### Summary of the root cause

Every Niri action is a **struct variant**. The payload is always a JSON object `{...}`, never a bare value. The struct's field names must appear as keys inside that object. The only exception is ColumnDisplay and LayoutSwitchTarget themselves which are separate enums with their own unit/struct variant encoding.

After fixing these bugs, update all tests in `test_actions.nim` to match the corrected wire format.

---

## Architecture Constraints (Do Not Violate)

1. **`actions.nim` must remain pure** — no transport/I/O imports. Only import `codec`, `models`, `std/json`, `std/options`.
2. **One-way dependency**: `requests.nim` → `actions.nim`. Never the reverse.
3. **JSON encoding must match Rust serde externally-tagged enum format exactly.**
4. **Nim discriminated union `case` branches can group variants that share the same field layout.**

---

## Full Protocol Action Inventory (141 variants)

Below is the complete action surface organized by category. Each entry shows:
- Wire name (PascalCase, exact match required)
- Fields (snake_case, exact match required)
- `()` = no meaningful fields (encode as empty object `{}`)

### System / Lifecycle (9)
| # | Wire Name | Fields |
|---|-----------|--------|
| 1 | `Quit` | `skip_confirmation: bool` |
| 2 | `PowerOffMonitors` | () |
| 3 | `PowerOnMonitors` | () |
| 4 | `Spawn` | `command: [string]` (array) |
| 5 | `SpawnSh` | `command: string` |
| 6 | `DoScreenTransition` | `delay_ms: Option<u16>` |
| 7 | `LoadConfigFile` | `path: Option<string>` |
| 8 | `ShowHotkeyOverlay` | () |
| 9 | `ToggleKeyboardShortcutsInhibit` | () |

### Screenshots (3)
| # | Wire Name | Fields |
|---|-----------|--------|
| 10 | `Screenshot` | `show_pointer: bool`, `path: Option<string>` |
| 11 | `ScreenshotScreen` | `write_to_disk: bool`, `show_pointer: bool`, `path: Option<string>` |
| 12 | `ScreenshotWindow` | `id: Option<u64>`, `write_to_disk: bool`, `show_pointer: bool`, `path: Option<string>` |

### Window Focus (20)
| # | Wire Name | Fields |
|---|-----------|--------|
| 13 | `CloseWindow` | `id: Option<u64>` |
| 14 | `FullscreenWindow` | `id: Option<u64>` |
| 15 | `ToggleWindowedFullscreen` | `id: Option<u64>` |
| 16 | `FocusWindow` | `id: u64` |
| 17 | `FocusWindowInColumn` | `index: u8` |
| 18 | `FocusWindowPrevious` | () |
| 19 | `FocusWindowDown` | () |
| 20 | `FocusWindowUp` | () |
| 21 | `FocusWindowTop` | () |
| 22 | `FocusWindowBottom` | () |
| 23 | `FocusWindowDownOrTop` | () |
| 24 | `FocusWindowUpOrBottom` | () |
| 25 | `FocusWindowDownOrColumnLeft` | () |
| 26 | `FocusWindowDownOrColumnRight` | () |
| 27 | `FocusWindowUpOrColumnLeft` | () |
| 28 | `FocusWindowUpOrColumnRight` | () |
| 29 | `FocusWindowOrMonitorUp` | () |
| 30 | `FocusWindowOrMonitorDown` | () |
| 31 | `FocusWindowOrWorkspaceDown` | () |
| 32 | `FocusWindowOrWorkspaceUp` | () |

### Column Focus (9)
| # | Wire Name | Fields |
|---|-----------|--------|
| 33 | `FocusColumnLeft` | () |
| 34 | `FocusColumnRight` | () |
| 35 | `FocusColumnFirst` | () |
| 36 | `FocusColumnLast` | () |
| 37 | `FocusColumnRightOrFirst` | () |
| 38 | `FocusColumnLeftOrLast` | () |
| 39 | `FocusColumn` | `index: usize` |
| 40 | `FocusColumnOrMonitorLeft` | () |
| 41 | `FocusColumnOrMonitorRight` | () |

### Window Movement (10)
| # | Wire Name | Fields |
|---|-----------|--------|
| 42 | `MoveWindowDown` | () |
| 43 | `MoveWindowUp` | () |
| 44 | `MoveWindowDownOrToWorkspaceDown` | () |
| 45 | `MoveWindowUpOrToWorkspaceUp` | () |
| 46 | `ConsumeOrExpelWindowLeft` | `id: Option<u64>` |
| 47 | `ConsumeOrExpelWindowRight` | `id: Option<u64>` |
| 48 | `ConsumeWindowIntoColumn` | () |
| 49 | `ExpelWindowFromColumn` | () |
| 50 | `SwapWindowRight` | () |
| 51 | `SwapWindowLeft` | () |

### Column Operations (17)
| # | Wire Name | Fields |
|---|-----------|--------|
| 52 | `MoveColumnLeft` | () |
| 53 | `MoveColumnRight` | () |
| 54 | `MoveColumnToFirst` | () |
| 55 | `MoveColumnToLast` | () |
| 56 | `MoveColumnLeftOrToMonitorLeft` | () |
| 57 | `MoveColumnRightOrToMonitorRight` | () |
| 58 | `MoveColumnToIndex` | `index: usize` |
| 59 | `ToggleColumnTabbedDisplay` | () |
| 60 | `SetColumnDisplay` | `display: ColumnDisplay` |
| 61 | `CenterColumn` | () |
| 62 | `CenterWindow` | `id: Option<u64>` |
| 63 | `CenterVisibleColumns` | () |
| 64 | `MaximizeColumn` | () |
| 65 | `SetColumnWidth` | `change: SizeChange` |
| 66 | `ExpandColumnToAvailableWidth` | () |
| 67 | `SwitchPresetColumnWidth` | () |
| 68 | `SwitchPresetColumnWidthBack` | () |

### Window Sizing (8)
| # | Wire Name | Fields |
|---|-----------|--------|
| 69 | `SetWindowWidth` | `id: Option<u64>`, `change: SizeChange` |
| 70 | `SetWindowHeight` | `id: Option<u64>`, `change: SizeChange` |
| 71 | `ResetWindowHeight` | `id: Option<u64>` |
| 72 | `SwitchPresetWindowWidth` | `id: Option<u64>` |
| 73 | `SwitchPresetWindowWidthBack` | `id: Option<u64>` |
| 74 | `SwitchPresetWindowHeight` | `id: Option<u64>` |
| 75 | `SwitchPresetWindowHeightBack` | `id: Option<u64>` |
| 76 | `MaximizeWindowToEdges` | `id: Option<u64>` |

### Layout (1)
| # | Wire Name | Fields |
|---|-----------|--------|
| 77 | `SwitchLayout` | `layout: LayoutSwitchTarget` |

### Workspace (15)
| # | Wire Name | Fields |
|---|-----------|--------|
| 78 | `FocusWorkspaceDown` | () |
| 79 | `FocusWorkspaceUp` | () |
| 80 | `FocusWorkspace` | `reference: WorkspaceReferenceArg` |
| 81 | `FocusWorkspacePrevious` | () |
| 82 | `MoveWindowToWorkspaceDown` | `focus: bool` |
| 83 | `MoveWindowToWorkspaceUp` | `focus: bool` |
| 84 | `MoveWindowToWorkspace` | `window_id: Option<u64>`, `reference: WorkspaceReferenceArg`, `focus: bool` |
| 85 | `MoveColumnToWorkspaceDown` | `focus: bool` |
| 86 | `MoveColumnToWorkspaceUp` | `focus: bool` |
| 87 | `MoveColumnToWorkspace` | `reference: WorkspaceReferenceArg`, `focus: bool` |
| 88 | `MoveWorkspaceDown` | () |
| 89 | `MoveWorkspaceUp` | () |
| 90 | `MoveWorkspaceToIndex` | `index: usize`, `reference: Option<WorkspaceReferenceArg>` |
| 91 | `SetWorkspaceName` | `name: string`, `workspace: Option<WorkspaceReferenceArg>` |
| 92 | `UnsetWorkspaceName` | `reference: Option<WorkspaceReferenceArg>` |

### Monitor Focus (7)
| # | Wire Name | Fields |
|---|-----------|--------|
| 93 | `FocusMonitorLeft` | () |
| 94 | `FocusMonitorRight` | () |
| 95 | `FocusMonitorDown` | () |
| 96 | `FocusMonitorUp` | () |
| 97 | `FocusMonitorPrevious` | () |
| 98 | `FocusMonitorNext` | () |
| 99 | `FocusMonitor` | `output: string` |

### Move Window to Monitor (7)
| # | Wire Name | Fields |
|---|-----------|--------|
| 100 | `MoveWindowToMonitorLeft` | () |
| 101 | `MoveWindowToMonitorRight` | () |
| 102 | `MoveWindowToMonitorDown` | () |
| 103 | `MoveWindowToMonitorUp` | () |
| 104 | `MoveWindowToMonitorPrevious` | () |
| 105 | `MoveWindowToMonitorNext` | () |
| 106 | `MoveWindowToMonitor` | `id: Option<u64>`, `output: string` |

### Move Column to Monitor (7)
| # | Wire Name | Fields |
|---|-----------|--------|
| 107 | `MoveColumnToMonitorLeft` | () |
| 108 | `MoveColumnToMonitorRight` | () |
| 109 | `MoveColumnToMonitorDown` | () |
| 110 | `MoveColumnToMonitorUp` | () |
| 111 | `MoveColumnToMonitorPrevious` | () |
| 112 | `MoveColumnToMonitorNext` | () |
| 113 | `MoveColumnToMonitor` | `output: string` |

### Move Workspace to Monitor (7)
| # | Wire Name | Fields |
|---|-----------|--------|
| 114 | `MoveWorkspaceToMonitorLeft` | () |
| 115 | `MoveWorkspaceToMonitorRight` | () |
| 116 | `MoveWorkspaceToMonitorDown` | () |
| 117 | `MoveWorkspaceToMonitorUp` | () |
| 118 | `MoveWorkspaceToMonitorPrevious` | () |
| 119 | `MoveWorkspaceToMonitorNext` | () |
| 120 | `MoveWorkspaceToMonitor` | `output: string`, `reference: Option<WorkspaceReferenceArg>` |

### Floating Windows (7)
| # | Wire Name | Fields |
|---|-----------|--------|
| 121 | `ToggleWindowFloating` | `id: Option<u64>` |
| 122 | `MoveWindowToFloating` | `id: Option<u64>` |
| 123 | `MoveWindowToTiling` | `id: Option<u64>` |
| 124 | `FocusFloating` | () |
| 125 | `FocusTiling` | () |
| 126 | `SwitchFocusBetweenFloatingAndTiling` | () |
| 127 | `MoveFloatingWindow` | `id: Option<u64>`, `x: PositionChange`, `y: PositionChange` |

### Window Opacity (1)
| # | Wire Name | Fields |
|---|-----------|--------|
| 128 | `ToggleWindowRuleOpacity` | `id: Option<u64>` |

### Screencasting (4)
| # | Wire Name | Fields |
|---|-----------|--------|
| 129 | `SetDynamicCastWindow` | `id: Option<u64>` |
| 130 | `SetDynamicCastMonitor` | `output: Option<string>` |
| 131 | `ClearDynamicCastTarget` | () |
| 132 | `StopCast` | `session_id: u64` |

### Overview (3)
| # | Wire Name | Fields |
|---|-----------|--------|
| 133 | `ToggleOverview` | () |
| 134 | `OpenOverview` | () |
| 135 | `CloseOverview` | () |

### Window Urgency (3)
| # | Wire Name | Fields |
|---|-----------|--------|
| 136 | `ToggleWindowUrgent` | `id: u64` |
| 137 | `SetWindowUrgent` | `id: u64` |
| 138 | `UnsetWindowUrgent` | `id: u64` |

### Debug (3)
| # | Wire Name | Fields |
|---|-----------|--------|
| 139 | `ToggleDebugTint` | () |
| 140 | `DebugToggleOpaqueRegions` | () |
| 141 | `DebugToggleDamage` | () |

---

## Field Type Families

Actions share a small number of field patterns. Group your `NiriAction` case branches by these patterns to minimize field duplication.

### Family: Empty (no fields) — ~75 variants
Wire format: `{"ActionName": {}}`
Examples: `FocusWindowDown`, `MoveColumnLeft`, `ToggleOverview`, `PowerOffMonitors`

### Family: OptionalWindowId — ~20 variants
Fields: `id: Option<u64>`
Wire format: `{"ActionName": {"id": null}}` or `{"ActionName": {"id": 42}}`
Examples: `CloseWindow`, `FullscreenWindow`, `ToggleWindowFloating`, `ResetWindowHeight`, `CenterWindow`

### Family: SizeChangeWithOptId — 2 variants
Fields: `id: Option<u64>`, `change: SizeChange`
Wire format: `{"SetWindowWidth": {"id": null, "change": {"SetFixed": 800}}}`
Examples: `SetWindowWidth`, `SetWindowHeight`

### Family: WorkspaceRef — 2 variants (FocusWorkspace, MoveColumnToWorkspace-like)
Fields: `reference: WorkspaceReferenceArg` (possibly + `focus: bool`, `window_id: Option<u64>`)
These need separate case branches because their field sets differ.

### Family: FocusBool — 4 variants
Fields: `focus: bool`
Wire format: `{"MoveWindowToWorkspaceDown": {"focus": true}}`
Examples: `MoveWindowToWorkspaceDown`, `MoveWindowToWorkspaceUp`, `MoveColumnToWorkspaceDown`, `MoveColumnToWorkspaceUp`

### Family: OutputName — 3 variants (FocusMonitor, MoveColumnToMonitor, MoveWorkspaceToMonitor)
Fields: `output: string`

### Family: RequiredWindowId — 4 variants
Fields: `id: u64` (NOT optional)
Examples: `FocusWindow`, `ToggleWindowUrgent`, `SetWindowUrgent`, `UnsetWindowUrgent`

### Family: PositionChange (floating move) — 1 variant
Fields: `id: Option<u64>`, `x: PositionChange`, `y: PositionChange`

### Family: Unique / complex — remaining variants with unique field shapes
`Quit`, `Spawn`, `SpawnSh`, `Screenshot`, `ScreenshotScreen`, `ScreenshotWindow`, `SwitchLayout`, `SetColumnDisplay`, `SetColumnWidth`, `MoveWindowToWorkspace`, `MoveColumnToWorkspace`, `FocusWorkspace`, `MoveWorkspaceToIndex`, `SetWorkspaceName`, `UnsetWorkspaceName`, `MoveWindowToMonitor`, `MoveWorkspaceToMonitor`, `DoScreenTransition`, `LoadConfigFile`, `FocusWindowInColumn`, `FocusColumn`, `MoveColumnToIndex`, `SetDynamicCastMonitor`, `StopCast`

---

## Step-by-Step Implementation Plan

### Step 0: Verify current tests pass
```bash
devenv shell -- env NIMBLE_DIR=/tmp/nimble nimble test
```
If anything fails, fix it before proceeding. Commit the fix.

### Step 1: Fix wire format bugs in `actions.nim` + `test_actions.nim`

This step fixes the 7 wire format bugs documented above. Do this as an isolated commit.

**1a.** In `actions.nim`, change the `else` branch of `toJson`:
```nim
else:
  encodeStructVariant(ActionWireNames[a.kind], newJObject())
```

**1b.** Fix Spawn encoding:
```nim
of naSpawn:
  encodeStructVariant("Spawn", %*{"command": %a.args})
```

**1c.** Fix SpawnSh encoding:
```nim
of naSpawnSh:
  encodeStructVariant("SpawnSh", %*{"command": %a.command})
```

**1d.** Fix SetColumnDisplay encoding:
```nim
of naSetColumnDisplay:
  let d = if a.columnDisplay == cdTabbed: "Tabbed" else: "Normal"
  encodeStructVariant("SetColumnDisplay", %*{"display": d})
```

**1e.** Fix SwitchLayout encoding:
```nim
of naSwitchLayout:
  encodeStructVariant("SwitchLayout", %*{"layout": toJson(a.layoutTarget)})
```

**1f.** Make `naQuit` parameterized — add `skipConfirmation: bool` field. Update wire encoding:
```nim
of naQuit:
  encodeStructVariant("Quit", %*{"skip_confirmation": a.skipConfirmation})
```
Update constructor: `proc quit*(skipConfirmation: bool = false): NiriAction`

**1g.** Make `naScreenshot` parameterized — add `showPointer: bool`, `screenshotPath: Option[string]`. Wire encoding:
```nim
of naScreenshot:
  encodeStructVariant("Screenshot", %*{
    "show_pointer": a.showPointer,
    "path": (if a.screenshotPath.isSome: %a.screenshotPath.get() else: newJNull())
  })
```
Update constructor: `proc screenshot*(showPointer: bool = false, path: Option[string] = none(string)): NiriAction`

**1h.** Update ALL test expectations in `test_actions.nim`:
```nim
# Unit-like actions now encode as empty struct variants
check toJson(focusWindowDown()) == parseJson("""{"FocusWindowDown":{}}""")
check toJson(toggleOverview()) == parseJson("""{"ToggleOverview":{}}""")

# Quit is parameterized
check toJson(actions.quit()) == parseJson("""{"Quit":{"skip_confirmation":false}}""")

# Spawn wraps in command field
check toJson(spawn(@["alacritty"])) == parseJson("""{"Spawn":{"command":["alacritty"]}}""")

# SpawnSh wraps in command field
check toJson(spawnSh("echo hello")) == parseJson("""{"SpawnSh":{"command":"echo hello"}}""")

# Action request wrapping
check toJson(requestAction(actions.quit())) == parseJson("""{"Action":{"Quit":{"skip_confirmation":false}}}""")
```

**1i.** Run tests. Fix until green.
```bash
devenv shell -- env NIMBLE_DIR=/tmp/nimble nimble test
```

**Commit**: `fix: correct wire format to match Niri serde externally-tagged struct variants`

---

### Step 2: Expand `NiriActionKind` enum to full 141 variants

Open `actions.nim` and replace the `NiriActionKind` enum with all 141 variants. Group by category for readability. Use the `na` prefix convention.

Naming convention — translate PascalCase wire names to `na` + PascalCase:
- `FocusWindowDown` → `naFocusWindowDown`
- `MoveWindowToWorkspace` → `naMoveWindowToWorkspace`
- `ToggleDebugTint` → `naToggleDebugTint`

List them in the same order as the inventory above.

**Commit**: `feat: expand NiriActionKind to full protocol scope (141 variants)`

---

### Step 3: Expand `ActionWireNames` to full 141 entries

The `ActionWireNames` array must have exactly one entry per enum variant, in declaration order. Copy the wire names from the inventory.

Add a compile-time assertion after the array:
```nim
static:
  assert ActionWireNames.len == ord(high(NiriActionKind)) + 1,
    "ActionWireNames must cover every NiriActionKind variant"
```

This assertion already works implicitly (array size = enum cardinality), but make it explicit for documentation.

**Commit**: `feat: complete ActionWireNames for all 141 variants`

---

### Step 4: Expand `NiriAction` object case branches

Design case branches to group variants by field family. This is the most architecture-sensitive step.

Here is the recommended grouping:

```nim
NiriAction* = object
  case kind*: NiriActionKind
  # --- Empty (no fields) ---
  of naFocusWindowDown, naFocusWindowUp, naFocusWindowTop, naFocusWindowBottom,
     naFocusWindowDownOrTop, naFocusWindowUpOrBottom,
     naFocusWindowDownOrColumnLeft, naFocusWindowDownOrColumnRight,
     naFocusWindowUpOrColumnLeft, naFocusWindowUpOrColumnRight,
     naFocusWindowOrMonitorUp, naFocusWindowOrMonitorDown,
     naFocusWindowOrWorkspaceDown, naFocusWindowOrWorkspaceUp,
     naFocusWindowPrevious,
     naFocusColumnLeft, naFocusColumnRight,
     naFocusColumnFirst, naFocusColumnLast,
     naFocusColumnRightOrFirst, naFocusColumnLeftOrLast,
     naFocusColumnOrMonitorLeft, naFocusColumnOrMonitorRight,
     naMoveWindowDown, naMoveWindowUp,
     naMoveWindowDownOrToWorkspaceDown, naMoveWindowUpOrToWorkspaceUp,
     naConsumeWindowIntoColumn, naExpelWindowFromColumn,
     naSwapWindowRight, naSwapWindowLeft,
     naMoveColumnLeft, naMoveColumnRight,
     naMoveColumnToFirst, naMoveColumnToLast,
     naMoveColumnLeftOrToMonitorLeft, naMoveColumnRightOrToMonitorRight,
     naToggleColumnTabbedDisplay, naCenterColumn, naCenterVisibleColumns,
     naMaximizeColumn, naExpandColumnToAvailableWidth,
     naSwitchPresetColumnWidth, naSwitchPresetColumnWidthBack,
     naFocusWorkspaceDown, naFocusWorkspaceUp, naFocusWorkspacePrevious,
     naMoveWorkspaceDown, naMoveWorkspaceUp,
     naFocusMonitorLeft, naFocusMonitorRight,
     naFocusMonitorDown, naFocusMonitorUp,
     naFocusMonitorPrevious, naFocusMonitorNext,
     naMoveWindowToMonitorLeft, naMoveWindowToMonitorRight,
     naMoveWindowToMonitorDown, naMoveWindowToMonitorUp,
     naMoveWindowToMonitorPrevious, naMoveWindowToMonitorNext,
     naMoveColumnToMonitorLeft, naMoveColumnToMonitorRight,
     naMoveColumnToMonitorDown, naMoveColumnToMonitorUp,
     naMoveColumnToMonitorPrevious, naMoveColumnToMonitorNext,
     naMoveWorkspaceToMonitorLeft, naMoveWorkspaceToMonitorRight,
     naMoveWorkspaceToMonitorDown, naMoveWorkspaceToMonitorUp,
     naMoveWorkspaceToMonitorPrevious, naMoveWorkspaceToMonitorNext,
     naFocusFloating, naFocusTiling,
     naSwitchFocusBetweenFloatingAndTiling,
     naClearDynamicCastTarget,
     naToggleOverview, naOpenOverview, naCloseOverview,
     naToggleDebugTint, naDebugToggleOpaqueRegions, naDebugToggleDamage,
     naPowerOffMonitors, naPowerOnMonitors,
     naShowHotkeyOverlay, naToggleKeyboardShortcutsInhibit:
    discard

  # --- Optional window ID ---
  of naCloseWindow, naFullscreenWindow, naToggleWindowedFullscreen,
     naConsumeOrExpelWindowLeft, naConsumeOrExpelWindowRight,
     naCenterWindow,
     naResetWindowHeight,
     naSwitchPresetWindowWidth, naSwitchPresetWindowWidthBack,
     naSwitchPresetWindowHeight, naSwitchPresetWindowHeightBack,
     naMaximizeWindowToEdges,
     naToggleWindowFloating, naMoveWindowToFloating, naMoveWindowToTiling,
     naToggleWindowRuleOpacity,
     naSetDynamicCastWindow:
    windowId*: Option[WindowId]

  # --- Required window ID (u64, not optional) ---
  of naFocusWindow, naToggleWindowUrgent, naSetWindowUrgent, naUnsetWindowUrgent:
    reqWindowId*: WindowId

  # --- Size change + optional window ID ---
  of naSetWindowWidth, naSetWindowHeight:
    sizeWindowId*: Option[WindowId]
    sizeChange*: SizeChange

  # --- Column width change ---
  of naSetColumnWidth:
    colWidthChange*: SizeChange

  # --- Spawn ---
  of naSpawn:
    spawnCommand*: seq[string]

  # --- SpawnSh ---
  of naSpawnSh:
    shCommand*: string

  # --- Quit ---
  of naQuit:
    skipConfirmation*: bool

  # --- Screenshot ---
  of naScreenshot:
    ssShowPointer*: bool
    ssPath*: Option[string]

  # --- ScreenshotScreen ---
  of naScreenshotScreen:
    sssWriteToDisk*: bool
    sssShowPointer*: bool
    sssPath*: Option[string]

  # --- ScreenshotWindow ---
  of naScreenshotWindow:
    sswId*: Option[WindowId]
    sswWriteToDisk*: bool
    sswShowPointer*: bool
    sswPath*: Option[string]

  # --- DoScreenTransition ---
  of naDoScreenTransition:
    transitionDelayMs*: Option[uint16]

  # --- LoadConfigFile ---
  of naLoadConfigFile:
    configPath*: Option[string]

  # --- Workspace ref ---
  of naFocusWorkspace:
    focusWsRef*: WorkspaceRef

  # --- Move window to workspace (complex) ---
  of naMoveWindowToWorkspace:
    mwtwWindowId*: Option[WindowId]
    mwtwRef*: WorkspaceRef
    mwtwFocus*: bool

  # --- Move column to workspace ---
  of naMoveColumnToWorkspace:
    mctwRef*: WorkspaceRef
    mctwFocus*: bool

  # --- Focus bool (workspace up/down moves) ---
  of naMoveWindowToWorkspaceDown, naMoveWindowToWorkspaceUp,
     naMoveColumnToWorkspaceDown, naMoveColumnToWorkspaceUp:
    moveFocus*: bool

  # --- MoveWorkspaceToIndex ---
  of naMoveWorkspaceToIndex:
    wsToIdx*: int
    wsToIdxRef*: Option[WorkspaceRef]

  # --- SetWorkspaceName ---
  of naSetWorkspaceName:
    wsNewName*: string
    wsNameRef*: Option[WorkspaceRef]

  # --- UnsetWorkspaceName ---
  of naUnsetWorkspaceName:
    unsetWsRef*: Option[WorkspaceRef]

  # --- Layout switch ---
  of naSwitchLayout:
    layoutTarget*: LayoutSwitchTarget

  # --- Column display ---
  of naSetColumnDisplay:
    columnDisplay*: ColumnDisplay

  # --- Index-based (FocusWindowInColumn, FocusColumn, MoveColumnToIndex) ---
  of naFocusWindowInColumn:
    focusWinIdx*: uint8

  of naFocusColumn:
    focusColIdx*: int

  of naMoveColumnToIndex:
    moveColIdx*: int

  # --- Output name (FocusMonitor, MoveColumnToMonitor) ---
  of naFocusMonitor, naMoveColumnToMonitor:
    outputName*: string

  # --- Move window to monitor (with optional id) ---
  of naMoveWindowToMonitor:
    mwtmId*: Option[WindowId]
    mwtmOutput*: string

  # --- Move workspace to monitor (with optional ref) ---
  of naMoveWorkspaceToMonitor:
    mwstmOutput*: string
    mwstmRef*: Option[WorkspaceRef]

  # --- Floating window move ---
  of naMoveFloatingWindow:
    floatWindowId*: Option[WindowId]
    xChange*: PositionChange
    yChange*: PositionChange

  # --- Dynamic cast monitor ---
  of naSetDynamicCastMonitor:
    castOutput*: Option[string]

  # --- StopCast ---
  of naStopCast:
    castSessionId*: uint64
```

**Important Nim constraint**: Every enum variant must appear in exactly one `of` branch. No variant can be left unhandled. The compiler enforces this.

**Note on field naming**: Nim case objects require unique field names across all branches (when they could be ambiguous). Use prefixed names where needed (`ssShowPointer`, `sssShowPointer`, etc.) but prefer clean names when there's no collision.

**Commit**: `feat: expand NiriAction case object to full protocol field layout`

---

### Step 5: Add constructor procs for all 141 variants

Follow the existing pattern. Every variant gets one exported constructor.

Rules:
- Empty variants: zero-arg proc returning `NiriAction(kind: naXxx)`
- Optional window ID: one arg with `= none(WindowId)` default
- Required window ID: one arg, no default
- Complex variants: all fields as params, sensible defaults where protocol allows

Name constructors using camelCase of the wire name:
- `FocusWindowDown` → `proc focusWindowDown*(): NiriAction`
- `MoveWindowToWorkspace` → `proc moveWindowToWorkspace*(ref: WorkspaceRef, focus: bool = false, windowId: Option[WindowId] = none(WindowId)): NiriAction`

Group constructors by category, matching the inventory order.

Example constructors for new variants:
```nim
# Window focus
proc focusWindowTop*(): NiriAction = NiriAction(kind: naFocusWindowTop)
proc focusWindowBottom*(): NiriAction = NiriAction(kind: naFocusWindowBottom)
proc focusWindow*(id: WindowId): NiriAction = NiriAction(kind: naFocusWindow, reqWindowId: id)
proc focusWindowInColumn*(index: uint8): NiriAction = NiriAction(kind: naFocusWindowInColumn, focusWinIdx: index)

# Workspace
proc moveWindowToWorkspaceDown*(focus: bool = false): NiriAction = NiriAction(kind: naMoveWindowToWorkspaceDown, moveFocus: focus)
proc moveWindowToWorkspace*(refv: WorkspaceRef, focus: bool = false, windowId: Option[WindowId] = none(WindowId)): NiriAction =
  NiriAction(kind: naMoveWindowToWorkspace, mwtwRef: refv, mwtwFocus: focus, mwtwWindowId: windowId)

# Monitor
proc focusMonitor*(output: string): NiriAction = NiriAction(kind: naFocusMonitor, outputName: output)

# Screenshot
proc screenshot*(showPointer: bool = false, path: Option[string] = none(string)): NiriAction =
  NiriAction(kind: naScreenshot, ssShowPointer: showPointer, ssPath: path)
proc screenshotWindow*(id: Option[WindowId] = none(WindowId), writeToDisk: bool = true, showPointer: bool = false, path: Option[string] = none(string)): NiriAction =
  NiriAction(kind: naScreenshotWindow, sswId: id, sswWriteToDisk: writeToDisk, sswShowPointer: showPointer, sswPath: path)
```

**Commit**: `feat: add constructor procs for all 141 action variants`

---

### Step 6: Complete `toJson` for all variants

Expand the `toJson*(a: NiriAction): JsonNode` case statement to cover every variant. Use helper procs to avoid a giant monolith.

#### Helper procs to add (private, not exported):

```nim
proc encodeEmptyAction(kind: NiriActionKind): JsonNode =
  encodeStructVariant(ActionWireNames[kind], newJObject())

proc encodeOptionalId(id: Option[WindowId]): JsonNode =
  if id.isSome: toJson(id.get()) else: newJNull()

proc encodeWindowIdAction(kind: NiriActionKind, id: Option[WindowId]): JsonNode =
  encodeStructVariant(ActionWireNames[kind], %*{"id": encodeOptionalId(id)})

proc encodeReqWindowIdAction(kind: NiriActionKind, id: WindowId): JsonNode =
  encodeStructVariant(ActionWireNames[kind], %*{"id": toJson(id)})
```

#### toJson structure:

```nim
proc toJson*(a: NiriAction): JsonNode =
  case a.kind
  # Empty actions
  of naFocusWindowDown, naFocusWindowUp, ...(all empty variants):
    encodeEmptyAction(a.kind)

  # Optional window ID actions
  of naCloseWindow, naFullscreenWindow, ...(all optional-id variants):
    encodeWindowIdAction(a.kind, a.windowId)

  # Required window ID actions
  of naFocusWindow, naToggleWindowUrgent, naSetWindowUrgent, naUnsetWindowUrgent:
    encodeReqWindowIdAction(a.kind, a.reqWindowId)

  # Size change + optional window ID
  of naSetWindowWidth, naSetWindowHeight:
    encodeStructVariant(ActionWireNames[a.kind], %*{
      "id": encodeOptionalId(a.sizeWindowId),
      "change": toJson(a.sizeChange)
    })

  of naSetColumnWidth:
    encodeStructVariant("SetColumnWidth", %*{"change": toJson(a.colWidthChange)})

  of naQuit:
    encodeStructVariant("Quit", %*{"skip_confirmation": a.skipConfirmation})

  of naSpawn:
    encodeStructVariant("Spawn", %*{"command": %a.spawnCommand})

  of naSpawnSh:
    encodeStructVariant("SpawnSh", %*{"command": %a.shCommand})

  of naScreenshot:
    encodeStructVariant("Screenshot", %*{
      "show_pointer": a.ssShowPointer,
      "path": (if a.ssPath.isSome: %a.ssPath.get() else: newJNull())
    })

  # ... and so on for each unique branch

  of naFocusWorkspace:
    encodeStructVariant("FocusWorkspace", %*{"reference": toJson(a.focusWsRef)})

  of naMoveWindowToWorkspace:
    encodeStructVariant("MoveWindowToWorkspace", %*{
      "window_id": encodeOptionalId(a.mwtwWindowId),
      "reference": toJson(a.mwtwRef),
      "focus": a.mwtwFocus
    })

  of naMoveWindowToWorkspaceDown, naMoveWindowToWorkspaceUp,
     naMoveColumnToWorkspaceDown, naMoveColumnToWorkspaceUp:
    encodeStructVariant(ActionWireNames[a.kind], %*{"focus": a.moveFocus})

  of naSwitchLayout:
    encodeStructVariant("SwitchLayout", %*{"layout": toJson(a.layoutTarget)})

  of naSetColumnDisplay:
    let d = if a.columnDisplay == cdTabbed: "Tabbed" else: "Normal"
    encodeStructVariant("SetColumnDisplay", %*{"display": d})

  of naFocusMonitor, naMoveColumnToMonitor:
    encodeStructVariant(ActionWireNames[a.kind], %*{"output": a.outputName})

  of naMoveFloatingWindow:
    encodeStructVariant("MoveFloatingWindow", %*{
      "id": encodeOptionalId(a.floatWindowId),
      "x": toJson(a.xChange),
      "y": toJson(a.yChange)
    })

  # ... complete for all remaining branches
```

**Critical**: The `case` must be exhaustive. The Nim compiler will error if any variant is missing. This is your safety net.

**Commit**: `feat: complete toJson encoding for all 141 action variants`

---

### Step 7: Exhaustive tests in `test_actions.nim`

Replace the existing tests with a comprehensive suite. Structure:

#### 7a. Completeness guard test

```nim
test "every NiriActionKind has a wire name mapping":
  for kind in NiriActionKind:
    check ActionWireNames[kind].len > 0

test "wire name count equals enum count":
  check ActionWireNames.len == ord(high(NiriActionKind)) + 1
```

#### 7b. Table-driven encoding tests

Create a table of `(constructor call, expected JSON string)` pairs and iterate:

```nim
const unitActionTests = [
  (focusWindowDown(), """{"FocusWindowDown":{}}"""),
  (focusWindowUp(), """{"FocusWindowUp":{}}"""),
  (focusColumnLeft(), """{"FocusColumnLeft":{}}"""),
  # ... all ~75 empty actions
  (toggleDebugTint(), """{"ToggleDebugTint":{}}"""),
]

test "empty actions encode as struct variant with empty object":
  for (action, expected) in unitActionTests:
    check toJson(action) == parseJson(expected)
```

#### 7c. Parameterized action tests

Test each parameterized action family:

```nim
test "optional window id actions":
  check toJson(closeWindow()) == parseJson("""{"CloseWindow":{"id":null}}""")
  check toJson(closeWindow(some(WindowId(42)))) == parseJson("""{"CloseWindow":{"id":42}}""")
  check toJson(toggleWindowFloating(some(WindowId(5)))) == parseJson("""{"ToggleWindowFloating":{"id":5}}""")

test "required window id actions":
  check toJson(focusWindow(WindowId(1))) == parseJson("""{"FocusWindow":{"id":1}}""")
  check toJson(toggleWindowUrgent(WindowId(3))) == parseJson("""{"ToggleWindowUrgent":{"id":3}}""")

test "quit with skip_confirmation":
  check toJson(actions.quit()) == parseJson("""{"Quit":{"skip_confirmation":false}}""")
  check toJson(actions.quit(skipConfirmation = true)) == parseJson("""{"Quit":{"skip_confirmation":true}}""")

test "spawn actions":
  check toJson(spawn(@["ls", "-la"])) == parseJson("""{"Spawn":{"command":["ls","-la"]}}""")
  check toJson(spawnSh("echo hi")) == parseJson("""{"SpawnSh":{"command":"echo hi"}}""")

test "screenshot actions":
  check toJson(screenshot()) == parseJson("""{"Screenshot":{"show_pointer":false,"path":null}}""")
  check toJson(screenshot(showPointer = true)) == parseJson("""{"Screenshot":{"show_pointer":true,"path":null}}""")
  check toJson(screenshotWindow(some(WindowId(1)), writeToDisk = false)) ==
    parseJson("""{"ScreenshotWindow":{"id":1,"write_to_disk":false,"show_pointer":false,"path":null}}""")

test "workspace actions":
  check toJson(focusWorkspace(WorkspaceRef(kind: wrkByIndex, idx: WorkspaceIdx(2)))) ==
    parseJson("""{"FocusWorkspace":{"reference":{"Index":2}}}""")
  check toJson(moveWindowToWorkspaceDown(focus = true)) ==
    parseJson("""{"MoveWindowToWorkspaceDown":{"focus":true}}""")

test "monitor actions":
  check toJson(focusMonitor("HDMI-A-1")) == parseJson("""{"FocusMonitor":{"output":"HDMI-A-1"}}""")
  check toJson(focusMonitorLeft()) == parseJson("""{"FocusMonitorLeft":{}}""")

test "layout and display":
  check toJson(switchLayout(LayoutSwitchTarget(kind: lstNext))) ==
    parseJson("""{"SwitchLayout":{"layout":"Next"}}""")
  check toJson(setColumnDisplay(cdTabbed)) ==
    parseJson("""{"SetColumnDisplay":{"display":"Tabbed"}}""")

test "size change actions":
  check toJson(setWindowWidth(SizeChange(kind: sckSetFixed, fixedVal: 800))) ==
    parseJson("""{"SetWindowWidth":{"id":null,"change":{"SetFixed":800}}}""")
  check toJson(setColumnWidth(SizeChange(kind: sckAdjustProportion, adjPropVal: 0.1))) ==
    parseJson("""{"SetColumnWidth":{"change":{"AdjustProportion":0.1}}}""")

test "floating window actions":
  let x = PositionChange(kind: pckAdjustFixed, adjFixedVal: 10.0)
  let y = PositionChange(kind: pckAdjustFixed, adjFixedVal: -5.0)
  check toJson(moveFloatingWindow(x, y)) ==
    parseJson("""{"MoveFloatingWindow":{"id":null,"x":{"AdjustFixed":10.0},"y":{"AdjustFixed":-5.0}}}""")

test "cast actions":
  check toJson(stopCast(42'u64)) == parseJson("""{"StopCast":{"session_id":42}}""")
  check toJson(setDynamicCastMonitor(some("eDP-1"))) ==
    parseJson("""{"SetDynamicCastMonitor":{"output":"eDP-1"}}""")
```

#### 7d. Request wrapping tests

```nim
test "action request wrapping produces correct nesting":
  check toJson(requestAction(focusWindowDown())) ==
    parseJson("""{"Action":{"FocusWindowDown":{}}}""")
  check toJson(requestAction(actions.quit(true))) ==
    parseJson("""{"Action":{"Quit":{"skip_confirmation":true}}}""")
  check toJson(requestAction(spawn(@["ls"]))) ==
    parseJson("""{"Action":{"Spawn":{"command":["ls"]}}}""")
```

**Commit**: `test: exhaustive action encoding tests with completeness guards`

---

### Step 8: Update `test_requests.nim` if needed

Check that the request-action nesting tests in `test_requests.nim` still pass with the new wire format. Add coverage for a few new action families (screenshot, cast, monitor, workspace with focus bool).

**Commit**: `test: expand request integration tests for new action families`

---

### Step 9: Final verification

Run the full test suite:
```bash
devenv shell -- env NIMBLE_DIR=/tmp/nimble nimble test
```

Also verify the library compiles cleanly:
```bash
devenv shell -- env NIMBLE_DIR=/tmp/nimble nim c --hints:off src/nimri_ipc/nimri_ipc.nim
```

---

## Commit Sequence Summary

| # | Scope | Description |
|---|-------|-------------|
| 1 | fix | Correct wire format bugs (empty struct variants, field wrapping) |
| 2 | feat | Expand NiriActionKind enum to 141 variants |
| 3 | feat | Complete ActionWireNames array + static assertion |
| 4 | feat | Expand NiriAction case object with all field branches |
| 5 | feat | Add constructor procs for all 141 variants |
| 6 | feat | Complete toJson encoding for all variants |
| 7 | test | Exhaustive encoding tests + completeness guards |
| 8 | test | Request integration test expansion |

Steps 2-6 can be combined into fewer commits if you prefer, but the wire format fix (step 1) should always be a separate commit.

---

## Verification Checklist

Before declaring done, all must be true:

- [ ] `NiriActionKind` has exactly 141 variants
- [ ] `ActionWireNames` has exactly 141 entries, all matching protocol wire names
- [ ] Every variant has exactly one exported constructor proc
- [ ] `toJson` handles every variant (compiler-verified exhaustive case)
- [ ] Empty actions encode as `{"Name": {}}` (NOT `"Name"`)
- [ ] All struct variant payloads wrap fields in a JSON object with correct field names
- [ ] `nimble test` passes with zero failures
- [ ] `nim c --hints:off src/nimri_ipc/nimri_ipc.nim` compiles cleanly
- [ ] No imports of transport/I/O in `actions.nim`
- [ ] No reverse coupling from `actions.nim` to `requests.nim`

---

## Reference

- Niri IPC source: `https://github.com/YaLTeR/niri/blob/main/niri-ipc/src/lib.rs`
- API docs: `https://docs.rs/niri-ipc/latest/niri_ipc/enum.Action.html`
- Serde externally-tagged format: struct variant `Foo { x: i32 }` → `{"Foo": {"x": 42}}`, empty struct `Bar {}` → `{"Bar": {}}`
