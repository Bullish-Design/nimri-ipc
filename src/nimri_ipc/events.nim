## nimri_ipc/events - Typed Niri event decoding

import std/[json, options]
import results
import ./[codec, models, errors]

type
  NiriEventKind* = enum
    neWorkspacesChanged, neWorkspaceActivated,
    neWorkspaceUrgencyChanged, neWorkspaceActiveWindowChanged,
    neWindowsChanged, neWindowOpenedOrChanged, neWindowClosed,
    neWindowFocusChanged, neWindowFocusTimestampChanged,
    neWindowUrgencyChanged, neWindowLayoutsChanged,
    neKeyboardLayoutsChanged, neKeyboardLayoutSwitched,
    neOverviewOpenedOrClosed, neConfigLoaded, neScreenshotCaptured,
    neCastsChanged, neCastStartedOrChanged, neCastStopped,
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
    of neCastStartedOrChanged: castValue*: Cast
    of neCastStopped: stoppedStreamId*: uint64
    of neUnknown:
      unknownEventKind*: string
      unknownEventRaw*: string

proc decodeEvent*(node: JsonNode): Result[NiriEvent, string] =
  let tv = parseTaggedVariant(node)
  if tv.isErr: return err(tv.error)

  case tv.get().tag
  of "WorkspacesChanged":
    var ws: seq[Workspace] = @[]
    if tv.get().payload.hasKey("workspaces"):
      for it in tv.get().payload["workspaces"].items:
        let w = fromJson(it, Workspace)
        if w.isOk: ws.add(w.get())
    ok(NiriEvent(kind: neWorkspacesChanged, workspaces: ws))
  of "WorkspaceActivated":
    ok(NiriEvent(kind: neWorkspaceActivated,
      activatedId: WorkspaceId(codec.getUint64(tv.get().payload, "id").get(0'u64)),
      activatedFocused: codec.getBool(tv.get().payload, "focused").get(false)))
  of "WorkspaceUrgencyChanged":
    ok(NiriEvent(kind: neWorkspaceUrgencyChanged,
      urgentWsId: WorkspaceId(codec.getUint64(tv.get().payload, "id").get(0'u64)),
      wsUrgent: codec.getBool(tv.get().payload, "urgent").get(false)))
  of "WorkspaceActiveWindowChanged":
    var wid = none(WindowId)
    let aw = codec.getOptionalField(tv.get().payload, "active_window_id")
    if aw.isSome: wid = some(WindowId(uint64(aw.get().getInt())))
    ok(NiriEvent(kind: neWorkspaceActiveWindowChanged,
      wsActiveWinWsId: WorkspaceId(codec.getUint64(tv.get().payload, "id").get(0'u64)),
      wsActiveWinId: wid))
  of "WindowsChanged":
    var wins: seq[Window] = @[]
    if tv.get().payload.hasKey("windows"):
      for it in tv.get().payload["windows"].items:
        let w = fromJson(it, Window)
        if w.isOk: wins.add(w.get())
    ok(NiriEvent(kind: neWindowsChanged, windows: wins))
  of "WindowOpenedOrChanged":
    let wnode = if tv.get().payload.hasKey("window"): tv.get().payload["window"] else: tv.get().payload
    let w = fromJson(wnode, Window)
    if w.isErr: return err(w.error)
    ok(NiriEvent(kind: neWindowOpenedOrChanged, window: w.get()))
  of "WindowClosed":
    ok(NiriEvent(kind: neWindowClosed, closedId: WindowId(codec.getUint64(tv.get().payload, "id").get(0'u64))))
  of "WindowFocusChanged":
    var wid = none(WindowId)
    let nid = codec.getOptionalField(tv.get().payload, "id")
    if nid.isSome: wid = some(WindowId(uint64(nid.get().getInt())))
    ok(NiriEvent(kind: neWindowFocusChanged, focusedId: wid))
  of "WindowUrgencyChanged":
    ok(NiriEvent(kind: neWindowUrgencyChanged,
      urgentWinId: WindowId(codec.getUint64(tv.get().payload, "id").get(0'u64)),
      winUrgent: codec.getBool(tv.get().payload, "urgent").get(false)))
  of "WindowLayoutsChanged":
    var changes: seq[tuple[id: WindowId, layout: WindowLayout]] = @[]
    if tv.get().payload.hasKey("changes"):
      for c in tv.get().payload["changes"].items:
        if c.kind == JArray and c.len == 2:
          let lid = WindowId(uint64(c[0].getInt()))
          let l = fromJson(c[1], WindowLayout)
          if l.isOk: changes.add((id: lid, layout: l.get()))
    ok(NiriEvent(kind: neWindowLayoutsChanged, layoutChanges: changes))
  of "KeyboardLayoutsChanged":
    let obj = if tv.get().payload.hasKey("names"): tv.get().payload else: tv.get().payload
    let kl = fromJson(obj, KeyboardLayouts)
    if kl.isErr: return err(kl.error)
    ok(NiriEvent(kind: neKeyboardLayoutsChanged, kbLayouts: kl.get()))
  of "KeyboardLayoutSwitched":
    ok(NiriEvent(kind: neKeyboardLayoutSwitched, kbIdx: uint8(codec.getInt(tv.get().payload, "idx").get(0))))
  of "OverviewOpenedOrClosed":
    ok(NiriEvent(kind: neOverviewOpenedOrClosed, isOverviewOpen: codec.getBool(tv.get().payload, "is_open").get(false)))
  of "ConfigLoaded":
    ok(NiriEvent(kind: neConfigLoaded, configFailed: codec.getBool(tv.get().payload, "failed").get(false)))
  of "ScreenshotCaptured":
    ok(NiriEvent(kind: neScreenshotCaptured, screenshotPath: codec.getOptionalStr(tv.get().payload, "path")))
  of "CastsChanged":
    var cs: seq[Cast] = @[]
    if tv.get().payload.hasKey("casts"):
      for c in tv.get().payload["casts"].items:
        let d = fromJson(c, Cast)
        if d.isOk: cs.add(d.get())
    ok(NiriEvent(kind: neCastsChanged, casts: cs))
  of "CastStartedOrChanged":
    let c = fromJson(tv.get().payload["cast"], Cast)
    if c.isErr: return err(c.error)
    ok(NiriEvent(kind: neCastStartedOrChanged, castValue: c.get()))
  of "CastStopped":
    ok(NiriEvent(kind: neCastStopped, stoppedStreamId: codec.getUint64(tv.get().payload, "stream_id").get(0'u64)))
  else:
    ok(NiriEvent(kind: neUnknown, unknownEventKind: tv.get().tag, unknownEventRaw: $tv.get().payload))

proc decodeEventLine*(line: string): Result[NiriEvent, NimriIpcError] =
  try:
    let n = parseJson(line)
    let d = decodeEvent(n)
    if d.isErr:
      return err(jsonDecodeError("decodeEventLine", d.error, line))
    ok(d.get())
  except JsonParsingError as e:
    err(jsonDecodeError("decodeEventLine", e.msg, line))

proc isWindowEvent*(event: NiriEvent): bool =
  event.kind in {neWindowsChanged, neWindowOpenedOrChanged, neWindowClosed, neWindowFocusChanged,
    neWindowFocusTimestampChanged, neWindowUrgencyChanged, neWindowLayoutsChanged}

proc isWorkspaceEvent*(event: NiriEvent): bool =
  event.kind in {neWorkspacesChanged, neWorkspaceActivated, neWorkspaceUrgencyChanged, neWorkspaceActiveWindowChanged}

proc isKeyboardEvent*(event: NiriEvent): bool =
  event.kind in {neKeyboardLayoutsChanged, neKeyboardLayoutSwitched}

proc isSystemEvent*(event: NiriEvent): bool =
  event.kind in {neOverviewOpenedOrClosed, neConfigLoaded, neScreenshotCaptured}

proc isCastEvent*(event: NiriEvent): bool =
  event.kind in {neCastsChanged, neCastStartedOrChanged, neCastStopped}
