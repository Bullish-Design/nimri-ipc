## nimri_ipc/requests - Requests and responses

import std/[json, options, tables]
import results
import ./[codec, models, actions, errors]

type
  OutputAction* = object
    raw*: JsonNode

  NiriRequestKind* = enum
    nrVersion, nrOutputs, nrWorkspaces, nrWindows, nrLayers,
    nrKeyboardLayouts, nrFocusedOutput, nrFocusedWindow,
    nrOverviewState, nrCasts,
    nrPickWindow, nrPickColor,
    nrAction,
    nrEventStream, nrReturnError,
    nrLoadConfigFile, nrOutputConfig

  NiriRequest* = object
    case kind*: NiriRequestKind
    of nrAction: action*: NiriAction
    of nrLoadConfigFile: configPath*: Option[string]
    of nrOutputConfig:
      outputName*: string
      outputAction*: OutputAction
    else: discard

  NiriResponseKind* = enum
    nresHandled, nresVersion, nresOutputs, nresWorkspaces, nresWindows,
    nresLayers, nresKeyboardLayouts, nresFocusedOutput, nresFocusedWindow,
    nresOverviewState, nresCasts, nresPickWindow, nresPickColor,
    nresUnknown

  NiriResponse* = object
    case kind*: NiriResponseKind
    of nresHandled: discard
    of nresVersion: version*: string
    of nresOutputs: outputs*: Table[string, Output]
    of nresWorkspaces: workspaces*: seq[Workspace]
    of nresWindows: windows*: seq[Window]
    of nresLayers: layers*: seq[LayerSurface]
    of nresKeyboardLayouts: keyboardLayouts*: KeyboardLayouts
    of nresFocusedOutput: focusedOutput*: Option[Output]
    of nresFocusedWindow: focusedWindow*: Option[Window]
    of nresOverviewState: isOverviewOpen*: bool
    of nresCasts: casts*: seq[Cast]
    of nresPickWindow: pickedWindow*: Option[Window]
    of nresPickColor: pickedColor*: Option[string]
    of nresUnknown:
      unknownKind*: string
      unknownRaw*: string

proc requestVersion*(): NiriRequest = NiriRequest(kind: nrVersion)
proc requestOutputs*(): NiriRequest = NiriRequest(kind: nrOutputs)
proc requestWorkspaces*(): NiriRequest = NiriRequest(kind: nrWorkspaces)
proc requestWindows*(): NiriRequest = NiriRequest(kind: nrWindows)
proc requestLayers*(): NiriRequest = NiriRequest(kind: nrLayers)
proc requestKeyboardLayouts*(): NiriRequest = NiriRequest(kind: nrKeyboardLayouts)
proc requestFocusedOutput*(): NiriRequest = NiriRequest(kind: nrFocusedOutput)
proc requestFocusedWindow*(): NiriRequest = NiriRequest(kind: nrFocusedWindow)
proc requestOverviewState*(): NiriRequest = NiriRequest(kind: nrOverviewState)
proc requestCasts*(): NiriRequest = NiriRequest(kind: nrCasts)
proc requestPickWindow*(): NiriRequest = NiriRequest(kind: nrPickWindow)
proc requestPickColor*(): NiriRequest = NiriRequest(kind: nrPickColor)
proc requestAction*(action: NiriAction): NiriRequest = NiriRequest(kind: nrAction, action: action)
proc requestEventStream*(): NiriRequest = NiriRequest(kind: nrEventStream)
proc requestLoadConfig*(path = none(string)): NiriRequest = NiriRequest(kind: nrLoadConfigFile, configPath: path)

proc toJson*(r: NiriRequest): JsonNode =
  case r.kind
  of nrVersion: encodeUnitVariant("Version")
  of nrOutputs: encodeUnitVariant("Outputs")
  of nrWorkspaces: encodeUnitVariant("Workspaces")
  of nrWindows: encodeUnitVariant("Windows")
  of nrLayers: encodeUnitVariant("Layers")
  of nrKeyboardLayouts: encodeUnitVariant("KeyboardLayouts")
  of nrFocusedOutput: encodeUnitVariant("FocusedOutput")
  of nrFocusedWindow: encodeUnitVariant("FocusedWindow")
  of nrOverviewState: encodeUnitVariant("OverviewState")
  of nrCasts: encodeUnitVariant("Casts")
  of nrPickWindow: encodeUnitVariant("PickWindow")
  of nrPickColor: encodeUnitVariant("PickColor")
  of nrAction: encodeStructVariant("Action", toJson(r.action))
  of nrEventStream: encodeUnitVariant("EventStream")
  of nrReturnError: encodeUnitVariant("ReturnError")
  of nrLoadConfigFile:
    encodeStructVariant("LoadConfigFile", %*{"path": (if r.configPath.isSome: %r.configPath.get() else: newJNull())})
  of nrOutputConfig:
    encodeStructVariant("OutputConfig", %*{"name": %r.outputName, "action": r.outputAction.raw})

proc decodeWindows(arr: JsonNode): Result[seq[Window], NimriIpcError] =
  if arr.kind != JArray: return err(protocolViolation("decodeWindows", "array", $arr.kind, $arr))
  var windowSeq: seq[Window] = @[]
  for it in arr.items:
    let w = fromJson(it, Window)
    if w.isErr: return err(jsonDecodeError("decodeWindows", w.error, $it))
    windowSeq.add(w.get())
  ok(windowSeq)

proc decodeWorkspaces(arr: JsonNode): Result[seq[Workspace], NimriIpcError] =
  if arr.kind != JArray: return err(protocolViolation("decodeWorkspaces", "array", $arr.kind, $arr))
  var workspaceSeq: seq[Workspace] = @[]
  for it in arr.items:
    let w = fromJson(it, Workspace)
    if w.isErr: return err(jsonDecodeError("decodeWorkspaces", w.error, $it))
    workspaceSeq.add(w.get())
  ok(workspaceSeq)

proc decodeResponse*(node: JsonNode): Result[NiriResponse, NimriIpcError] =
  let rep = parseReply(node)
  if rep.isErr:
    return err(niriError(rep.error))

  let tv = parseTaggedVariant(rep.get())
  if tv.isErr:
    if rep.get().kind == JString and rep.get().getStr() == "Handled":
      return ok(NiriResponse(kind: nresHandled))
    return err(protocolViolation("decodeResponse", "tagged response", $rep.get().kind, $rep.get()))

  case tv.get().tag
  of "Handled":
    ok(NiriResponse(kind: nresHandled))
  of "Version":
    if tv.get().payload.kind != JString: return err(protocolViolation("decodeResponse", "string", $tv.get().payload.kind, $tv.get().payload))
    ok(NiriResponse(kind: nresVersion, version: tv.get().payload.getStr()))
  of "Windows":
    let d = decodeWindows(tv.get().payload)
    if d.isErr: return err(d.error)
    ok(NiriResponse(kind: nresWindows, windows: d.get()))
  of "Workspaces":
    let d = decodeWorkspaces(tv.get().payload)
    if d.isErr: return err(d.error)
    ok(NiriResponse(kind: nresWorkspaces, workspaces: d.get()))
  of "Outputs":
    var t = initTable[string, Output]()
    if tv.get().payload.kind != JObject: return err(protocolViolation("decodeResponse", "object", $tv.get().payload.kind, $tv.get().payload))
    for k, v in tv.get().payload:
      let decodedOut = fromJson(v, Output)
      if decodedOut.isErr: return err(jsonDecodeError("decodeResponse", decodedOut.error, $v))
      t[k] = decodedOut.get()
    ok(NiriResponse(kind: nresOutputs, outputs: t))
  of "FocusedWindow":
    if tv.get().payload.kind == JNull:
      ok(NiriResponse(kind: nresFocusedWindow, focusedWindow: none(Window)))
    else:
      let w = fromJson(tv.get().payload, Window)
      if w.isErr: return err(jsonDecodeError("decodeResponse", w.error, $tv.get().payload))
      ok(NiriResponse(kind: nresFocusedWindow, focusedWindow: some(w.get())))
  of "FocusedOutput":
    if tv.get().payload.kind == JNull:
      ok(NiriResponse(kind: nresFocusedOutput, focusedOutput: none(Output)))
    else:
      let o = fromJson(tv.get().payload, Output)
      if o.isErr: return err(jsonDecodeError("decodeResponse", o.error, $tv.get().payload))
      ok(NiriResponse(kind: nresFocusedOutput, focusedOutput: some(o.get())))
  of "KeyboardLayouts":
    let kl = fromJson(tv.get().payload, KeyboardLayouts)
    if kl.isErr: return err(jsonDecodeError("decodeResponse", kl.error, $tv.get().payload))
    ok(NiriResponse(kind: nresKeyboardLayouts, keyboardLayouts: kl.get()))
  of "Layers":
    if tv.get().payload.kind != JArray: return err(protocolViolation("decodeResponse", "array", $tv.get().payload.kind, $tv.get().payload))
    var ls: seq[LayerSurface] = @[]
    for it in tv.get().payload.items:
      let l = fromJson(it, LayerSurface)
      if l.isErr: return err(jsonDecodeError("decodeResponse", l.error, $it))
      ls.add(l.get())
    ok(NiriResponse(kind: nresLayers, layers: ls))
  else:
    ok(NiriResponse(kind: nresUnknown, unknownKind: tv.get().tag, unknownRaw: $tv.get().payload))
