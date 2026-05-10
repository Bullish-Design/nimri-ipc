import unittest
import std/[json, options]
import ../src/nimri_ipc/[actions, models, requests]

suite "actions tests":
  test "unit actions encode as strings":
    check toJson(focusWindowDown()) == parseJson("\"FocusWindowDown\"")
    check toJson(actions.quit()) == parseJson("\"Quit\"")
    check toJson(toggleOverview()) == parseJson("\"ToggleOverview\"")

  test "parameterized actions":
    check toJson(closeWindow()) == parseJson("{\"CloseWindow\":{\"id\":null}}")
    check toJson(closeWindow(some(WindowId(42)))) == parseJson("{\"CloseWindow\":{\"id\":42}}")
    check toJson(spawn(@["alacritty","--title","test"])) == parseJson("{\"Spawn\":[\"alacritty\",\"--title\",\"test\"]}")
    check toJson(spawnSh("echo hello")) == parseJson("{\"SpawnSh\":\"echo hello\"}")
    check toJson(setWindowWidth(SizeChange(kind: sckSetFixed, fixedVal: 800))) == parseJson("{\"SetWindowWidth\":{\"id\":null,\"change\":{\"SetFixed\":800}}}")
    check toJson(focusWorkspace(WorkspaceRef(kind: wrkByName, name: "main"))) == parseJson("{\"FocusWorkspace\":{\"reference\":{\"Name\":\"main\"}}}")

  test "action to request wrapping":
    let req = requestAction(closeWindow(some(WindowId(7))))
    check toJson(req) == parseJson("{\"Action\":{\"CloseWindow\":{\"id\":7}}}")
    check toJson(requestAction(actions.quit())) == parseJson("{\"Action\":\"Quit\"}")
