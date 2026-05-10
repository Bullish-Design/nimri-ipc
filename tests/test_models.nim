import unittest
import std/[json, options]
import results
import ../src/nimri_ipc/[codec, models]

suite "models tests":
  test "ID round trip":
    let wid = WindowId(12345)
    let wj = toJson(wid)
    check fromJson(wj, WindowId).get() == wid

    let wsid = WorkspaceId(67890)
    check fromJson(toJson(wsid), WorkspaceId).get() == wsid

    let outName = OutputName("eDP-1")
    check fromJson(toJson(outName), OutputName).get() == outName

  test "Transform decode":
    check fromJson(parseJson("\"_90\""), Transform).get() == Rot90
    check fromJson(parseJson("\"_180\""), Transform).get() == Rot180
    check fromJson(parseJson("\"_270\""), Transform).get() == Rot270
    check fromJson(parseJson("\"Flipped90\""), Transform).get() == FlippedRot90
    check fromJson(parseJson("\"FutureTransform\""), Transform).get() == Unknown

  test "Layer decode":
    check fromJson(parseJson("\"Background\""), Layer).get() == Background
    check fromJson(parseJson("\"Overlay\""), Layer).get() == Overlay
    check fromJson(parseJson("\"Future\""), Layer).get() == UnknownLayer

  test "SizeChange encode/roundtrip":
    let s1 = SizeChange(kind: sckSetFixed, fixedVal: 100)
    check toJson(s1) == parseJson("{\"SetFixed\":100}")
    let s1d = fromJson(toJson(s1), SizeChange).get()
    check s1d.kind == s1.kind
    check s1d.fixedVal == s1.fixedVal
    let s2 = SizeChange(kind: sckSetProportion, propVal: 0.5)
    check toJson(s2) == parseJson("{\"SetProportion\":0.5}")

  test "WorkspaceRef encode":
    check toJson(WorkspaceRef(kind: wrkById, id: WorkspaceId(5))) == parseJson("{\"Id\":5}")
    check toJson(WorkspaceRef(kind: wrkByIndex, idx: WorkspaceIdx(2))) == parseJson("{\"Index\":2}")
    check toJson(WorkspaceRef(kind: wrkByName, name: "main")) == parseJson("{\"Name\":\"main\"}")

  test "LayoutSwitchTarget encode":
    check toJson(LayoutSwitchTarget(kind: lstNext)) == parseJson("\"Next\"")
    check toJson(LayoutSwitchTarget(kind: lstPrev)) == parseJson("\"Prev\"")
    check toJson(LayoutSwitchTarget(kind: lstByIndex, idx: 3)) == parseJson("{\"Index\":3}")

  test "Window decode from fixture":
    let n = parseFile("tests/fixtures/responses/windows.json")
    let r = parseReply(n)
    check r.isOk
    let wins = r.get()["Windows"]
    let w = fromJson(wins[0], Window)
    check w.isOk
    check uint64(w.get().id) == 1'u64
    check w.get().appId.get() == "Alacritty"
    check w.get().isFocused

  test "Window decode with extra fields":
    let n = parseFile("tests/fixtures/responses/windows_extra_fields.json")
    let r = parseReply(n)
    check r.isOk
    check fromJson(r.get()["Windows"][0], Window).isOk

  test "Workspace decode from fixture":
    let n = parseFile("tests/fixtures/responses/workspaces.json")
    let r = parseReply(n)
    let ws = fromJson(r.get()["Workspaces"][0], Workspace)
    check ws.isOk
    check uint64(ws.get().id) == 1'u64

  test "Output decode from fixture":
    let n = parseFile("tests/fixtures/responses/outputs.json")
    let r = parseReply(n)
    let outNode = r.get()["Outputs"]["eDP-1"]
    let o = fromJson(outNode, Output)
    check o.isOk
    check o.get().name == "eDP-1"
    check o.get().modes.len > 0

  test "KeyboardLayouts decode from fixture":
    let n = parseFile("tests/fixtures/responses/keyboard_layouts.json")
    let r = parseReply(n)
    let kl = fromJson(r.get()["KeyboardLayouts"], KeyboardLayouts)
    check kl.isOk
    check kl.get().names.len > 0

  test "snake_case mapping and toJson":
    let w = fromJson(parseJson("""{"id":1,"title":"t","app_id":"a","workspace_id":1,"is_focused":true,"is_floating":false,"is_urgent":false,"layout":{"tile_size":{"w":1.0,"h":1.0},"window_size":{"w":1,"h":1},"window_offset_in_tile":{"x":0.0,"y":0.0}}}"""), Window)
    check w.isOk
    let outJson = toJson(w.get())
    check outJson.hasKey("app_id")
    check not outJson.hasKey("appId")
