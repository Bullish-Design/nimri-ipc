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
    of naFocusWindowPrevious, naFocusWindowDown, naFocusWindowUp, naFocusWindowTop, naFocusWindowBottom,
       naFocusWindowDownOrTop, naFocusWindowUpOrBottom,
       naFocusWindowDownOrColumnLeft, naFocusWindowDownOrColumnRight,
       naFocusWindowUpOrColumnLeft, naFocusWindowUpOrColumnRight,
       naFocusWindowOrMonitorUp, naFocusWindowOrMonitorDown,
       naFocusWindowOrWorkspaceDown, naFocusWindowOrWorkspaceUp,
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
    of naFocusWindow, naToggleWindowUrgent, naSetWindowUrgent, naUnsetWindowUrgent:
      reqWindowId*: WindowId
    of naSetWindowWidth, naSetWindowHeight:
      sizeWindowId*: Option[WindowId]
      sizeChange*: SizeChange
    of naSetColumnWidth:
      colWidthChange*: SizeChange
    of naSpawn:
      spawnCommand*: seq[string]
    of naSpawnSh:
      shCommand*: string
    of naQuit:
      skipConfirmation*: bool
    of naScreenshot:
      ssShowPointer*: bool
      ssPath*: Option[string]
    of naScreenshotScreen:
      sssWriteToDisk*: bool
      sssShowPointer*: bool
      sssPath*: Option[string]
    of naScreenshotWindow:
      sswId*: Option[WindowId]
      sswWriteToDisk*: bool
      sswShowPointer*: bool
      sswPath*: Option[string]
    of naDoScreenTransition:
      transitionDelayMs*: Option[uint16]
    of naLoadConfigFile:
      configPath*: Option[string]
    of naFocusWorkspace:
      focusWsRef*: WorkspaceRef
    of naMoveWindowToWorkspace:
      mwtwWindowId*: Option[WindowId]
      mwtwRef*: WorkspaceRef
      mwtwFocus*: bool
    of naMoveColumnToWorkspace:
      mctwRef*: WorkspaceRef
      mctwFocus*: bool
    of naMoveWindowToWorkspaceDown, naMoveWindowToWorkspaceUp,
       naMoveColumnToWorkspaceDown, naMoveColumnToWorkspaceUp:
      moveFocus*: bool
    of naMoveWorkspaceToIndex:
      wsToIdx*: int
      wsToIdxRef*: Option[WorkspaceRef]
    of naSetWorkspaceName:
      wsNewName*: string
      wsNameRef*: Option[WorkspaceRef]
    of naUnsetWorkspaceName:
      unsetWsRef*: Option[WorkspaceRef]
    of naSwitchLayout:
      layoutTarget*: LayoutSwitchTarget
    of naSetColumnDisplay:
      columnDisplay*: ColumnDisplay
    of naFocusWindowInColumn:
      focusWinIdx*: uint8
    of naFocusColumn:
      focusColIdx*: int
    of naMoveColumnToIndex:
      moveColIdx*: int
    of naFocusMonitor, naMoveColumnToMonitor:
      outputName*: string
    of naMoveWindowToMonitor:
      mwtmId*: Option[WindowId]
      mwtmOutput*: string
    of naMoveWorkspaceToMonitor:
      mwstmOutput*: string
      mwstmRef*: Option[WorkspaceRef]
    of naMoveFloatingWindow:
      floatWindowId*: Option[WindowId]
      xChange*: PositionChange
      yChange*: PositionChange
    of naSetDynamicCastMonitor:
      castOutput*: Option[string]
    of naStopCast:
      castSessionId*: uint64

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
proc focusWindowTop*(): NiriAction = NiriAction(kind: naFocusWindowTop)
proc focusWindowBottom*(): NiriAction = NiriAction(kind: naFocusWindowBottom)
proc focusWindowDownOrTop*(): NiriAction = NiriAction(kind: naFocusWindowDownOrTop)
proc focusWindowUpOrBottom*(): NiriAction = NiriAction(kind: naFocusWindowUpOrBottom)
proc focusWindowDownOrColumnLeft*(): NiriAction = NiriAction(kind: naFocusWindowDownOrColumnLeft)
proc focusWindowDownOrColumnRight*(): NiriAction = NiriAction(kind: naFocusWindowDownOrColumnRight)
proc focusWindowUpOrColumnLeft*(): NiriAction = NiriAction(kind: naFocusWindowUpOrColumnLeft)
proc focusWindowUpOrColumnRight*(): NiriAction = NiriAction(kind: naFocusWindowUpOrColumnRight)
proc focusWindowOrMonitorUp*(): NiriAction = NiriAction(kind: naFocusWindowOrMonitorUp)
proc focusWindowOrMonitorDown*(): NiriAction = NiriAction(kind: naFocusWindowOrMonitorDown)
proc focusWindowOrWorkspaceDown*(): NiriAction = NiriAction(kind: naFocusWindowOrWorkspaceDown)
proc focusWindowOrWorkspaceUp*(): NiriAction = NiriAction(kind: naFocusWindowOrWorkspaceUp)
proc focusWindowPrevious*(): NiriAction = NiriAction(kind: naFocusWindowPrevious)
proc focusWindowInColumn*(index: uint8): NiriAction = NiriAction(kind: naFocusWindowInColumn, focusWinIdx: index)
proc focusWindow*(id: WindowId): NiriAction = NiriAction(kind: naFocusWindow, reqWindowId: id)

proc focusColumnLeft*(): NiriAction = NiriAction(kind: naFocusColumnLeft)
proc focusColumnRight*(): NiriAction = NiriAction(kind: naFocusColumnRight)
proc focusColumnFirst*(): NiriAction = NiriAction(kind: naFocusColumnFirst)
proc focusColumnLast*(): NiriAction = NiriAction(kind: naFocusColumnLast)
proc focusColumnRightOrFirst*(): NiriAction = NiriAction(kind: naFocusColumnRightOrFirst)
proc focusColumnLeftOrLast*(): NiriAction = NiriAction(kind: naFocusColumnLeftOrLast)
proc focusColumn*(index: int): NiriAction = NiriAction(kind: naFocusColumn, focusColIdx: index)
proc focusColumnOrMonitorLeft*(): NiriAction = NiriAction(kind: naFocusColumnOrMonitorLeft)
proc focusColumnOrMonitorRight*(): NiriAction = NiriAction(kind: naFocusColumnOrMonitorRight)

proc moveWindowDown*(): NiriAction = NiriAction(kind: naMoveWindowDown)
proc moveWindowUp*(): NiriAction = NiriAction(kind: naMoveWindowUp)
proc moveWindowDownOrToWorkspaceDown*(): NiriAction = NiriAction(kind: naMoveWindowDownOrToWorkspaceDown)
proc moveWindowUpOrToWorkspaceUp*(): NiriAction = NiriAction(kind: naMoveWindowUpOrToWorkspaceUp)
proc consumeOrExpelWindowLeft*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naConsumeOrExpelWindowLeft, windowId: id)
proc consumeOrExpelWindowRight*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naConsumeOrExpelWindowRight, windowId: id)
proc consumeWindowIntoColumn*(): NiriAction = NiriAction(kind: naConsumeWindowIntoColumn)
proc expelWindowFromColumn*(): NiriAction = NiriAction(kind: naExpelWindowFromColumn)
proc swapWindowRight*(): NiriAction = NiriAction(kind: naSwapWindowRight)
proc swapWindowLeft*(): NiriAction = NiriAction(kind: naSwapWindowLeft)

proc moveColumnLeft*(): NiriAction = NiriAction(kind: naMoveColumnLeft)
proc moveColumnRight*(): NiriAction = NiriAction(kind: naMoveColumnRight)
proc moveColumnToFirst*(): NiriAction = NiriAction(kind: naMoveColumnToFirst)
proc moveColumnToLast*(): NiriAction = NiriAction(kind: naMoveColumnToLast)
proc moveColumnLeftOrToMonitorLeft*(): NiriAction = NiriAction(kind: naMoveColumnLeftOrToMonitorLeft)
proc moveColumnRightOrToMonitorRight*(): NiriAction = NiriAction(kind: naMoveColumnRightOrToMonitorRight)
proc moveColumnToIndex*(index: int): NiriAction = NiriAction(kind: naMoveColumnToIndex, moveColIdx: index)
proc toggleColumnTabbedDisplay*(): NiriAction = NiriAction(kind: naToggleColumnTabbedDisplay)
proc setColumnDisplay*(display: ColumnDisplay): NiriAction = NiriAction(kind: naSetColumnDisplay, columnDisplay: display)
proc centerColumn*(): NiriAction = NiriAction(kind: naCenterColumn)
proc centerWindow*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naCenterWindow, windowId: id)
proc centerVisibleColumns*(): NiriAction = NiriAction(kind: naCenterVisibleColumns)
proc maximizeColumn*(): NiriAction = NiriAction(kind: naMaximizeColumn)
proc setColumnWidth*(change: SizeChange): NiriAction = NiriAction(kind: naSetColumnWidth, colWidthChange: change)
proc expandColumnToAvailableWidth*(): NiriAction = NiriAction(kind: naExpandColumnToAvailableWidth)
proc switchPresetColumnWidth*(): NiriAction = NiriAction(kind: naSwitchPresetColumnWidth)
proc switchPresetColumnWidthBack*(): NiriAction = NiriAction(kind: naSwitchPresetColumnWidthBack)

proc setWindowWidth*(change: SizeChange, id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naSetWindowWidth, sizeWindowId: id, sizeChange: change)
proc setWindowHeight*(change: SizeChange, id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naSetWindowHeight, sizeWindowId: id, sizeChange: change)
proc resetWindowHeight*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naResetWindowHeight, windowId: id)
proc switchPresetWindowWidth*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naSwitchPresetWindowWidth, windowId: id)
proc switchPresetWindowWidthBack*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naSwitchPresetWindowWidthBack, windowId: id)
proc switchPresetWindowHeight*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naSwitchPresetWindowHeight, windowId: id)
proc switchPresetWindowHeightBack*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naSwitchPresetWindowHeightBack, windowId: id)
proc maximizeWindowToEdges*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naMaximizeWindowToEdges, windowId: id)

proc switchLayout*(target: LayoutSwitchTarget): NiriAction = NiriAction(kind: naSwitchLayout, layoutTarget: target)

proc focusWorkspaceDown*(): NiriAction = NiriAction(kind: naFocusWorkspaceDown)
proc focusWorkspaceUp*(): NiriAction = NiriAction(kind: naFocusWorkspaceUp)
proc focusWorkspace*(refv: WorkspaceRef): NiriAction = NiriAction(kind: naFocusWorkspace, focusWsRef: refv)
proc focusWorkspacePrevious*(): NiriAction = NiriAction(kind: naFocusWorkspacePrevious)
proc moveWindowToWorkspaceDown*(focus: bool = false): NiriAction = NiriAction(kind: naMoveWindowToWorkspaceDown, moveFocus: focus)
proc moveWindowToWorkspaceUp*(focus: bool = false): NiriAction = NiriAction(kind: naMoveWindowToWorkspaceUp, moveFocus: focus)
proc moveWindowToWorkspace*(refv: WorkspaceRef, focus: bool = false, windowId: Option[WindowId] = none(WindowId)): NiriAction =
  NiriAction(kind: naMoveWindowToWorkspace, mwtwRef: refv, mwtwFocus: focus, mwtwWindowId: windowId)
proc moveColumnToWorkspaceDown*(focus: bool = false): NiriAction = NiriAction(kind: naMoveColumnToWorkspaceDown, moveFocus: focus)
proc moveColumnToWorkspaceUp*(focus: bool = false): NiriAction = NiriAction(kind: naMoveColumnToWorkspaceUp, moveFocus: focus)
proc moveColumnToWorkspace*(refv: WorkspaceRef, focus: bool = false): NiriAction = NiriAction(kind: naMoveColumnToWorkspace, mctwRef: refv, mctwFocus: focus)
proc moveWorkspaceDown*(): NiriAction = NiriAction(kind: naMoveWorkspaceDown)
proc moveWorkspaceUp*(): NiriAction = NiriAction(kind: naMoveWorkspaceUp)
proc moveWorkspaceToIndex*(index: int, refv: Option[WorkspaceRef] = none(WorkspaceRef)): NiriAction = NiriAction(kind: naMoveWorkspaceToIndex, wsToIdx: index, wsToIdxRef: refv)
proc setWorkspaceName*(name: string, workspace: Option[WorkspaceRef] = none(WorkspaceRef)): NiriAction = NiriAction(kind: naSetWorkspaceName, wsNewName: name, wsNameRef: workspace)
proc unsetWorkspaceName*(reference: Option[WorkspaceRef] = none(WorkspaceRef)): NiriAction = NiriAction(kind: naUnsetWorkspaceName, unsetWsRef: reference)

proc focusMonitorLeft*(): NiriAction = NiriAction(kind: naFocusMonitorLeft)
proc focusMonitorRight*(): NiriAction = NiriAction(kind: naFocusMonitorRight)
proc focusMonitorDown*(): NiriAction = NiriAction(kind: naFocusMonitorDown)
proc focusMonitorUp*(): NiriAction = NiriAction(kind: naFocusMonitorUp)
proc focusMonitorPrevious*(): NiriAction = NiriAction(kind: naFocusMonitorPrevious)
proc focusMonitorNext*(): NiriAction = NiriAction(kind: naFocusMonitorNext)
proc focusMonitor*(output: string): NiriAction = NiriAction(kind: naFocusMonitor, outputName: output)

proc moveWindowToMonitorLeft*(): NiriAction = NiriAction(kind: naMoveWindowToMonitorLeft)
proc moveWindowToMonitorRight*(): NiriAction = NiriAction(kind: naMoveWindowToMonitorRight)
proc moveWindowToMonitorDown*(): NiriAction = NiriAction(kind: naMoveWindowToMonitorDown)
proc moveWindowToMonitorUp*(): NiriAction = NiriAction(kind: naMoveWindowToMonitorUp)
proc moveWindowToMonitorPrevious*(): NiriAction = NiriAction(kind: naMoveWindowToMonitorPrevious)
proc moveWindowToMonitorNext*(): NiriAction = NiriAction(kind: naMoveWindowToMonitorNext)
proc moveWindowToMonitor*(output: string, id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naMoveWindowToMonitor, mwtmOutput: output, mwtmId: id)

proc moveColumnToMonitorLeft*(): NiriAction = NiriAction(kind: naMoveColumnToMonitorLeft)
proc moveColumnToMonitorRight*(): NiriAction = NiriAction(kind: naMoveColumnToMonitorRight)
proc moveColumnToMonitorDown*(): NiriAction = NiriAction(kind: naMoveColumnToMonitorDown)
proc moveColumnToMonitorUp*(): NiriAction = NiriAction(kind: naMoveColumnToMonitorUp)
proc moveColumnToMonitorPrevious*(): NiriAction = NiriAction(kind: naMoveColumnToMonitorPrevious)
proc moveColumnToMonitorNext*(): NiriAction = NiriAction(kind: naMoveColumnToMonitorNext)
proc moveColumnToMonitor*(output: string): NiriAction = NiriAction(kind: naMoveColumnToMonitor, outputName: output)

proc moveWorkspaceToMonitorLeft*(): NiriAction = NiriAction(kind: naMoveWorkspaceToMonitorLeft)
proc moveWorkspaceToMonitorRight*(): NiriAction = NiriAction(kind: naMoveWorkspaceToMonitorRight)
proc moveWorkspaceToMonitorDown*(): NiriAction = NiriAction(kind: naMoveWorkspaceToMonitorDown)
proc moveWorkspaceToMonitorUp*(): NiriAction = NiriAction(kind: naMoveWorkspaceToMonitorUp)
proc moveWorkspaceToMonitorPrevious*(): NiriAction = NiriAction(kind: naMoveWorkspaceToMonitorPrevious)
proc moveWorkspaceToMonitorNext*(): NiriAction = NiriAction(kind: naMoveWorkspaceToMonitorNext)
proc moveWorkspaceToMonitor*(output: string, reference: Option[WorkspaceRef] = none(WorkspaceRef)): NiriAction = NiriAction(kind: naMoveWorkspaceToMonitor, mwstmOutput: output, mwstmRef: reference)

proc toggleWindowFloating*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naToggleWindowFloating, windowId: id)
proc moveWindowToFloating*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naMoveWindowToFloating, windowId: id)
proc moveWindowToTiling*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naMoveWindowToTiling, windowId: id)
proc focusFloating*(): NiriAction = NiriAction(kind: naFocusFloating)
proc focusTiling*(): NiriAction = NiriAction(kind: naFocusTiling)
proc switchFocusBetweenFloatingAndTiling*(): NiriAction = NiriAction(kind: naSwitchFocusBetweenFloatingAndTiling)
proc moveFloatingWindow*(x, y: PositionChange, id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naMoveFloatingWindow, floatWindowId: id, xChange: x, yChange: y)

proc toggleWindowRuleOpacity*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naToggleWindowRuleOpacity, windowId: id)

proc setDynamicCastWindow*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naSetDynamicCastWindow, windowId: id)
proc setDynamicCastMonitor*(output: Option[string] = none(string)): NiriAction = NiriAction(kind: naSetDynamicCastMonitor, castOutput: output)
proc clearDynamicCastTarget*(): NiriAction = NiriAction(kind: naClearDynamicCastTarget)
proc stopCast*(sessionId: uint64): NiriAction = NiriAction(kind: naStopCast, castSessionId: sessionId)

proc toggleOverview*(): NiriAction = NiriAction(kind: naToggleOverview)
proc openOverview*(): NiriAction = NiriAction(kind: naOpenOverview)
proc closeOverview*(): NiriAction = NiriAction(kind: naCloseOverview)

proc toggleWindowUrgent*(id: WindowId): NiriAction = NiriAction(kind: naToggleWindowUrgent, reqWindowId: id)
proc setWindowUrgent*(id: WindowId): NiriAction = NiriAction(kind: naSetWindowUrgent, reqWindowId: id)
proc unsetWindowUrgent*(id: WindowId): NiriAction = NiriAction(kind: naUnsetWindowUrgent, reqWindowId: id)

proc toggleDebugTint*(): NiriAction = NiriAction(kind: naToggleDebugTint)
proc debugToggleOpaqueRegions*(): NiriAction = NiriAction(kind: naDebugToggleOpaqueRegions)
proc debugToggleDamage*(): NiriAction = NiriAction(kind: naDebugToggleDamage)

proc quit*(skipConfirmation: bool = false): NiriAction = NiriAction(kind: naQuit, skipConfirmation: skipConfirmation)
proc powerOffMonitors*(): NiriAction = NiriAction(kind: naPowerOffMonitors)
proc powerOnMonitors*(): NiriAction = NiriAction(kind: naPowerOnMonitors)
proc spawn*(command: seq[string]): NiriAction = NiriAction(kind: naSpawn, spawnCommand: command)
proc spawnSh*(command: string): NiriAction = NiriAction(kind: naSpawnSh, shCommand: command)
proc doScreenTransition*(delayMs: Option[uint16] = none(uint16)): NiriAction = NiriAction(kind: naDoScreenTransition, transitionDelayMs: delayMs)
proc loadConfigFile*(path: Option[string] = none(string)): NiriAction = NiriAction(kind: naLoadConfigFile, configPath: path)
proc showHotkeyOverlay*(): NiriAction = NiriAction(kind: naShowHotkeyOverlay)
proc toggleKeyboardShortcutsInhibit*(): NiriAction = NiriAction(kind: naToggleKeyboardShortcutsInhibit)
proc screenshot*(showPointer: bool = false, path: Option[string] = none(string)): NiriAction = NiriAction(kind: naScreenshot, ssShowPointer: showPointer, ssPath: path)
proc screenshotScreen*(writeToDisk: bool = true, showPointer: bool = false, path: Option[string] = none(string)): NiriAction = NiriAction(kind: naScreenshotScreen, sssWriteToDisk: writeToDisk, sssShowPointer: showPointer, sssPath: path)
proc screenshotWindow*(id: Option[WindowId] = none(WindowId), writeToDisk: bool = true, showPointer: bool = false, path: Option[string] = none(string)): NiriAction = NiriAction(kind: naScreenshotWindow, sswId: id, sswWriteToDisk: writeToDisk, sswShowPointer: showPointer, sswPath: path)
proc closeWindow*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naCloseWindow, windowId: id)
proc fullscreenWindow*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naFullscreenWindow, windowId: id)
proc toggleWindowedFullscreen*(id: Option[WindowId] = none(WindowId)): NiriAction = NiriAction(kind: naToggleWindowedFullscreen, windowId: id)

proc encodeEmptyAction(kind: NiriActionKind): JsonNode =
  encodeStructVariant(ActionWireNames[kind], newJObject())

proc encodeOptionalId(id: Option[WindowId]): JsonNode =
  if id.isSome: toJson(id.get()) else: newJNull()

proc encodeWindowIdAction(kind: NiriActionKind, id: Option[WindowId]): JsonNode =
  encodeStructVariant(ActionWireNames[kind], %*{"id": encodeOptionalId(id)})

proc encodeReqWindowIdAction(kind: NiriActionKind, id: WindowId): JsonNode =
  encodeStructVariant(ActionWireNames[kind], %*{"id": toJson(id)})

proc encodeOptionString(s: Option[string]): JsonNode =
  if s.isSome: %s.get() else: newJNull()

proc encodeOptionWorkspaceRef(v: Option[WorkspaceRef]): JsonNode =
  if v.isSome: toJson(v.get()) else: newJNull()

proc toJson*(a: NiriAction): JsonNode =
  case a.kind
  of naFocusWindowPrevious, naFocusWindowDown, naFocusWindowUp, naFocusWindowTop, naFocusWindowBottom,
     naFocusWindowDownOrTop, naFocusWindowUpOrBottom,
     naFocusWindowDownOrColumnLeft, naFocusWindowDownOrColumnRight,
     naFocusWindowUpOrColumnLeft, naFocusWindowUpOrColumnRight,
     naFocusWindowOrMonitorUp, naFocusWindowOrMonitorDown,
     naFocusWindowOrWorkspaceDown, naFocusWindowOrWorkspaceUp,
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
    encodeEmptyAction(a.kind)
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
    encodeWindowIdAction(a.kind, a.windowId)
  of naFocusWindow, naToggleWindowUrgent, naSetWindowUrgent, naUnsetWindowUrgent:
    encodeReqWindowIdAction(a.kind, a.reqWindowId)
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
    encodeStructVariant("Screenshot", %*{"show_pointer": a.ssShowPointer, "path": encodeOptionString(a.ssPath)})
  of naScreenshotScreen:
    encodeStructVariant("ScreenshotScreen", %*{
      "write_to_disk": a.sssWriteToDisk,
      "show_pointer": a.sssShowPointer,
      "path": encodeOptionString(a.sssPath)
    })
  of naScreenshotWindow:
    encodeStructVariant("ScreenshotWindow", %*{
      "id": encodeOptionalId(a.sswId),
      "write_to_disk": a.sswWriteToDisk,
      "show_pointer": a.sswShowPointer,
      "path": encodeOptionString(a.sswPath)
    })
  of naDoScreenTransition:
    let n = if a.transitionDelayMs.isSome: %a.transitionDelayMs.get() else: newJNull()
    encodeStructVariant("DoScreenTransition", %*{"delay_ms": n})
  of naLoadConfigFile:
    encodeStructVariant("LoadConfigFile", %*{"path": encodeOptionString(a.configPath)})
  of naFocusWorkspace:
    encodeStructVariant("FocusWorkspace", %*{"reference": toJson(a.focusWsRef)})
  of naMoveWindowToWorkspace:
    encodeStructVariant("MoveWindowToWorkspace", %*{
      "window_id": encodeOptionalId(a.mwtwWindowId),
      "reference": toJson(a.mwtwRef),
      "focus": a.mwtwFocus
    })
  of naMoveColumnToWorkspace:
    encodeStructVariant("MoveColumnToWorkspace", %*{"reference": toJson(a.mctwRef), "focus": a.mctwFocus})
  of naMoveWindowToWorkspaceDown, naMoveWindowToWorkspaceUp,
     naMoveColumnToWorkspaceDown, naMoveColumnToWorkspaceUp:
    encodeStructVariant(ActionWireNames[a.kind], %*{"focus": a.moveFocus})
  of naMoveWorkspaceToIndex:
    encodeStructVariant("MoveWorkspaceToIndex", %*{"index": a.wsToIdx, "reference": encodeOptionWorkspaceRef(a.wsToIdxRef)})
  of naSetWorkspaceName:
    encodeStructVariant("SetWorkspaceName", %*{"name": a.wsNewName, "workspace": encodeOptionWorkspaceRef(a.wsNameRef)})
  of naUnsetWorkspaceName:
    encodeStructVariant("UnsetWorkspaceName", %*{"reference": encodeOptionWorkspaceRef(a.unsetWsRef)})
  of naSwitchLayout:
    encodeStructVariant("SwitchLayout", %*{"layout": toJson(a.layoutTarget)})
  of naSetColumnDisplay:
    let d = if a.columnDisplay == cdTabbed: "Tabbed" else: "Normal"
    encodeStructVariant("SetColumnDisplay", %*{"display": d})
  of naFocusWindowInColumn:
    encodeStructVariant("FocusWindowInColumn", %*{"index": a.focusWinIdx})
  of naFocusColumn:
    encodeStructVariant("FocusColumn", %*{"index": a.focusColIdx})
  of naMoveColumnToIndex:
    encodeStructVariant("MoveColumnToIndex", %*{"index": a.moveColIdx})
  of naFocusMonitor, naMoveColumnToMonitor:
    encodeStructVariant(ActionWireNames[a.kind], %*{"output": a.outputName})
  of naMoveWindowToMonitor:
    encodeStructVariant("MoveWindowToMonitor", %*{"id": encodeOptionalId(a.mwtmId), "output": a.mwtmOutput})
  of naMoveWorkspaceToMonitor:
    encodeStructVariant("MoveWorkspaceToMonitor", %*{"output": a.mwstmOutput, "reference": encodeOptionWorkspaceRef(a.mwstmRef)})
  of naMoveFloatingWindow:
    encodeStructVariant("MoveFloatingWindow", %*{
      "id": encodeOptionalId(a.floatWindowId),
      "x": toJson(a.xChange),
      "y": toJson(a.yChange)
    })
  of naSetDynamicCastMonitor:
    encodeStructVariant("SetDynamicCastMonitor", %*{"output": encodeOptionString(a.castOutput)})
  of naStopCast:
    encodeStructVariant("StopCast", %*{"session_id": %a.castSessionId})
