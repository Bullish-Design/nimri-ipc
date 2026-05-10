import unittest
import std/[asyncdispatch, asyncnet, net, os, options, tables, times]
import results
import ../src/nimri_ipc/[client, requests, actions, models, errors]

proc tmpSockPath(name: string): string =
  "/tmp/" & name & "_" & $epochTime().int & ".sock"

proc withMockServer(path: string, handler: proc(s: AsyncSocket): Future[void] {.gcsafe, async.}): Future[void] {.async.} =
  let server = newAsyncSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
  if fileExists(path): removeFile(path)
  server.bindUnix(path)
  server.listen()
  let clientFut = server.accept()
  let accepted = await clientFut
  await handler(accepted)
  accepted.close()
  server.close()
  if fileExists(path): removeFile(path)

suite "client tests":
  test "socket path resolution":
    check resolveSocketPath(initNiriConnectConfig(socketPath = some("/tmp/test.sock"))).get() == "/tmp/test.sock"

  test "missing socket path error":
    let old = getEnv("NIRI_SOCKET")
    putEnv("NIRI_SOCKET", "")
    let r = resolveSocketPath(initNiriConnectConfig())
    check r.isErr
    check r.error.kind == SocketPathMissing
    putEnv("NIRI_SOCKET", old)

  test "send version request and decode":
    let p = tmpSockPath("nimri_client")
    proc serverHandler(s: AsyncSocket): Future[void] {.async.} =
      discard await s.recvLine()
      await s.send("{\"Ok\":{\"Version\":\"0.1.9\"}}\n")

    let serverFut = withMockServer(p, serverHandler)
    let c = waitFor(openClient(initNiriConnectConfig(socketPath = some(p), commandTimeout = initDuration(seconds = 2))))
    check c.isOk
    let v = waitFor(c.get().send(requestVersion()))
    check v.isOk
    check v.get().kind == nresVersion
    check v.get().version == "0.1.9"
    waitFor(c.get().close())
    waitFor(serverFut)

  test "doAction handled":
    let p = tmpSockPath("nimri_action")
    proc serverHandler(s: AsyncSocket): Future[void] {.async.} =
      discard await s.recvLine()
      await s.send("{\"Ok\":\"Handled\"}\n")

    let serverFut = withMockServer(p, serverHandler)
    let c = waitFor(openClient(initNiriConnectConfig(socketPath = some(p), commandTimeout = initDuration(seconds = 2))))
    check c.isOk
    let r = waitFor(c.get().doAction(actions.quit()))
    check r.isOk
    waitFor(c.get().close())
    waitFor(serverFut)
