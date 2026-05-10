## nimri_ipc/actions - Niri actions and JSON encoding

import std/[json, options]
import ./[codec, models]

type
  NiriActionKind* = enum
    naQuit, naPowerOffMonitors, naPowerOnMonitors, naSpawn, naSpawnSh,
    naDoScreenTransition, naLoadConfigFile, naShowHotkeyOverlay, naToggleKeyboardShortcutsInhibit,
    naScreenshot, naScreenshotScreen, naScreenshotWindow,
    naCloseWindow, naFullscreenWindow, naToggleWindowedFullscreen, naFocusWindow, naFocusWindowInColumn,
    naFocusWindowPrevious, naFocusWindowDown, naFocusWindowUp, naFocusWindowTop, naFocusWindowBottom,
    naFocusWindowDownOrTop, naFocusWindowUpOrBottom, naFocusWindowDownOrColumnLeft, naFocusWindowDownOrColumnRight,
    naFocusWindowUpOrColumnLeft, naFocusWindowUpOrColumnRight, naFocusWindowOrMonitorUp, naFocusWindowOrMonitorDown,
    naFocusWindowOrWorkspaceDown, naFocusWindowOrWorkspaceUp,
    naFocusColumnLeft, naFocusColumnRight, naFocusColumnFirst, naFocusColumnLast, naFocusColumnRightOrFirst,
    naFocusColumnLeftOrLast, naFocusColumn, naFocusColumnOrMonitorLeft, naFocusColumnOrMonitorRight,
    naMoveWindowDown, naMoveWindowUp, naMoveWindowDownOrToWorkspaceDown, naMoveWindowUpOrToWorkspaceUp,
    naConsumeOrExpelWindowLeft, naConsumeOrExpelWindowRight, naConsumeWindowIntoColumn, naExpelWindowFromColumn,
    naSwapWindowRight, naSwapWindowLeft,
    naMoveColumnLeft, naMoveColumnRight, naMoveColumnToFirst, naMoveColumnToLast, naMoveColumnLeftOrToMonitorLeft,
    naMoveColumnRightOrToMonitorRight, naMoveColumnToIndex, naToggleColumnTabbedDisplay, naSetColumnDisplay,
    naCenterColumn, naCenterWindow, naCenterVisibleColumns, naMaximizeColumn, naSetColumnWidth,
    naExpandColumnToAvailableWidth, naSwitchPresetColumnWidth, naSwitchPresetColumnWidthBack,
    naSetWindowWidth, naSetWindowHeight, naResetWindowHeight, naSwitchPresetWindowWidth, naSwitchPresetWindowWidthBack,
    naSwitchPresetWindowHeight, naSwitchPresetWindowHeightBack, naMaximizeWindowToEdges,
    naSwitchLayout,
    naFocusWorkspaceDown, naFocusWorkspaceUp, naFocusWorkspace, naFocusWorkspacePrevious,
    naMoveWindowToWorkspaceDown, naMoveWindowToWorkspaceUp, naMoveWindowToWorkspace,
    naMoveColumnToWorkspaceDown, naMoveColumnToWorkspaceUp, naMoveColumnToWorkspace,
    naMoveWorkspaceDown, naMoveWorkspaceUp, naMoveWorkspaceToIndex, naSetWorkspaceName, naUnsetWorkspaceName,
    naFocusMonitorLeft, naFocusMonitorRight, naFocusMonitorDown, naFocusMonitorUp, naFocusMonitorPrevious,
    naFocusMonitorNext, naFocusMonitor,
    naMoveWindowToMonitorLeft, naMoveWindowToMonitorRight, naMoveWindowToMonitorDown, naMoveWindowToMonitorUp,
    naMoveWindowToMonitorPrevious, naMoveWindowToMonitorNext, naMoveWindowToMonitor,
    naMoveColumnToMonitorLeft, naMoveColumnToMonitorRight, naMoveColumnToMonitorDown, naMoveColumnToMonitorUp,
    naMoveColumnToMonitorPrevious, naMoveColumnToMonitorNext, naMoveColumnToMonitor,
    naMoveWorkspaceToMonitorLeft, naMoveWorkspaceToMonitorRight, naMoveWorkspaceToMonitorDown, naMoveWorkspaceToMonitorUp,
    naMoveWorkspaceToMonitorPrevious, naMoveWorkspaceToMonitorNext, naMoveWorkspaceToMonitor,
    naToggleWindowFloating, naMoveWindowToFloating, naMoveWindowToTiling, naFocusFloating, naFocusTiling,
    naSwitchFocusBetweenFloatingAndTiling, naMoveFloatingWindow,
    naToggleWindowRuleOpacity,
    naSetDynamicCastWindow, naSetDynamicCastMonitor, naClearDynamicCastTarget, naStopCast,
    naToggleOverview, naOpenOverview, naCloseOverview,
    naToggleWindowUrgent, naSetWindowUrgent, naUnsetWindowUrgent,
    naToggleDebugTint, naDebugToggleOpaqueRegions, naDebugToggleDamage

  NiriAction* = object
    case kind*: NiriActionKind
    of naCloseWindow, naFullscreenWindow:
      windowId*: Option[WindowId]
    of naSetWindowWidth, naSetWindowHeight:
      sizeWindowId*: Option[WindowId]
      sizeChange*: SizeChange
    of naSpawn:
      args*: seq[string]
    of naSpawnSh:
      command*: string
    of naQuit:
      skipConfirmation*: bool
    of naScreenshot:
      showPointer*: bool
      screenshotPath*: Option[string]
    of naFocusWorkspace, naMoveWindowToWorkspace:
      workspaceRef*: WorkspaceRef
    of naSwitchLayout:
      layoutTarget*: LayoutSwitchTarget
    of naSetColumnDisplay:
      columnDisplay*: ColumnDisplay
    of naMoveFloatingWindow:
      floatWindowId*: Option[WindowId]
      xChange*: PositionChange
      yChange*: PositionChange
    else: discard

const ActionWireNames*: array[NiriActionKind, string] = [
  "Quit", "PowerOffMonitors", "PowerOnMonitors", "Spawn", "SpawnSh",
  "DoScreenTransition", "LoadConfigFile", "ShowHotkeyOverlay", "ToggleKeyboardShortcutsInhibit",
  "Screenshot", "ScreenshotScreen", "ScreenshotWindow",
  "CloseWindow", "FullscreenWindow", "ToggleWindowedFullscreen", "FocusWindow", "FocusWindowInColumn",
  "FocusWindowPrevious", "FocusWindowDown", "FocusWindowUp", "FocusWindowTop", "FocusWindowBottom",
  "FocusWindowDownOrTop", "FocusWindowUpOrBottom", "FocusWindowDownOrColumnLeft", "FocusWindowDownOrColumnRight",
  "FocusWindowUpOrColumnLeft", "FocusWindowUpOrColumnRight", "FocusWindowOrMonitorUp", "FocusWindowOrMonitorDown",
  "FocusWindowOrWorkspaceDown", "FocusWindowOrWorkspaceUp",
  "FocusColumnLeft", "FocusColumnRight", "FocusColumnFirst", "FocusColumnLast", "FocusColumnRightOrFirst",
  "FocusColumnLeftOrLast", "FocusColumn", "FocusColumnOrMonitorLeft", "FocusColumnOrMonitorRight",
  "MoveWindowDown", "MoveWindowUp", "MoveWindowDownOrToWorkspaceDown", "MoveWindowUpOrToWorkspaceUp",
  "ConsumeOrExpelWindowLeft", "ConsumeOrExpelWindowRight", "ConsumeWindowIntoColumn", "ExpelWindowFromColumn",
  "SwapWindowRight", "SwapWindowLeft",
  "MoveColumnLeft", "MoveColumnRight", "MoveColumnToFirst", "MoveColumnToLast", "MoveColumnLeftOrToMonitorLeft",
  "MoveColumnRightOrToMonitorRight", "MoveColumnToIndex", "ToggleColumnTabbedDisplay", "SetColumnDisplay",
  "CenterColumn", "CenterWindow", "CenterVisibleColumns", "MaximizeColumn", "SetColumnWidth",
  "ExpandColumnToAvailableWidth", "SwitchPresetColumnWidth", "SwitchPresetColumnWidthBack",
  "SetWindowWidth", "SetWindowHeight", "ResetWindowHeight", "SwitchPresetWindowWidth", "SwitchPresetWindowWidthBack",
  "SwitchPresetWindowHeight", "SwitchPresetWindowHeightBack", "MaximizeWindowToEdges",
  "SwitchLayout",
  "FocusWorkspaceDown", "FocusWorkspaceUp", "FocusWorkspace", "FocusWorkspacePrevious",
  "MoveWindowToWorkspaceDown", "MoveWindowToWorkspaceUp", "MoveWindowToWorkspace",
  "MoveColumnToWorkspaceDown", "MoveColumnToWorkspaceUp", "MoveColumnToWorkspace",
  "MoveWorkspaceDown", "MoveWorkspaceUp", "MoveWorkspaceToIndex", "SetWorkspaceName", "UnsetWorkspaceName",
  "FocusMonitorLeft", "FocusMonitorRight", "FocusMonitorDown", "FocusMonitorUp", "FocusMonitorPrevious",
  "FocusMonitorNext", "FocusMonitor",
  "MoveWindowToMonitorLeft", "MoveWindowToMonitorRight", "MoveWindowToMonitorDown", "MoveWindowToMonitorUp",
  "MoveWindowToMonitorPrevious", "MoveWindowToMonitorNext", "MoveWindowToMonitor",
  "MoveColumnToMonitorLeft", "MoveColumnToMonitorRight", "MoveColumnToMonitorDown", "MoveColumnToMonitorUp",
  "MoveColumnToMonitorPrevious", "MoveColumnToMonitorNext", "MoveColumnToMonitor",
  "MoveWorkspaceToMonitorLeft", "MoveWorkspaceToMonitorRight", "MoveWorkspaceToMonitorDown", "MoveWorkspaceToMonitorUp",
  "MoveWorkspaceToMonitorPrevious", "MoveWorkspaceToMonitorNext", "MoveWorkspaceToMonitor",
  "ToggleWindowFloating", "MoveWindowToFloating", "MoveWindowToTiling", "FocusFloating", "FocusTiling",
  "SwitchFocusBetweenFloatingAndTiling", "MoveFloatingWindow",
  "ToggleWindowRuleOpacity",
  "SetDynamicCastWindow", "SetDynamicCastMonitor", "ClearDynamicCastTarget", "StopCast",
  "ToggleOverview", "OpenOverview", "CloseOverview",
  "ToggleWindowUrgent", "SetWindowUrgent", "UnsetWindowUrgent",
  "ToggleDebugTint", "DebugToggleOpaqueRegions", "DebugToggleDamage"
]

static:
  assert ActionWireNames.len == ord(high(NiriActionKind)) + 1,
    "ActionWireNames must cover every NiriActionKind variant"

proc focusWindowDown*(): NiriAction = NiriAction(kind: naFocusWindowDown)
proc focusWindowUp*(): NiriAction = NiriAction(kind: naFocusWindowUp)
proc focusColumnLeft*(): NiriAction = NiriAction(kind: naFocusColumnLeft)
proc focusColumnRight*(): NiriAction = NiriAction(kind: naFocusColumnRight)
proc moveWindowDown*(): NiriAction = NiriAction(kind: naMoveWindowDown)
proc moveWindowUp*(): NiriAction = NiriAction(kind: naMoveWindowUp)
proc moveColumnLeft*(): NiriAction = NiriAction(kind: naMoveColumnLeft)
proc moveColumnRight*(): NiriAction = NiriAction(kind: naMoveColumnRight)
proc quit*(skipConfirmation: bool = false): NiriAction = NiriAction(kind: naQuit, skipConfirmation: skipConfirmation)
proc toggleOverview*(): NiriAction = NiriAction(kind: naToggleOverview)
proc screenshot*(showPointer: bool = false, path: Option[string] = none(string)): NiriAction =
  NiriAction(kind: naScreenshot, showPointer: showPointer, screenshotPath: path)
proc powerOffMonitors*(): NiriAction = NiriAction(kind: naPowerOffMonitors)

proc closeWindow*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naCloseWindow, windowId: id)
proc fullscreenWindow*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naFullscreenWindow, windowId: id)
proc setWindowWidth*(change: SizeChange, id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naSetWindowWidth, sizeWindowId: id, sizeChange: change)
proc setWindowHeight*(change: SizeChange, id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naSetWindowHeight, sizeWindowId: id, sizeChange: change)
proc spawn*(args: seq[string]): NiriAction = NiriAction(kind: naSpawn, args: args)
proc spawnSh*(command: string): NiriAction = NiriAction(kind: naSpawnSh, command: command)
proc focusWorkspace*(refv: WorkspaceRef): NiriAction = NiriAction(kind: naFocusWorkspace, workspaceRef: refv)
proc moveWindowToWorkspace*(refv: WorkspaceRef): NiriAction = NiriAction(kind: naMoveWindowToWorkspace, workspaceRef: refv)
proc switchLayout*(target: LayoutSwitchTarget): NiriAction = NiriAction(kind: naSwitchLayout, layoutTarget: target)
proc setColumnDisplay*(display: ColumnDisplay): NiriAction = NiriAction(kind: naSetColumnDisplay, columnDisplay: display)
proc moveFloatingWindow*(x, y: PositionChange, id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naMoveFloatingWindow, floatWindowId: id, xChange: x, yChange: y)

proc toJson*(a: NiriAction): JsonNode =
  case a.kind
  of naCloseWindow, naFullscreenWindow:
    let p = %*{"id": (if a.windowId.isSome: toJson(a.windowId.get()) else: newJNull())}
    encodeStructVariant(ActionWireNames[a.kind], p)
  of naSetWindowWidth, naSetWindowHeight:
    let p = %*{
      "id": (if a.sizeWindowId.isSome: toJson(a.sizeWindowId.get()) else: newJNull()),
      "change": toJson(a.sizeChange)
    }
    encodeStructVariant(ActionWireNames[a.kind], p)
  of naSpawn:
    encodeStructVariant("Spawn", %*{"command": %a.args})
  of naSpawnSh:
    encodeStructVariant("SpawnSh", %*{"command": %a.command})
  of naQuit:
    encodeStructVariant("Quit", %*{"skip_confirmation": a.skipConfirmation})
  of naScreenshot:
    encodeStructVariant("Screenshot", %*{
      "show_pointer": a.showPointer,
      "path": (if a.screenshotPath.isSome: %a.screenshotPath.get() else: newJNull())
    })
  of naFocusWorkspace, naMoveWindowToWorkspace:
    encodeStructVariant(ActionWireNames[a.kind], %*{"reference": toJson(a.workspaceRef)})
  of naSwitchLayout:
    encodeStructVariant("SwitchLayout", %*{"layout": toJson(a.layoutTarget)})
  of naSetColumnDisplay:
    let d = if a.columnDisplay == cdTabbed: "Tabbed" else: "Normal"
    encodeStructVariant("SetColumnDisplay", %*{"display": d})
  of naMoveFloatingWindow:
    let p = %*{
      "id": (if a.floatWindowId.isSome: toJson(a.floatWindowId.get()) else: newJNull()),
      "x": toJson(a.xChange),
      "y": toJson(a.yChange)
    }
    encodeStructVariant("MoveFloatingWindow", p)
  else:
    encodeStructVariant(ActionWireNames[a.kind], newJObject())
