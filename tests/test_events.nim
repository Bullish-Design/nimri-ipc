import unittest
import std/[json, options]
import results
import ../src/nimri_ipc/[events, errors, models]

suite "events tests":
  test "workspace and window events":
    let a = decodeEvent(parseJson("{\"WorkspaceActivated\":{\"id\":5,\"focused\":true}}"))
    check a.isOk
    check a.get().kind == neWorkspaceActivated

    let c = decodeEvent(parseJson("{\"WindowClosed\":{\"id\":42}}"))
    check c.isOk
    check c.get().kind == neWindowClosed

  test "window focus changed none and some":
    let s = decodeEvent(parseJson("{\"WindowFocusChanged\":{\"id\":7}}"))
    check s.isOk
    check s.get().focusedId.isSome
    let n = decodeEvent(parseJson("{\"WindowFocusChanged\":{\"id\":null}}"))
    check n.isOk
    check n.get().focusedId.isNone

  test "window layouts changed":
    let e = decodeEvent(parseJson("{\"WindowLayoutsChanged\":{\"changes\":[[42,{\"tile_size\":{\"w\":1.0,\"h\":1.0},\"window_size\":{\"w\":1,\"h\":1},\"window_offset_in_tile\":{\"x\":0.0,\"y\":0.0}}]]}}"))
    check e.isOk
    check e.get().kind == neWindowLayoutsChanged
    check e.get().layoutChanges.len == 1

  test "unknown event":
    let u = decodeEvent(parseJson("{\"FutureEventType\":{\"data\":123}}"))
    check u.isOk
    check u.get().kind == neUnknown

  test "decodeEventLine":
    check decodeEventLine("{\"WindowClosed\":{\"id\":42}}") .isOk
    let bad = decodeEventLine("not json")
    check bad.isErr
    check bad.error.kind == JsonDecodeError

  test "classification":
    check isWindowEvent(NiriEvent(kind: neWindowClosed, closedId: WindowId(1)))
    check isWorkspaceEvent(NiriEvent(kind: neWorkspaceActivated, activatedId: WorkspaceId(1), activatedFocused: true))
    check isKeyboardEvent(NiriEvent(kind: neKeyboardLayoutSwitched, kbIdx: 1))
    check isSystemEvent(NiriEvent(kind: neConfigLoaded, configFailed: false))
    check isCastEvent(NiriEvent(kind: neCastStopped, stoppedStreamId: 1))

  test "fixture events decode":
    let files = @[
      "tests/fixtures/events/workspaces_changed.json",
      "tests/fixtures/events/windows_changed.json",
      "tests/fixtures/events/window_opened_or_changed.json",
      "tests/fixtures/events/window_focus_changed.json",
      "tests/fixtures/events/window_layouts_changed.json",
      "tests/fixtures/events/keyboard_layouts_changed.json",
      "tests/fixtures/events/keyboard_layout_switched.json"
    ]
    for f in files:
      let d = decodeEventLine(readFile(f))
      check d.isOk
