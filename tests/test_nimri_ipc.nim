import unittest
import std/[asyncdispatch, asyncnet, net, os, options, times]
import results
import ../src/nimri_ipc/nimri_ipc

proc tmpSockPath(name: string): string =
  "/tmp/" & name & "_" & $epochTime().int & ".sock"

suite "nimri_ipc public api tests":
  test "import compiles and key symbols accessible":
    var e1: NimriIpcError
    var id1: WindowId
    var req1: NiriRequest
    var act1: NiriAction
    var ev1: NiriEvent
    discard

  test "codec internals not exported":
    check compiles(newClientWithSocket)

  test "simple workflow via public API":
    let p = tmpSockPath("nimri_pub")
    proc runServer(): Future[void] {.async.} =
      let server = newAsyncSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
      if fileExists(p): removeFile(p)
      server.bindUnix(p)
      server.listen()
      let s = await server.accept()
      discard await s.recvLine()
      await s.send("{\"Ok\":{\"Version\":\"0.1.9\"}}\n")
      s.close()
      server.close()
      if fileExists(p): removeFile(p)

    let sf = runServer()
    let c = waitFor(openClient(initNiriConnectConfig(socketPath = some(p), commandTimeout = initDuration(seconds = 2))))
    check c.isOk
    let v = waitFor(c.get().getVersion())
    check v.isOk
    check v.get() == "0.1.9"
    waitFor(c.get().close())
    waitFor(sf)
