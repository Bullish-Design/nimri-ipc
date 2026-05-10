## nimri_ipc/models - Niri domain model types and JSON mappings

import std/[json, options, hashes]
import results
import ./codec

type
  WindowId* = distinct uint64
  WorkspaceId* = distinct uint64
  OutputName* = distinct string
  WorkspaceIdx* = distinct uint8

proc `==`*(a, b: WindowId): bool = uint64(a) == uint64(b)
proc `==`*(a, b: WorkspaceId): bool = uint64(a) == uint64(b)
proc `==`*(a, b: OutputName): bool = string(a) == string(b)
proc `==`*(a, b: WorkspaceIdx): bool = uint8(a) == uint8(b)

proc `$`*(v: WindowId): string = $uint64(v)
proc `$`*(v: WorkspaceId): string = $uint64(v)
proc `$`*(v: OutputName): string = string(v)
proc `$`*(v: WorkspaceIdx): string = $uint8(v)

proc hash*(v: WindowId): Hash = hash(uint64(v))
proc hash*(v: WorkspaceId): Hash = hash(uint64(v))
proc hash*(v: OutputName): Hash = hash(string(v))
proc hash*(v: WorkspaceIdx): Hash = hash(uint8(v))

proc toJson*(v: WindowId): JsonNode = %uint64(v)
proc toJson*(v: WorkspaceId): JsonNode = %uint64(v)
proc toJson*(v: OutputName): JsonNode = %string(v)
proc toJson*(v: WorkspaceIdx): JsonNode = %uint8(v)

proc fromJson*(node: JsonNode, T: typedesc[WindowId]): Result[WindowId, string] =
  if node.kind != JInt or node.getInt() < 0:
    return err("WindowId must be non-negative int")
  ok(WindowId(uint64(node.getInt())))

proc fromJson*(node: JsonNode, T: typedesc[WorkspaceId]): Result[WorkspaceId, string] =
  if node.kind != JInt or node.getInt() < 0:
    return err("WorkspaceId must be non-negative int")
  ok(WorkspaceId(uint64(node.getInt())))

proc fromJson*(node: JsonNode, T: typedesc[OutputName]): Result[OutputName, string] =
  if node.kind != JString:
    return err("OutputName must be string")
  ok(OutputName(node.getStr()))

proc fromJson*(node: JsonNode, T: typedesc[WorkspaceIdx]): Result[WorkspaceIdx, string] =
  if node.kind != JInt or node.getInt() < 0 or node.getInt() > 255:
    return err("WorkspaceIdx must be uint8")
  ok(WorkspaceIdx(uint8(node.getInt())))

type
  Transform* = enum
    Normal, Rot90, Rot180, Rot270,
    Flipped, FlippedRot90, FlippedRot180, FlippedRot270,
    Unknown

  Layer* = enum
    Background, Bottom, Top, Overlay, UnknownLayer

  LayerSurfaceKeyboardInteractivity* = enum
    LskiNone, Exclusive, OnDemand, UnknownInteractivity

  CastKind* = enum
    Monitor, WindowCast, UnknownCastKind

  ColumnDisplay* = enum
    cdNormal, cdTabbed

  LayoutSwitchTargetKind* = enum
    lstNext, lstPrev, lstByIndex

  LayoutSwitchTarget* = object
    case kind*: LayoutSwitchTargetKind
    of lstByIndex: idx*: uint8
    else: discard

  SizeChangeKind* = enum
    sckSetFixed, sckSetProportion, sckAdjustFixed, sckAdjustProportion

  SizeChange* = object
    case kind*: SizeChangeKind
    of sckSetFixed: fixedVal*: int32
    of sckSetProportion: propVal*: float64
    of sckAdjustFixed: adjFixedVal*: int32
    of sckAdjustProportion: adjPropVal*: float64

  PositionChangeKind* = enum
    pckSetFixed, pckSetProportion, pckAdjustFixed, pckAdjustProportion

  PositionChange* = object
    case kind*: PositionChangeKind
    of pckSetFixed: fixedVal*: float64
    of pckSetProportion: propVal*: float64
    of pckAdjustFixed: adjFixedVal*: float64
    of pckAdjustProportion: adjPropVal*: float64

  WorkspaceRefKind* = enum
    wrkById, wrkByIndex, wrkByName

  WorkspaceRef* = object
    case kind*: WorkspaceRefKind
    of wrkById: id*: WorkspaceId
    of wrkByIndex: idx*: WorkspaceIdx
    of wrkByName: name*: string

  Timestamp* = object
    secs*: uint64
    nanos*: uint32

  Mode* = object
    width*: uint16
    height*: uint16
    refreshRate*: uint32
    isPreferred*: bool

  LogicalOutput* = object
    x*: int32
    y*: int32
    width*: uint32
    height*: uint32
    scale*: float64
    transform*: Transform

  Output* = object
    name*: string
    make*: string
    model*: string
    serial*: Option[string]
    physicalSize*: Option[tuple[w: uint32, h: uint32]]
    modes*: seq[Mode]
    currentMode*: Option[int]
    vrrSupported*: bool
    vrrEnabled*: bool
    logical*: Option[LogicalOutput]

  WindowLayout* = object
    tileSize*: tuple[w: float64, h: float64]
    windowSize*: tuple[w: int32, h: int32]
    posInScrollingLayout*: Option[tuple[col: int, win: int]]
    tilePosInWorkspaceView*: Option[tuple[x: float64, y: float64]]
    windowOffsetInTile*: tuple[x: float64, y: float64]

  Window* = object
    id*: WindowId
    title*: Option[string]
    appId*: Option[string]
    pid*: Option[int32]
    workspaceId*: Option[WorkspaceId]
    isFocused*: bool
    isFloating*: bool
    isUrgent*: bool
    layout*: WindowLayout
    focusTimestamp*: Option[Timestamp]

  Workspace* = object
    id*: WorkspaceId
    idx*: WorkspaceIdx
    name*: Option[string]
    output*: Option[string]
    isActive*: bool
    isFocused*: bool
    isUrgent*: bool
    activeWindowId*: Option[WindowId]

  KeyboardLayouts* = object
    names*: seq[string]
    currentIdx*: uint8

  LayerSurface* = object
    namespace*: string
    output*: string
    layer*: Layer
    keyboardInteractivity*: LayerSurfaceKeyboardInteractivity

  CastTarget* = object
    raw*: JsonNode

  Cast* = object
    streamId*: uint64
    sessionId*: uint64
    kind*: CastKind
    target*: CastTarget
    isActive*: bool
    pid*: Option[int32]

proc transformFromWire(s: string): Transform =
  case s
  of "Normal": Normal
  of "_90": Rot90
  of "_180": Rot180
  of "_270": Rot270
  of "Flipped": Flipped
  of "Flipped90": FlippedRot90
  of "Flipped180": FlippedRot180
  of "Flipped270": FlippedRot270
  else: Unknown

proc transformToWire(t: Transform): string =
  case t
  of Normal: "Normal"
  of Rot90: "_90"
  of Rot180: "_180"
  of Rot270: "_270"
  of Flipped: "Flipped"
  of FlippedRot90: "Flipped90"
  of FlippedRot180: "Flipped180"
  of FlippedRot270: "Flipped270"
  else: "Unknown"

proc fromJson*(node: JsonNode, T: typedesc[Transform]): Result[Transform, string] =
  if node.kind != JString: return err("transform must be string")
  ok(transformFromWire(node.getStr()))

proc toJson*(t: Transform): JsonNode = %transformToWire(t)

proc fromJson*(node: JsonNode, T: typedesc[Layer]): Result[Layer, string] =
  if node.kind != JString: return err("layer must be string")
  ok(case node.getStr()
    of "Background": Background
    of "Bottom": Bottom
    of "Top": Top
    of "Overlay": Overlay
    else: UnknownLayer)

proc toJson*(l: Layer): JsonNode = %(case l
  of Background: "Background"
  of Bottom: "Bottom"
  of Top: "Top"
  of Overlay: "Overlay"
  else: "Unknown")

proc fromJson*(node: JsonNode, T: typedesc[LayerSurfaceKeyboardInteractivity]): Result[LayerSurfaceKeyboardInteractivity, string] =
  if node.kind != JString: return err("keyboard_interactivity must be string")
  ok(case node.getStr()
    of "None": LskiNone
    of "Exclusive": Exclusive
    of "OnDemand": OnDemand
    else: UnknownInteractivity)

proc toJson*(v: LayerSurfaceKeyboardInteractivity): JsonNode = %(case v
  of LskiNone: "None"
  of Exclusive: "Exclusive"
  of OnDemand: "OnDemand"
  else: "Unknown")

proc fromJson*(node: JsonNode, T: typedesc[CastKind]): Result[CastKind, string] =
  if node.kind != JString: return err("cast kind must be string")
  ok(case node.getStr()
    of "Monitor": Monitor
    of "Window": WindowCast
    else: UnknownCastKind)

proc toJson*(v: CastKind): JsonNode = %(case v
  of Monitor: "Monitor"
  of WindowCast: "Window"
  else: "Unknown")

proc toJson*(v: LayoutSwitchTarget): JsonNode =
  case v.kind
  of lstNext: result = newJString("Next")
  of lstPrev: result = newJString("Prev")
  of lstByIndex:
    result = newJObject()
    result["Index"] = %v.idx

proc toJson*(v: SizeChange): JsonNode =
  case v.kind
  of sckSetFixed: encodeStructVariant("SetFixed", %v.fixedVal)
  of sckSetProportion: encodeStructVariant("SetProportion", %v.propVal)
  of sckAdjustFixed: encodeStructVariant("AdjustFixed", %v.adjFixedVal)
  of sckAdjustProportion: encodeStructVariant("AdjustProportion", %v.adjPropVal)

proc fromJson*(node: JsonNode, T: typedesc[SizeChange]): Result[SizeChange, string] =
  let tv = parseTaggedVariant(node)
  if tv.isErr: return err(tv.error)
  case tv.get().tag
  of "SetFixed": ok(SizeChange(kind: sckSetFixed, fixedVal: int32(tv.get().payload.getInt())))
  of "SetProportion": ok(SizeChange(kind: sckSetProportion, propVal: tv.get().payload.getFloat()))
  of "AdjustFixed": ok(SizeChange(kind: sckAdjustFixed, adjFixedVal: int32(tv.get().payload.getInt())))
  of "AdjustProportion": ok(SizeChange(kind: sckAdjustProportion, adjPropVal: tv.get().payload.getFloat()))
  else: err("unknown SizeChange variant")

proc toJson*(v: PositionChange): JsonNode =
  case v.kind
  of pckSetFixed: encodeStructVariant("SetFixed", %v.fixedVal)
  of pckSetProportion: encodeStructVariant("SetProportion", %v.propVal)
  of pckAdjustFixed: encodeStructVariant("AdjustFixed", %v.adjFixedVal)
  of pckAdjustProportion: encodeStructVariant("AdjustProportion", %v.adjPropVal)

proc fromJson*(node: JsonNode, T: typedesc[PositionChange]): Result[PositionChange, string] =
  let tv = parseTaggedVariant(node)
  if tv.isErr: return err(tv.error)
  case tv.get().tag
  of "SetFixed": ok(PositionChange(kind: pckSetFixed, fixedVal: tv.get().payload.getFloat()))
  of "SetProportion": ok(PositionChange(kind: pckSetProportion, propVal: tv.get().payload.getFloat()))
  of "AdjustFixed": ok(PositionChange(kind: pckAdjustFixed, adjFixedVal: tv.get().payload.getFloat()))
  of "AdjustProportion": ok(PositionChange(kind: pckAdjustProportion, adjPropVal: tv.get().payload.getFloat()))
  else: err("unknown PositionChange variant")

proc toJson*(v: WorkspaceRef): JsonNode =
  case v.kind
  of wrkById: encodeStructVariant("Id", toJson(v.id))
  of wrkByIndex: encodeStructVariant("Index", toJson(v.idx))
  of wrkByName: encodeStructVariant("Name", %v.name)

proc fromJson*(node: JsonNode, T: typedesc[Timestamp]): Result[Timestamp, string] =
  let secs = codec.getUint64(node, "secs")
  let nanos = codec.getInt(node, "nanos")
  if secs.isErr or nanos.isErr: return err("invalid timestamp")
  ok(Timestamp(secs: secs.get(), nanos: uint32(nanos.get())))

proc fromJson*(node: JsonNode, T: typedesc[Mode]): Result[Mode, string] =
  let w = codec.getInt(node, "width")
  let h = codec.getInt(node, "height")
  let rr = codec.getInt(node, "refresh_rate")
  let p = codec.getBool(node, "is_preferred")
  if w.isErr or h.isErr or rr.isErr or p.isErr: return err("invalid mode")
  ok(Mode(width: uint16(w.get()), height: uint16(h.get()), refreshRate: uint32(rr.get()), isPreferred: p.get()))

proc fromJson*(node: JsonNode, T: typedesc[LogicalOutput]): Result[LogicalOutput, string] =
  let x = codec.getInt(node, "x")
  let y = codec.getInt(node, "y")
  let w = codec.getInt(node, "width")
  let h = codec.getInt(node, "height")
  let s = codec.getFloat(node, "scale")
  let t = codec.getField(node, "transform")
  if x.isErr or y.isErr or w.isErr or h.isErr or s.isErr or t.isErr: return err("invalid logical output")
  let tt = fromJson(t.get(), Transform)
  if tt.isErr: return err(tt.error)
  ok(LogicalOutput(x: int32(x.get()), y: int32(y.get()), width: uint32(w.get()), height: uint32(h.get()), scale: s.get(), transform: tt.get()))

proc fromJson*(node: JsonNode, T: typedesc[Output]): Result[Output, string] =
  if node.kind != JObject: return err("output must be object")
  var modes: seq[Mode] = @[]
  let modesNode = codec.getField(node, "modes")
  if modesNode.isErr or modesNode.get().kind != JArray: return err("invalid output modes")
  for m in modesNode.get().items:
    let dm = fromJson(m, Mode)
    if dm.isErr: return err(dm.error)
    modes.add(dm.get())

  var logicalOpt = none(LogicalOutput)
  let lnode = codec.getOptionalField(node, "logical")
  if lnode.isSome:
    let dl = fromJson(lnode.get(), LogicalOutput)
    if dl.isErr: return err(dl.error)
    logicalOpt = some(dl.get())

  var phy = none(tuple[w: uint32, h: uint32])
  if node.hasKey("physical_size") and node["physical_size"].kind == JObject:
    let p = node["physical_size"]
    let pw = codec.getInt(p, "w")
    let ph = codec.getInt(p, "h")
    if pw.isOk and ph.isOk:
      phy = some((w: uint32(pw.get()), h: uint32(ph.get())))

  ok(Output(
    name: codec.getStr(node, "name").get(""),
    make: codec.getStr(node, "make").get(""),
    model: codec.getStr(node, "model").get(""),
    serial: codec.getOptionalStr(node, "serial"),
    physicalSize: phy,
    modes: modes,
    currentMode: codec.getOptionalInt(node, "current_mode"),
    vrrSupported: codec.getBool(node, "vrr_supported").get(false),
    vrrEnabled: codec.getBool(node, "vrr_enabled").get(false),
    logical: logicalOpt
  ))

proc fromJson*(node: JsonNode, T: typedesc[WindowLayout]): Result[WindowLayout, string] =
  if node.kind != JObject: return err("layout must be object")

  var tile = (w: 0.0, h: 0.0)
  if node.hasKey("tile_size") and node["tile_size"].kind == JObject:
    tile = (
      w: codec.getFloat(node["tile_size"], "w").get(0.0),
      h: codec.getFloat(node["tile_size"], "h").get(0.0)
    )

  var ws = (w: 0'i32, h: 0'i32)
  if node.hasKey("window_size") and node["window_size"].kind == JObject:
    ws = (
      w: int32(codec.getInt(node["window_size"], "w").get(0)),
      h: int32(codec.getInt(node["window_size"], "h").get(0))
    )

  var off = (x: 0.0, y: 0.0)
  if node.hasKey("window_offset_in_tile") and node["window_offset_in_tile"].kind == JObject:
    off = (
      x: codec.getFloat(node["window_offset_in_tile"], "x").get(0.0),
      y: codec.getFloat(node["window_offset_in_tile"], "y").get(0.0)
    )

  var posScroll = none(tuple[col: int, win: int])
  if node.hasKey("pos_in_scrolling_layout") and node["pos_in_scrolling_layout"].kind == JObject:
    posScroll = some((
      col: codec.getInt(node["pos_in_scrolling_layout"], "col").get(0),
      win: codec.getInt(node["pos_in_scrolling_layout"], "win").get(0)
    ))

  var tilePos = none(tuple[x: float64, y: float64])
  if node.hasKey("tile_pos_in_workspace_view") and node["tile_pos_in_workspace_view"].kind == JObject:
    tilePos = some((
      x: codec.getFloat(node["tile_pos_in_workspace_view"], "x").get(0.0),
      y: codec.getFloat(node["tile_pos_in_workspace_view"], "y").get(0.0)
    ))

  ok(WindowLayout(tileSize: tile, windowSize: ws, posInScrollingLayout: posScroll,
    tilePosInWorkspaceView: tilePos, windowOffsetInTile: off))

proc fromJson*(node: JsonNode, T: typedesc[Window]): Result[Window, string] =
  if node.kind != JObject: return err("window must be object")
  let idf = codec.getUint64(node, "id")
  let l = codec.getField(node, "layout")
  if idf.isErr or l.isErr: return err("invalid window")
  let dl = fromJson(l.get(), WindowLayout)
  if dl.isErr: return err(dl.error)

  var wsId = none(WorkspaceId)
  let wsNode = codec.getOptionalField(node, "workspace_id")
  if wsNode.isSome:
    wsId = some(WorkspaceId(uint64(wsNode.get().getInt())))

  var fts = none(Timestamp)
  let tsNode = codec.getOptionalField(node, "focus_timestamp")
  if tsNode.isSome:
    let ts = fromJson(tsNode.get(), Timestamp)
    if ts.isOk: fts = some(ts.get())

  var pidOpt = none(int32)
  let p = codec.getOptionalInt(node, "pid")
  if p.isSome: pidOpt = some(int32(p.get()))

  ok(Window(
    id: WindowId(idf.get()),
    title: codec.getOptionalStr(node, "title"),
    appId: codec.getOptionalStr(node, "app_id"),
    pid: pidOpt,
    workspaceId: wsId,
    isFocused: codec.getBool(node, "is_focused").get(false),
    isFloating: codec.getBool(node, "is_floating").get(false),
    isUrgent: codec.getBool(node, "is_urgent").get(false),
    layout: dl.get(),
    focusTimestamp: fts
  ))

proc fromJson*(node: JsonNode, T: typedesc[Workspace]): Result[Workspace, string] =
  if node.kind != JObject: return err("workspace must be object")
  var active = none(WindowId)
  let aw = codec.getOptionalField(node, "active_window_id")
  if aw.isSome:
    active = some(WindowId(uint64(aw.get().getInt())))
  ok(Workspace(
    id: WorkspaceId(codec.getUint64(node, "id").get(0'u64)),
    idx: WorkspaceIdx(uint8(codec.getInt(node, "idx").get(0))),
    name: codec.getOptionalStr(node, "name"),
    output: codec.getOptionalStr(node, "output"),
    isActive: codec.getBool(node, "is_active").get(false),
    isFocused: codec.getBool(node, "is_focused").get(false),
    isUrgent: codec.getBool(node, "is_urgent").get(false),
    activeWindowId: active
  ))

proc fromJson*(node: JsonNode, T: typedesc[KeyboardLayouts]): Result[KeyboardLayouts, string] =
  if node.kind != JObject: return err("keyboard layouts must be object")
  var names: seq[string] = @[]
  let ns = codec.getField(node, "names")
  if ns.isErr or ns.get().kind != JArray: return err("names must be array")
  for it in ns.get().items:
    if it.kind == JString: names.add(it.getStr())
  ok(KeyboardLayouts(names: names, currentIdx: uint8(codec.getInt(node, "current_idx").get(0))))

proc fromJson*(node: JsonNode, T: typedesc[LayerSurface]): Result[LayerSurface, string] =
  if node.kind != JObject: return err("layer surface must be object")
  let l = fromJson(node["layer"], Layer)
  let k = fromJson(node["keyboard_interactivity"], LayerSurfaceKeyboardInteractivity)
  if l.isErr or k.isErr: return err("invalid layer surface enum")
  ok(LayerSurface(namespace: codec.getStr(node, "namespace").get(""), output: codec.getStr(node, "output").get(""), layer: l.get(), keyboardInteractivity: k.get()))

proc fromJson*(node: JsonNode, T: typedesc[Cast]): Result[Cast, string] =
  if node.kind != JObject: return err("cast must be object")
  let k = fromJson(node["kind"], CastKind)
  if k.isErr: return err(k.error)
  var pidOpt = none(int32)
  let p = codec.getOptionalInt(node, "pid")
  if p.isSome: pidOpt = some(int32(p.get()))
  ok(Cast(
    streamId: codec.getUint64(node, "stream_id").get(0'u64),
    sessionId: codec.getUint64(node, "session_id").get(0'u64),
    kind: k.get(),
    target: CastTarget(raw: if node.hasKey("target"): node["target"] else: newJNull()),
    isActive: codec.getBool(node, "is_active").get(false),
    pid: pidOpt
  ))

proc toJson*(v: WindowLayout): JsonNode =
  result = %*{
    "tile_size": %*{"w": v.tileSize.w, "h": v.tileSize.h},
    "window_size": %*{"w": v.windowSize.w, "h": v.windowSize.h},
    "window_offset_in_tile": %*{"x": v.windowOffsetInTile.x, "y": v.windowOffsetInTile.y}
  }

proc toJson*(v: Window): JsonNode =
  result = %*{
    "id": toJson(v.id),
    "title": (if v.title.isSome: %v.title.get() else: newJNull()),
    "app_id": (if v.appId.isSome: %v.appId.get() else: newJNull()),
    "workspace_id": (if v.workspaceId.isSome: toJson(v.workspaceId.get()) else: newJNull()),
    "is_focused": %v.isFocused,
    "is_floating": %v.isFloating,
    "is_urgent": %v.isUrgent,
    "layout": toJson(v.layout)
  }
