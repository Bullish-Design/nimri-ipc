import unittest
import std/[asyncdispatch, asyncnet, net, os, options, times]
import results
import ../src/nimri_ipc/[stream, events, errors]

proc tmpSockPath(name: string): string =
  "/tmp/" & name & "_" & $epochTime().int & ".sock"

proc withMockServer(path: string, handler: proc(s: AsyncSocket): Future[void] {.gcsafe, async.}): Future[void] {.async.} =
  let server = newAsyncSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
  if fileExists(path): removeFile(path)
  server.bindUnix(path)
  server.listen()
  let accepted = await server.accept()
  await handler(accepted)
  accepted.close()
  server.close()
  if fileExists(path): removeFile(path)

suite "stream tests":
  test "open stream and next event":
    let p = tmpSockPath("nimri_stream")
    proc serverHandler(s: AsyncSocket): Future[void] {.async.} =
      discard await s.recvLine()
      await s.send("{\"Ok\":\"Handled\"}\n")
      await s.send("{\"WindowClosed\":{\"id\":1}}\n")

    let serverFut = withMockServer(p, serverHandler)
    let st = waitFor(openEventStream(initNiriConnectConfig(socketPath = some(p), commandTimeout = initDuration(seconds = 2))))
    check st.isOk
    let e = waitFor(st.get().next(initDuration(seconds = 2)))
    check e.isOk
    check e.get().kind == neWindowClosed
    waitFor(st.get().close())
    waitFor(serverFut)

  test "waitFor predicate":
    let p = tmpSockPath("nimri_stream_wait")
    proc serverHandler(s: AsyncSocket): Future[void] {.async.} =
      discard await s.recvLine()
      await s.send("{\"Ok\":\"Handled\"}\n")
      await s.send("{\"WorkspacesChanged\":{\"workspaces\":[]}}\n")
      await s.send("{\"WindowFocusChanged\":{\"id\":7}}\n")

    let serverFut = withMockServer(p, serverHandler)
    let st = waitFor(openEventStream(initNiriConnectConfig(socketPath = some(p), commandTimeout = initDuration(seconds = 2))))
    check st.isOk
    let found = waitFor(st.get().waitFor(proc(e: NiriEvent): bool = e.kind == neWindowFocusChanged, initDuration(seconds = 2)))
    check found.isOk
    check found.get().kind == neWindowFocusChanged
    waitFor(st.get().close())
    waitFor(serverFut)
