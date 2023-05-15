# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

import node_binding
import std/endians
import std/logging

var consoleLog = newConsoleLogger(levelThreshold=lvlAll)
addHandler(consoleLog)

import ../../common
import ../../builder
import ../../serde_json
import ../../private/backend/c
import ../../private/deser
import ../../private/varint
import ../../private/logging as traceLogging
import ../../bpath

# Napi helpers for encoding Bipf


converter toInt32(n: napi_value): int32             {.inline.} = n.getInt32()
converter toDouble(n: napi_value): float64          {.inline.} = n.getFloat64()
converter toString(n: napi_value): string           {.inline.} = $n.getStr()
converter toBool*(n: napi_value): bool              {.inline.} = n.getBool()
converter toInputBuffer(n: napi_value): ByteBuffer              {.inline.} = raise newException(ValueError, "not implemented")
converter toAtom(n: napi_value): AtomValue                      {.inline.} = raise newException(ValueError, "not implemented")
converter toBipfBuffer(n: napi_value): BipfBuffer[ByteBuffer]   {.inline.} = raise newException(ValueError, "not implemented")





template dnItems(n: napi_value): napi_value = n.items

iterator dnPairs(n: napi_value): (string, napi_value) =
  for key in n.getAllPropertyNames():
    let kStr = key.getStr
    yield (kStr, n.getPropertyUnsafe(key))

proc dnKind(obj: napi_value): DynNodeKind {.inline.} =
  block:
    let kind = obj.kind
    case kind
    of napi_undefined: result = nkUndefined
    of napi_null: result = nkNull
    of napi_boolean: result = nkBool
    of napi_number: 
      let longValue = obj.getInt64()
      if longValue == low(int64):
        raise newException(ValueError, "non finite number")
      else:
        result = nkDouble
        if longValue >= low(int32) and longValue <= high(int32):
          let doubleValue = obj.getFloat64()
          if float64(longValue) == doubleValue:
            result = nkInt
    of napi_string: result = nkString
    of napi_object: 
      if isTypedArray(obj):
        let (arrType, _, _, _, _) = getTypedArrayInfo(obj)

        if arrType == napi_uint8_array:
          result = nkBuffer
        else:
          raise newException(ValueError, "unsupported typed array type:" & $arrType)
      elif isArray(obj):
        result =  nkArray
      else:
        result =  nkMap
    of napi_bigint: result =  nkDouble
    of napi_symbol: result =  nkString

    else: raise newException(ValueError, "unsupported kind:" & $kind)
    
    
proc addNapiValue*(b: var BipfBuilder, key: sink string, node: sink napi_value) {.inline.} =
  addNodeWithKey(b, key, node)

proc addNapiValue*(b: var BipfBuilder, node: sink napi_value) {.inline.} =
  addNode(b, node)

# Napi helper for decoding Bipf

type 
  NapiDeserCtx = napi_env
template bufferType(ctx: NapiDeserCtx): typedesc = NapiBuffer
template nodeType(ctx: NapiDeserCtx): typedesc = napi_value
  

template newMap(factory: NapiDeserCtx): napi_value = factory.createObject()
template newArray(factory: NapiDeserCtx, arr: sink seq[napi_value]): napi_value = factory.create(arr)
template setEntry(factory: NapiDeserCtx, map: napi_value, key: napi_value, value: napi_value) = factory.setProperty(map, key, value)
template setElement(factory: NapiDeserCtx, arr: napi_value, idx: int, value: napi_value) = factory.setElement(arr, idx.uint32, value)

template readPrefix*(buffer: NapiBuffer, p: var int): BipfPrefix = BipfPrefix(readVaruint32(buffer, p))    
template readPrefix*(buffer: openArray[byte], p: var int): BipfPrefix = BipfPrefix(readVaruint32(buffer, p))    

template readStringNode*(factory: NapiDeserCtx, source: NapiBuffer, p: var int, l: int): napi_value =
  let start = p
  p += l
  factory.createString(source.view(start, l))

template readBufferNode*(factory: NapiDeserCtx, source: NapiBuffer, p: var int, l: int): napi_value =
  let start = p
  p += l
  factory.createBuffer(source.view(start, l))

template readIntNode*(factory: NapiDeserCtx, source: NapiBuffer, p: var int, l: int): napi_value =
  let pInt = source.address(p)
  var i : int32
  littleEndian32(addr i, cast[ptr uint32](pInt))
  p += l
  factory.create(i)

template readDoubleNode*(factory: NapiDeserCtx, source: NapiBuffer, p: var int, l: int): napi_value =
  let pDouble = source.address(p)
  var d : float64
  littleEndian64(addr d, cast[ptr float64](pDouble))
  p += l
  factory.create(d)

template readAtomNode*(factory: NapiDeserCtx, source: NapiBuffer, p: var int, l: int): napi_value =
  if (l == 0):
    factory.getNull()
  elif (l == 1):
    let pByte = source.address(p)
    inc p
    case cast[ptr byte](pByte)[]
    of 0: factory.create(false)
    of 1: factory.create(true)
    else: raise newException(ValueError, "invalid bool null node (formelly 'invalid boolnull, length must = 1')")
  else:
    raise newException(ValueError, "invalid bool null node (formelly 'invalid boolnull, length must = 1')")

func equals(a: ByteBuffer | NapiBuffer, b: string | ByteBuffer, p: int): bool =
  if a.len - p < b.len:
    return false
  for i in 0 ..< b.len:
    if a[p + i] != byte(b[i]):
      return false
  return true

  
proc deserialize(factory: var NapiDeserCtx, buffer: NapiBuffer, start: int): napi_value =
  deserialize[NapiDeserCtx](factory, BipfBuffer[NapiBuffer](buffer: buffer), start)



proc compileQuery2() : auto =   
  var path : BPath[string] = @[]
  
  for key in @["value", "content", "type"].items:
    let keyPrefix = (key.len.uint32 shl 3) or BipfTag.STRING.uint32
    path.add BipfQueryOp[string](opCode: MatchKey, prefix: BipfPrefix(keyPrefix), key: key)
  
  return path

const SearchContactBPath = compileQuery2()

proc searchTypePos(msg: BipfBuffer[ByteBuffer]) : auto =
  runBPath(msg, SearchContactBPath, 0)

var db : seq[BipfBuffer[ByteBuffer]] = @[]

func match(msg: ByteBuffer, value: BipfBuffer, at: int): bool =
  result = true
  for j in 0..<value.len:
    if msg[at + j] != value.buffer[j]:
      result = false
      break


init proc(exports: Module) =
  exports.registerFn(1, "hello"):
    let toGreet = args[0].getStr; # Getting the first and only argument as a string
    echo "Hello " & toGreet

  exports.registerFn(1, "serialize"):
    try:
      let node = args[0]
      var b = newBipfBuilder[NimContext](DEFAULT_CONTEXT)
      b.addNapiValue(node)
      let size = b.encodingSize()
      
      var bipf = b.finish()

      var sharedBuffer = SharedBuffer(data: newSeq[byte](size))
      copyMem(sharedBuffer.data[0].addr, string(bipf.buffer)[0].addr, size)

      return napiCreateSharedBuffer(sharedBuffer)
    except Exception as e:
      error "error in serialize:", e.msg, e.getStackTrace() 
      napiThrowError(e)

  exports.registerFn(2, "deserialize"):
    try:
      let buffer = args[0].getBuffer()
      
      let start = if args.len > 1:
                    let kind = args[1].kind
                    if kind == napi_undefined: 0 else: args[1].getInt32()
                  else: 0

      var jsObjectFactory = `env$`
      return jsObjectFactory.deserialize(buffer, start)
    except Exception as e:
      napiThrowError(e)
  
  exports.registerFn(1, "parseJson2Bipf"):
    try:
      assert args.len == 1

      var builder = newBipfBuilder[NimContext](DEFAULT_CONTEXT)
      if args[0].kind == napi_string:                    
        builder.addJson(args[0].getStr)
      elif isBuffer(args[0]):
        let input = args[0].getBuffer()
        var x: ptr UncheckedArray[char] = cast[ptr UncheckedArray[char]](input.data)
        builder.addJson(x.toOpenArray(0, input.len - 1))
      else:
        raise newException(ValueError, "invalid input type")
    
      
      let size = builder.encodingSize()
      var bipf = builder.finish()

      var sharedBuffer = SharedBuffer(data: newSeq[byte](size))
      copyMem(sharedBuffer.data[0].addr, string(bipf.buffer)[0].addr, size)


      return napiCreateSharedBuffer(sharedBuffer)
    except Exception as e:
      napiThrowError(e)


  exports.registerFn(1, "compileSimpleBPath"):
    try:
      assert args.len == 1
      var path = newSeqOfCap[DEFAULT_CONTEXT.outputBufferType](5)
      
      for e in args[0].items:
        let str = e.getStr
        var b = DEFAULT_CONTEXT.allocBuffer(str.len)
        var p = 0
        b.writeUTF8(e, p)
        path.add b

      let compiled = compileSimplePath(DEFAULT_CONTEXT, path)
      var r = new BPathRef[DEFAULT_CONTEXT.outputBufferType]
      r[] = compiled
      
      return napiCreateRef(r)
    except CatchableError as e:
      echo e.msg, e.getStackTrace()
      napiThrowError(e)

  exports.registerFn(2, "runBPath"):
    try:
      assert args.len == 2 or args.len == 3
      let buffer = args[0].getBuffer()
      var path : BPathRef[string]
      args[1].getRef(path)
      let start = if args.len == 3: args[2].getInt32() else: 0

      let r = runBPath(BipfBuffer[NapiBuffer](buffer: buffer), path[], start)      
      return napiCreate(r)
    
    except Exception as e:
      napiThrowError(e)
      
  exports.registerFn(1, "loadDB"):
    try:
      assert args.len == 1

      let arrLen = args[0].len
      db = newSeq[BipfBuffer[ByteBuffer]](arrLen)
      for i in 0 ..< arrLen:
        let b = args[0].getElement(i).getBuffer()
        var stored = allocBuffer(DEFAULT_CONTEXT, b.len)
        for i in 0 ..< b.len:
          stored[i] = b[i]

        db[i] =  BipfBuffer[ByteBuffer](buffer: stored)
    
    except Exception as e:
      napiThrowError(e)
      
  exports.registerFn(1, "searchContacts"):
    try:
      var b = newBipfBuilder[NimContext](DEFAULT_CONTEXT)
      b.addString("contact")
      let contactVal = b.finish()

      var count = 0
      
      for msg in db:

        let r = searchTypePos(msg)
        if r == -1:
          continue

        if match(msg.buffer, contactVal, r):
          count.inc
          if count == 100:
            break

      return napiCreate(count)

    except Exception as e:
      napiThrowError(e)



    
    
