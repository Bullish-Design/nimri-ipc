import unittest
import std/[json, options]
import ../src/nimri_ipc/[actions, models, requests]

suite "actions tests":
  test "every NiriActionKind has a wire name mapping":
    for kind in NiriActionKind:
      check ActionWireNames[kind].len > 0

  test "wire name count equals enum count":
    check ActionWireNames.len == ord(high(NiriActionKind)) + 1

  test "empty actions encode as empty struct variants":
    check toJson(focusWindowDown()) == parseJson("""{"FocusWindowDown":{}}""")
    check toJson(toggleOverview()) == parseJson("""{"ToggleOverview":{}}""")
    check toJson(powerOffMonitors()) == parseJson("""{"PowerOffMonitors":{}}""")
    check toJson(moveColumnLeft()) == parseJson("""{"MoveColumnLeft":{}}""")
    check toJson(focusMonitorLeft()) == parseJson("""{"FocusMonitorLeft":{}}""")

  test "optional window id actions":
    check toJson(closeWindow()) == parseJson("""{"CloseWindow":{"id":null}}""")
    check toJson(closeWindow(some(WindowId(42)))) == parseJson("""{"CloseWindow":{"id":42}}""")
    check toJson(toggleWindowFloating(some(WindowId(5)))) == parseJson("""{"ToggleWindowFloating":{"id":5}}""")

  test "required window id actions":
    check toJson(focusWindow(WindowId(1))) == parseJson("""{"FocusWindow":{"id":1}}""")
    check toJson(toggleWindowUrgent(WindowId(3))) == parseJson("""{"ToggleWindowUrgent":{"id":3}}""")

  test "quit and spawn actions":
    check toJson(actions.quit()) == parseJson("""{"Quit":{"skip_confirmation":false}}""")
    check toJson(actions.quit(skipConfirmation = true)) == parseJson("""{"Quit":{"skip_confirmation":true}}""")
    check toJson(spawn(@["ls", "-la"])) == parseJson("""{"Spawn":{"command":["ls","-la"]}}""")
    check toJson(spawnSh("echo hi")) == parseJson("""{"SpawnSh":{"command":"echo hi"}}""")

  test "screenshot actions":
    check toJson(screenshot()) == parseJson("""{"Screenshot":{"show_pointer":false,"path":null}}""")
    check toJson(screenshot(showPointer = true)) == parseJson("""{"Screenshot":{"show_pointer":true,"path":null}}""")
    check toJson(screenshotWindow(some(WindowId(1)), writeToDisk = false)) ==
      parseJson("""{"ScreenshotWindow":{"id":1,"write_to_disk":false,"show_pointer":false,"path":null}}""")

  test "workspace and monitor actions":
    check toJson(focusWorkspace(WorkspaceRef(kind: wrkByIndex, idx: WorkspaceIdx(2)))) ==
      parseJson("""{"FocusWorkspace":{"reference":{"Index":2}}}""")
    check toJson(moveWindowToWorkspaceDown(focus = true)) ==
      parseJson("""{"MoveWindowToWorkspaceDown":{"focus":true}}""")
    check toJson(focusMonitor("HDMI-A-1")) == parseJson("""{"FocusMonitor":{"output":"HDMI-A-1"}}""")

  test "layout and size actions":
    check toJson(switchLayout(LayoutSwitchTarget(kind: lstNext))) ==
      parseJson("""{"SwitchLayout":{"layout":"Next"}}""")
    check toJson(setColumnDisplay(cdTabbed)) ==
      parseJson("""{"SetColumnDisplay":{"display":"Tabbed"}}""")
    check toJson(setWindowWidth(SizeChange(kind: sckSetFixed, fixedVal: 800))) ==
      parseJson("""{"SetWindowWidth":{"id":null,"change":{"SetFixed":800}}}""")
    check toJson(setColumnWidth(SizeChange(kind: sckAdjustProportion, adjPropVal: 0.1))) ==
      parseJson("""{"SetColumnWidth":{"change":{"AdjustProportion":0.1}}}""")

  test "floating and cast actions":
    let x = PositionChange(kind: pckAdjustFixed, adjFixedVal: 10.0)
    let y = PositionChange(kind: pckAdjustFixed, adjFixedVal: -5.0)
    check toJson(moveFloatingWindow(x, y)) ==
      parseJson("""{"MoveFloatingWindow":{"id":null,"x":{"AdjustFixed":10.0},"y":{"AdjustFixed":-5.0}}}""")
    check toJson(stopCast(42'u64)) == parseJson("""{"StopCast":{"session_id":42}}""")
    check toJson(setDynamicCastMonitor(some("eDP-1"))) ==
      parseJson("""{"SetDynamicCastMonitor":{"output":"eDP-1"}}""")

  test "action request wrapping produces correct nesting":
    check toJson(requestAction(focusWindowDown())) ==
      parseJson("""{"Action":{"FocusWindowDown":{}}}""")
    check toJson(requestAction(actions.quit(true))) ==
      parseJson("""{"Action":{"Quit":{"skip_confirmation":true}}}""")
    check toJson(requestAction(spawn(@["ls"]))) ==
      parseJson("""{"Action":{"Spawn":{"command":["ls"]}}}""")
