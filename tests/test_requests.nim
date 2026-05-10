import unittest
import std/[json, options, tables]
import results
import ../src/nimri_ipc/[requests, actions, models, errors]

suite "requests tests":
  test "unit queries encode":
    check toJson(requestVersion()) == parseJson("\"Version\"")
    check toJson(requestWindows()) == parseJson("\"Windows\"")
    check toJson(requestWorkspaces()) == parseJson("\"Workspaces\"")
    check toJson(requestOutputs()) == parseJson("\"Outputs\"")
    check toJson(requestFocusedWindow()) == parseJson("\"FocusedWindow\"")
    check toJson(requestFocusedOutput()) == parseJson("\"FocusedOutput\"")
    check toJson(requestLayers()) == parseJson("\"Layers\"")
    check toJson(requestKeyboardLayouts()) == parseJson("\"KeyboardLayouts\"")
    check toJson(requestOverviewState()) == parseJson("\"OverviewState\"")
    check toJson(requestCasts()) == parseJson("\"Casts\"")
    check toJson(requestPickWindow()) == parseJson("\"PickWindow\"")
    check toJson(requestPickColor()) == parseJson("\"PickColor\"")

  test "event stream and load config":
    check toJson(requestEventStream()) == parseJson("\"EventStream\"")
    check toJson(requestLoadConfig(some("/etc/niri/config.kdl"))) == parseJson("{\"LoadConfigFile\":{\"path\":\"/etc/niri/config.kdl\"}}")
    check toJson(requestLoadConfig()) == parseJson("{\"LoadConfigFile\":{\"path\":null}}")

  test "decode version and handled":
    let v = decodeResponse(parseJson("{\"Ok\":{\"Version\":\"0.1.9\"}}"))
    check v.isOk
    check v.get().kind == nresVersion
    check v.get().version == "0.1.9"

    let h = decodeResponse(parseJson("{\"Ok\":\"Handled\"}"))
    check h.isOk
    check h.get().kind == nresHandled

  test "decode fixture responses":
    let ws = decodeResponse(parseFile("tests/fixtures/responses/windows.json"))
    check ws.isOk
    check ws.get().kind == nresWindows
    check ws.get().windows.len > 0

    let wk = decodeResponse(parseFile("tests/fixtures/responses/workspaces.json"))
    check wk.isOk
    check wk.get().kind == nresWorkspaces

    let op = decodeResponse(parseFile("tests/fixtures/responses/outputs.json"))
    check op.isOk
    check op.get().kind == nresOutputs
    check len(op.get().outputs) > 0

  test "decode error and unknown":
    let er = decodeResponse(parseJson("{\"Err\":\"Unknown request\"}"))
    check er.isErr
    check er.error.kind == NiriError

    let u = decodeResponse(parseJson("{\"Ok\":{\"FutureResponse\":{\"data\":1}}}"))
    check u.isOk
    check u.get().kind == nresUnknown
    check u.get().unknownKind == "FutureResponse"

  test "action request nesting":
    check toJson(requestAction(actions.quit())) == parseJson("""{"Action":{"Quit":{"skip_confirmation":false}}}""")
    check toJson(requestAction(screenshot(showPointer = true))) ==
      parseJson("""{"Action":{"Screenshot":{"show_pointer":true,"path":null}}}""")
    check toJson(requestAction(setDynamicCastMonitor(some("eDP-1")))) ==
      parseJson("""{"Action":{"SetDynamicCastMonitor":{"output":"eDP-1"}}}""")
    check toJson(requestAction(focusMonitor("HDMI-A-1"))) ==
      parseJson("""{"Action":{"FocusMonitor":{"output":"HDMI-A-1"}}}""")
    check toJson(requestAction(moveWindowToWorkspaceDown(focus = true))) ==
      parseJson("""{"Action":{"MoveWindowToWorkspaceDown":{"focus":true}}}""")
