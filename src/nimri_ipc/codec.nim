## nimri_ipc/codec - Tagged-union JSON codec helpers

import std/[json, options, strutils]
import results

type
  TaggedVariant* = object
    tag*: string
    payload*: JsonNode
    isUnit*: bool

  FrameBuffer* = object
    buf: string
    pos: int

proc parseTaggedVariant*(node: JsonNode): Result[TaggedVariant, string] =
  case node.kind
  of JString:
    ok(TaggedVariant(tag: node.getStr(), payload: newJNull(), isUnit: true))
  of JObject:
    if node.len != 1:
      return err("expected single-key object for tagged variant, got keys=" & $node.len)
    for k, v in node:
      return ok(TaggedVariant(tag: k, payload: v, isUnit: false))
    err("unreachable")
  else:
    err("expected tagged variant as string or object, got " & $node.kind)

proc encodeUnitVariant*(tag: string): JsonNode =
  newJString(tag)

proc encodeStructVariant*(tag: string, payload: JsonNode): JsonNode =
  result = newJObject()
  result[tag] = payload

proc parseReply*(node: JsonNode): Result[JsonNode, string] =
  let parsed = parseTaggedVariant(node)
  if parsed.isErr:
    return err(parsed.error)
  let v = parsed.get()
  case v.tag
  of "Ok":
    ok(v.payload)
  of "Err":
    if v.payload.kind == JString:
      err(v.payload.getStr())
    else:
      err("Err payload must be string")
  else:
    err("expected Ok/Err reply tag, got " & v.tag)

proc getField*(node: JsonNode, field: string): Result[JsonNode, string] =
  if node.kind != JObject:
    return err("expected object while reading field '" & field & "'")
  if not node.hasKey(field):
    return err("missing required field '" & field & "'")
  ok(node[field])

proc getStr*(node: JsonNode, field: string): Result[string, string] =
  let f = getField(node, field)
  if f.isErr:
    return err(f.error)
  if f.get().kind != JString:
    return err("field '" & field & "' must be string")
  ok(f.get().getStr())

proc getInt*(node: JsonNode, field: string): Result[int, string] =
  let f = getField(node, field)
  if f.isErr:
    return err(f.error)
  if f.get().kind notin {JInt}:
    return err("field '" & field & "' must be int")
  ok(f.get().getInt())

proc getUint64*(node: JsonNode, field: string): Result[uint64, string] =
  let i = getInt(node, field)
  if i.isErr:
    return err(i.error)
  if i.get() < 0:
    return err("field '" & field & "' must be >= 0")
  ok(uint64(i.get()))

proc getFloat*(node: JsonNode, field: string): Result[float64, string] =
  let f = getField(node, field)
  if f.isErr:
    return err(f.error)
  case f.get().kind
  of JFloat:
    ok(f.get().getFloat())
  of JInt:
    ok(float64(f.get().getInt()))
  else:
    err("field '" & field & "' must be number")

proc getBool*(node: JsonNode, field: string): Result[bool, string] =
  let f = getField(node, field)
  if f.isErr:
    return err(f.error)
  if f.get().kind != JBool:
    return err("field '" & field & "' must be bool")
  ok(f.get().getBool())

proc getOptionalField*(node: JsonNode, field: string): Option[JsonNode] =
  if node.kind != JObject or not node.hasKey(field) or node[field].kind == JNull:
    return none(JsonNode)
  some(node[field])

proc getOptionalStr*(node: JsonNode, field: string): Option[string] =
  let f = getOptionalField(node, field)
  if f.isNone or f.get().kind != JString:
    return none(string)
  some(f.get().getStr())

proc getOptionalInt*(node: JsonNode, field: string): Option[int] =
  let f = getOptionalField(node, field)
  if f.isNone or f.get().kind != JInt:
    return none(int)
  some(f.get().getInt())

proc getOptionalUint64*(node: JsonNode, field: string): Option[uint64] =
  let f = getOptionalInt(node, field)
  if f.isNone or f.get() < 0:
    return none(uint64)
  some(uint64(f.get()))

proc decodeEnum*[T: enum](node: JsonNode, fallback: T): Result[T, string] =
  if node.kind != JString:
    return err("enum value must be string")
  let s = node.getStr()
  try:
    ok(parseEnum[T](s))
  except ValueError:
    ok(fallback)

proc initFrameBuffer*(): FrameBuffer =
  FrameBuffer(buf: "", pos: 0)

proc feed*(fb: var FrameBuffer, data: string) =
  fb.buf.add(data)

proc nextFrame*(fb: var FrameBuffer): Option[string] =
  while true:
    if fb.pos >= fb.buf.len:
      fb.buf.setLen(0)
      fb.pos = 0
      return none(string)

    let rel = fb.buf.find('\n', fb.pos)
    if rel < 0:
      if fb.pos > 0:
        fb.buf = fb.buf[fb.pos .. ^1]
        fb.pos = 0
      return none(string)

    let line = fb.buf[fb.pos ..< rel]
    fb.pos = rel + 1
    if line.len == 0:
      continue
    return some(line)
