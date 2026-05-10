## nimri_ipc/client - Command IPC client

import std/[asyncdispatch, asyncnet, json, options, tables]
import results
import ./[requests, actions, models, errors]
import ./internal/transport

export transport.NiriConnectConfig
export transport.initNiriConnectConfig
export transport.resolveSocketPath
export transport.NiriSocketEnv

type
  NiriClient* = ref object
    socket*: AsyncSocket
    config*: NiriConnectConfig
    connected*: bool

proc newClientWithSocket*(socket: AsyncSocket, config = initNiriConnectConfig()): NiriClient =
  NiriClient(socket: socket, config: config, connected: true)

proc openClient*(config = initNiriConnectConfig()): Future[Result[NiriClient, NimriIpcError]] {.async.} =
  let path = resolveSocketPath(config)
  if path.isErr: return err(path.error)
  let s = await connectSocket(path.get())
  if s.isErr: return err(s.error)
  ok(NiriClient(socket: s.get(), config: config, connected: true))

proc send*(client: NiriClient, request: NiriRequest): Future[Result[NiriResponse, NimriIpcError]] {.async.} =
  if client.isNil or not client.connected:
    return err(connectionClosed("send"))

  let payload = $toJson(request)
  let w = await writeLine(client.socket, payload, "send")
  if w.isErr: return err(w.error)

  let line = await readLineWithTimeout(client.socket, client.config.commandTimeout, "send")
  if line.isErr: return err(line.error)

  try:
    let n = parseJson(line.get())
    decodeResponse(n)
  except JsonParsingError as e:
    err(jsonDecodeError("send", e.msg, line.get()))

proc expectKind[T](resp: NiriResponse, expected: NiriResponseKind, extract: proc(r: NiriResponse): T): Result[T, NimriIpcError] =
  if resp.kind != expected:
    return err(responseMismatch($expected, $resp.kind))
  ok(extract(resp))

proc getWindows*(client: NiriClient): Future[Result[seq[Window], NimriIpcError]] {.async.} =
  let r = await send(client, requestWindows())
  if r.isErr: return err(r.error)
  expectKind[seq[Window]](r.get(), nresWindows, proc(x: NiriResponse): seq[Window] = x.windows)

proc getWorkspaces*(client: NiriClient): Future[Result[seq[Workspace], NimriIpcError]] {.async.} =
  let r = await send(client, requestWorkspaces())
  if r.isErr: return err(r.error)
  expectKind[seq[Workspace]](r.get(), nresWorkspaces, proc(x: NiriResponse): seq[Workspace] = x.workspaces)

proc getOutputs*(client: NiriClient): Future[Result[Table[string, Output], NimriIpcError]] {.async.} =
  let r = await send(client, requestOutputs())
  if r.isErr: return err(r.error)
  expectKind[Table[string, Output]](r.get(), nresOutputs, proc(x: NiriResponse): Table[string, Output] = x.outputs)

proc getFocusedWindow*(client: NiriClient): Future[Result[Option[Window], NimriIpcError]] {.async.} =
  let r = await send(client, requestFocusedWindow())
  if r.isErr: return err(r.error)
  expectKind[Option[Window]](r.get(), nresFocusedWindow, proc(x: NiriResponse): Option[Window] = x.focusedWindow)

proc getFocusedOutput*(client: NiriClient): Future[Result[Option[Output], NimriIpcError]] {.async.} =
  let r = await send(client, requestFocusedOutput())
  if r.isErr: return err(r.error)
  expectKind[Option[Output]](r.get(), nresFocusedOutput, proc(x: NiriResponse): Option[Output] = x.focusedOutput)

proc getVersion*(client: NiriClient): Future[Result[string, NimriIpcError]] {.async.} =
  let r = await send(client, requestVersion())
  if r.isErr: return err(r.error)
  expectKind[string](r.get(), nresVersion, proc(x: NiriResponse): string = x.version)

proc doAction*(client: NiriClient, action: NiriAction): Future[Result[void, NimriIpcError]] {.async.} =
  let r = await send(client, requestAction(action))
  if r.isErr: return err(r.error)
  if r.get().kind != nresHandled:
    return err(responseMismatch("nresHandled", $r.get().kind))
  ok()

proc close*(client: NiriClient) {.async.} =
  if client.isNil or not client.connected:
    return
  client.connected = false
  client.socket.close()
