## nimri_ipc/internal/transport - shared socket helpers

import std/[asyncdispatch, asyncnet, net, options, os, times]
import results
import ../errors

const NiriSocketEnv* = "NIRI_SOCKET"

type
  NiriConnectConfig* = object
    socketPath*: Option[string]
    commandTimeout*: Duration

proc initNiriConnectConfig*(socketPath = none(string), commandTimeout = initDuration(seconds = 5)): NiriConnectConfig =
  NiriConnectConfig(socketPath: socketPath, commandTimeout: commandTimeout)

proc resolveSocketPath*(config: NiriConnectConfig): Result[string, NimriIpcError] =
  if config.socketPath.isSome and config.socketPath.get().len > 0:
    return ok(config.socketPath.get())
  let envPath = getEnv(NiriSocketEnv)
  if envPath.len > 0:
    return ok(envPath)
  err(socketPathMissing())

proc connectSocket*(path: string): Future[Result[AsyncSocket, NimriIpcError]] {.async.} =
  try:
    let s = newAsyncSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
    await s.connectUnix(path)
    return ok(s)
  except CatchableError as e:
    return err(socketConnectFailed(path, e.msg))

proc readLineWithTimeout*(socket: AsyncSocket, timeout: Duration, operation = "readLine"): Future[Result[string, NimriIpcError]] {.async.} =
  let tms = int(timeout.inMilliseconds)
  try:
    if tms <= 0:
      let line = await socket.recvLine()
      if line.len == 0:
        return err(connectionClosed(operation))
      return ok(line)

    let fut = socket.recvLine()
    if await withTimeout(fut, tms):
      let line = fut.read()
      if line.len == 0:
        return err(connectionClosed(operation))
      return ok(line)
    return err(timeout(operation, tms))
  except CatchableError as e:
    return err(socketReadFailed(operation, e.msg))

proc writeLine*(socket: AsyncSocket, line: string, operation = "writeLine"): Future[Result[void, NimriIpcError]] {.async.} =
  try:
    await socket.send(line & "\n")
    return ok()
  except CatchableError as e:
    return err(socketWriteFailed(operation, e.msg))
