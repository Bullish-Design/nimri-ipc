## nimri_ipc/stream - Event stream client

import std/[asyncdispatch, asyncnet, json, options, times]
import results
import ./[codec, events, errors]
import ./internal/transport

export transport.NiriConnectConfig
export transport.initNiriConnectConfig

type
  NiriEventStream* = ref object
    socket*: AsyncSocket
    config*: NiriConnectConfig
    frameBuffer*: FrameBuffer
    connected*: bool

proc newEventStreamWithSocket*(socket: AsyncSocket, config = initNiriConnectConfig()): NiriEventStream =
  NiriEventStream(socket: socket, config: config, frameBuffer: initFrameBuffer(), connected: true)

proc openEventStream*(config = initNiriConnectConfig()): Future[Result[NiriEventStream, NimriIpcError]] {.async.} =
  let path = resolveSocketPath(config)
  if path.isErr: return err(path.error)
  let s = await connectSocket(path.get())
  if s.isErr: return err(s.error)

  let w = await writeLine(s.get(), "\"EventStream\"", "openEventStream")
  if w.isErr: return err(w.error)

  let line = await readLineWithTimeout(s.get(), config.commandTimeout, "openEventStream")
  if line.isErr: return err(line.error)

  try:
    let raw = parseJson(line.get())
    let rep = parseReply(raw)
    if rep.isErr:
      return err(niriError(rep.error))
    let tv = parseTaggedVariant(rep.get())
    if tv.isErr or tv.get().tag != "Handled":
      return err(protocolViolation("openEventStream", "Handled", (if tv.isOk: tv.get().tag else: "invalid"), $rep.get()))
  except JsonParsingError as e:
    return err(jsonDecodeError("openEventStream", e.msg, line.get()))

  ok(NiriEventStream(socket: s.get(), config: config, frameBuffer: initFrameBuffer(), connected: true))

proc next*(stream: NiriEventStream, timeout = initDuration(milliseconds = 0)): Future[Result[NiriEvent, NimriIpcError]] {.async.} =
  if stream.isNil or not stream.connected:
    return err(connectionClosed("nextEvent"))

  let ready = stream.frameBuffer.nextFrame()
  if ready.isSome:
    return decodeEventLine(ready.get())

  while true:
    let line = await readLineWithTimeout(stream.socket, timeout, "nextEvent")
    if line.isErr: return err(line.error)
    stream.frameBuffer.feed(line.get() & "\n")
    let f = stream.frameBuffer.nextFrame()
    if f.isSome:
      return decodeEventLine(f.get())

proc waitFor*(stream: NiriEventStream, predicate: proc(e: NiriEvent): bool, timeout: Duration): Future[Result[NiriEvent, NimriIpcError]] {.async.} =
  let start = getTime()
  while true:
    let elapsedMs = int((getTime() - start).inMilliseconds)
    let totalMs = int(timeout.inMilliseconds)
    if elapsedMs >= totalMs:
      return err(errors.timeout("waitFor", totalMs))
    let rem = initDuration(milliseconds = totalMs - elapsedMs)
    let ev = await next(stream, rem)
    if ev.isErr: return err(ev.error)
    if predicate(ev.get()):
      return ok(ev.get())

proc close*(stream: NiriEventStream) {.async.} =
  if stream.isNil or not stream.connected:
    return
  stream.connected = false
  stream.socket.close()
