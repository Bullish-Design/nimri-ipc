## nimri_ipc/errors - Error type definitions for nimri-ipc

type
  NimriIpcErrorKind* = enum
    SocketPathMissing
    SocketConnectFailed
    SocketReadFailed
    SocketWriteFailed
    ConnectionClosed
    Timeout
    JsonEncodeError
    JsonDecodeError
    ProtocolViolation
    NiriError
    ResponseMismatch
    UnsupportedValue

  NimriIpcError* = object
    kind*: NimriIpcErrorKind
    message*: string
    operation*: string
    detail*: string

proc truncateSnippet(s: string, maxLen = 200): string =
  if s.len <= maxLen:
    s
  else:
    s[0 ..< maxLen] & "..."

proc mk(kind: NimriIpcErrorKind, message: string, operation = "", detail = ""): NimriIpcError =
  NimriIpcError(kind: kind, message: message, operation: operation, detail: detail)

proc socketPathMissing*(): NimriIpcError =
  mk(SocketPathMissing, "NIRI_SOCKET not set and no socket path configured", "resolveSocketPath")

proc socketConnectFailed*(path, osError: string): NimriIpcError =
  mk(SocketConnectFailed, "failed to connect to socket", "connect", "path=" & path & ", error=" & osError)

proc socketReadFailed*(operation, osError: string): NimriIpcError =
  mk(SocketReadFailed, "failed to read from socket", operation, osError)

proc socketWriteFailed*(operation, osError: string): NimriIpcError =
  mk(SocketWriteFailed, "failed to write to socket", operation, osError)

proc connectionClosed*(operation: string): NimriIpcError =
  mk(ConnectionClosed, "connection closed", operation)

proc timeout*(operation: string, durationMs: int): NimriIpcError =
  mk(Timeout, "operation timed out", operation, $durationMs & "ms")

proc jsonEncodeError*(operation, detail: string): NimriIpcError =
  mk(JsonEncodeError, "failed to encode JSON", operation, detail)

proc jsonDecodeError*(operation, detail, snippet: string): NimriIpcError =
  mk(JsonDecodeError, "failed to decode JSON", operation, detail & "; snippet=" & truncateSnippet(snippet))

proc protocolViolation*(operation, expected, actual, snippet: string): NimriIpcError =
  mk(ProtocolViolation, "protocol violation: expected " & expected & ", got " & actual, operation,
    truncateSnippet(snippet))

proc niriError*(niriMessage: string): NimriIpcError =
  mk(NiriError, niriMessage, "reply")

proc responseMismatch*(expected, actual: string): NimriIpcError =
  mk(ResponseMismatch, "response kind mismatch", "decodeResponse", "expected=" & expected & ", actual=" & actual)

proc unsupportedValue*(field, value: string): NimriIpcError =
  mk(UnsupportedValue, "unsupported value", "decode", field & "=" & value)

proc `$`*(e: NimriIpcError): string =
  let op = if e.operation.len > 0: " op=" & e.operation else: ""
  let d = if e.detail.len > 0: " detail=" & e.detail else: ""
  $e.kind & ": " & e.message & op & d
