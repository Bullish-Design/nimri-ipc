import unittest
import std/[json, options]
import results
import ../src/nimri_ipc/codec

suite "codec tests":
  test "decode unit variant from bare string":
    let v = parseTaggedVariant(parseJson("\"FocusedWindow\""))
    check v.isOk
    check v.get().tag == "FocusedWindow"
    check v.get().isUnit
    check v.get().payload.kind == JNull

  test "decode struct variant from single-key object":
    let v = parseTaggedVariant(parseJson("{\"Windows\": []}"))
    check v.isOk
    check v.get().tag == "Windows"
    check v.get().payload.kind == JArray

  test "decode nested struct variant":
    let v = parseTaggedVariant(parseJson("{\"Action\": {\"CloseWindow\": {\"id\": null}}}"))
    check v.isOk
    check v.get().tag == "Action"
    check v.get().payload.kind == JObject
    check v.get().payload.hasKey("CloseWindow")

  test "decode newtype variant":
    let v = parseTaggedVariant(parseJson("{\"SetFixed\": 42}"))
    check v.isOk
    check v.get().payload.kind == JInt

  test "error on invalid tagged variants":
    check parseTaggedVariant(parseJson("{}")).isErr
    check parseTaggedVariant(parseJson("{\"A\":1,\"B\":2}")).isErr
    check parseTaggedVariant(parseJson("42")).isErr
    check parseTaggedVariant(parseJson("[1,2]")).isErr
    check parseTaggedVariant(parseJson("null")).isErr

  test "encode unit and struct":
    check encodeUnitVariant("Quit") == parseJson("\"Quit\"")
    check encodeStructVariant("Windows", parseJson("[]")) == parseJson("{\"Windows\":[]}")

  test "reply parsing":
    let ok1 = parseReply(parseJson("{\"Ok\": {\"Windows\": []}}"))
    check ok1.isOk
    check ok1.get().hasKey("Windows")
    let ok2 = parseReply(parseJson("{\"Ok\": \"Handled\"}"))
    check ok2.isOk
    check ok2.get().kind == JString
    let er = parseReply(parseJson("{\"Err\": \"Unknown request\"}"))
    check er.isErr
    check er.error == "Unknown request"
    check parseReply(parseJson("{\"Something\":1}")).isErr

  test "field extraction":
    let n = parseJson("{\"name\":\"eDP-1\",\"value\":42,\"ok\":true,\"future\":99}")
    check codec.getStr(n, "name").get() == "eDP-1"
    check codec.getStr(n, "missing").isErr
    check codec.getStr(parseJson("{\"name\":42}"), "name").isErr
    check codec.getOptionalStr(n, "name").get() == "eDP-1"
    check codec.getOptionalStr(n, "missing").isNone
    check codec.getOptionalStr(parseJson("{\"name\":null}"), "name").isNone
    check codec.getUint64(parseJson("{\"u\":184467}"), "u").get() == uint64(184467)
    check codec.getBool(parseJson("{\"b\":true}"), "b").get() == true
    check codec.getBool(parseJson("{\"b\":false}"), "b").get() == false

  test "enum decode with unknown tolerance":
    type TestEnum = enum teA, teB, teUnknown
    check decodeEnum[TestEnum](parseJson("\"teA\""), teUnknown).get() == teA
    check decodeEnum[TestEnum](parseJson("\"teNeverHeardOfThis\""), teUnknown).get() == teUnknown
    check decodeEnum[TestEnum](parseJson("42"), teUnknown).isErr

  test "frame buffer":
    var fb = initFrameBuffer()
    fb.feed("{\"event\": 1}\n")
    check fb.nextFrame().get() == "{\"event\": 1}"
    check fb.nextFrame().isNone

    fb.feed("{\"event\": ")
    check fb.nextFrame().isNone
    fb.feed("1}\n")
    check fb.nextFrame().get() == "{\"event\": 1}"

    fb.feed("{\"a\": 1}\n{\"b\": 2}\n{\"c\": 3}\n")
    check fb.nextFrame().get() == "{\"a\": 1}"
    check fb.nextFrame().get() == "{\"b\": 2}"
    check fb.nextFrame().get() == "{\"c\": 3}"
    check fb.nextFrame().isNone

    fb.feed("{\"a\": 1}\n{\"b\":")
    check fb.nextFrame().get() == "{\"a\": 1}"
    check fb.nextFrame().isNone
    fb.feed(" 2}\n")
    check fb.nextFrame().get() == "{\"b\": 2}"

    fb.feed("\n\n{\"a\": 1}\n\n")
    check fb.nextFrame().get() == "{\"a\": 1}"
    check fb.nextFrame().isNone

    fb.feed("{\"title\": \"hello\\\\nworld\"}\n")
    check fb.nextFrame().get() == "{\"title\": \"hello\\\\nworld\"}"
