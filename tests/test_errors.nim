import unittest
import std/strutils
import ../src/nimri_ipc/errors

suite "errors tests":
  test "each error kind has a working constructor":
    let es = @[
      socketPathMissing(),
      socketConnectFailed("/tmp/niri.sock", "boom"),
      socketReadFailed("send", "read failed"),
      socketWriteFailed("send", "write failed"),
      connectionClosed("next"),
      timeout("send", 100),
      jsonEncodeError("send", "bad"),
      jsonDecodeError("recv", "bad", "{}"),
      protocolViolation("send", "Ok", "Err", "{\"Err\":\"x\"}"),
      niriError("unknown request"),
      responseMismatch("Windows", "Version"),
      unsupportedValue("transform", "Future")
    ]
    check es.len == ord(high(NimriIpcErrorKind)) + 1
    for e in es:
      check e.message.len > 0

  test "$ produces readable output":
    let s = $socketConnectFailed("/tmp/x", "denied")
    check "SocketConnectFailed" in s
    check "failed to connect" in s

  test "snippet truncation":
    let longSnippet = "a".repeat(300)
    let e = jsonDecodeError("op", "detail", longSnippet)
    check e.detail.len <= 220
    let shortE = jsonDecodeError("op", "detail", "abc")
    check "abc" in shortE.detail

  test "kind enum is exhaustive":
    var count = 0
    for _ in NimriIpcErrorKind:
      inc count
    check count == 12
