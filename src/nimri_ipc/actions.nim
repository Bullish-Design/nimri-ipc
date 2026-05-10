## nimri_ipc/actions - Niri actions and JSON encoding

import std/[json, options]
import ./[codec, models]

type
  NiriActionKind* = enum
    naFocusWindowDown, naFocusWindowUp, naFocusColumnLeft, naFocusColumnRight,
    naMoveWindowDown, naMoveWindowUp, naMoveColumnLeft, naMoveColumnRight,
    naQuit, naToggleOverview, naScreenshot, naPowerOffMonitors,
    naCloseWindow, naFullscreenWindow, naSetWindowWidth, naSetWindowHeight,
    naSpawn, naSpawnSh, naFocusWorkspace, naMoveWindowToWorkspace,
    naSwitchLayout, naSetColumnDisplay, naMoveFloatingWindow

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
  "FocusWindowDown", "FocusWindowUp", "FocusColumnLeft", "FocusColumnRight",
  "MoveWindowDown", "MoveWindowUp", "MoveColumnLeft", "MoveColumnRight",
  "Quit", "ToggleOverview", "Screenshot", "PowerOffMonitors",
  "CloseWindow", "FullscreenWindow", "SetWindowWidth", "SetWindowHeight",
  "Spawn", "SpawnSh", "FocusWorkspace", "MoveWindowToWorkspace",
  "SwitchLayout", "SetColumnDisplay", "MoveFloatingWindow"
]

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
