# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

import ../private/backend/js
import ../private/backend/nodebuffer
import ../private/deser
import ../private/varint

import ../common
import ../builder
import ../bpath
import std/options
import sequtils


import std/jsffi


when not(defined(js)) or not(defined(nodejs)):
    {.fatal "This module is only for the JavaScript target on nodejs.".}

type JsBipfBuffer = BipfBuffer[NodeJsBuffer]

func isUint8Array(s: JsObject): bool {.importjs: "(# instanceof Uint8Array)".}
func isArray(s: JsObject): bool {.importjs: "(Array.isArray(#))".}
func isSafeInteger(s: JsObject): bool {.importjs: "(Number.isSafeInteger(#))".}
func isFinite(s: JsObject): bool {.importjs: "(Number.isFinite(#))".}
func declareSymbol(s: cstring): cstring {.importjs: "Symbol(#)".}



var bipfBufferSymbol = declareSymbol("nim_bipf_buffer")
# var BipfBufferTool {.exportc : "BipfBuffer".} = newJsObject()

func isBipfBuffer(s: JsObject): bool  =
  {.noSideEffect.}:
    result = (isNodeJsBuffer(s) and s.hasOwnProperty(bipfBufferSymbol)) or 
              (jsTypeOf(s) == "object" and isNodeJsBuffer(s.buffer) and s.buffer.hasOwnProperty(bipfBufferSymbol))
    

# BipfBufferTool.isBipfBuffer = isBipfBuffer

converter toInt32(n: JsObject): int32                  = cast[int32](n)
converter toDouble(n: JsObject): float64               = cast[float](n).float64
converter toString(n: JsObject): cstring               = cast[cstring](n)
converter toBool(n: JsObject): bool                    = cast[bool](n) 
converter toInputBuffer(n: JsObject): NodeJsBuffer     = cast[NodeJsBuffer](n)
converter toBipfBuffer(n: JsObject): BipfBuffer[NodeJsBuffer]        = 
  if isNodeJsBuffer(n):
    result = BipfBuffer[NodeJsBuffer](buffer:NodeJsBuffer(n))
  else:
    result = cast[BipfBuffer[NodeJsBuffer]](n)
converter toAtom(n: JsObject): AtomValue               = raise newException(ValueError, "Atom Value not yet implemented for JS API")  

# var valueAtomsMap = newJsAssoc[cstring, AtomValue]()
# var valueAtoms = newSeq[cstring]()

# converter toAtom(n: JsObject): AtomValue =
#   result = valueAtomsMap[n.cstring]
#   if isUndefined(result):
#     result = AtomValue(valueAtoms.len.uint32)
#     valueAtomsMap[n.cstring] = result
#     valueAtoms.add(n.cstring)


func dnKind(obj: JsObject): DynNodeKind  =
    let jsType = jsTypeOf(obj)
    if jsType == "undefined":
      result = nkUndefined
    elif jsType == "boolean":
      result = nkBool
    elif jsType == "number":
      if obj.isSafeInteger() and (obj.toInt32 >= low(int32)) and (obj.toInt32 <= high(int32)):
        result = nkInt
      elif obj.isFinite():
        result = nkDouble
      else:
        raise newException(ValueError, "Unsupported number (formely 'unknown type' error)" )
    elif jsType == "string":
      result = nkString
    elif jsType == "object":
      if isNull(obj):
        result = nkNull
      elif isUint8Array(obj):
        if isBipfBuffer(obj):
          result = nkBipfBuffer
        else:
          result = nkBuffer
      elif isArray(obj):
        result = nkArray
      else:
        result = nkMap
    else:
      raise newException(ValueError, "Unsupported type (formely 'unknown type'): " & $jsType)

template dnItems(node:JsObject): JsObject = node.items()
iterator dnPairs(node:JsObject): (cstring,JsObject) = 
  for key, value in node.pairs():
    yield (key, value.toJs())



proc addJsObject*(b: var BipfBuilder, key: sink cstring, node: sink JsObject) {.inline.} =
  addNodeWithKey(b, key, node)

proc addJsObject*(b: var BipfBuilder, node: sink JsObject) {.inline.} =
  addNode(b, node)



template markAsBipfBuffer(s: typed)  =
  {.noSideEffect.}:
    s.toJs()[bipfBufferSymbol] = true

type 
  CStringAtomDict = object of JsObject
    values: seq[cstring]
    map: JsAssoc[cstring, AtomValue]

  CStringAtomDictRef* = ref CStringAtomDict

  JsContextWithKeyDict* = object
    keyDict: CStringAtomDictRef

template inputBufferType*(ctx: JsContextWithKeyDict): typedesc = NodeJsBuffer
template outputBufferType*(ctx: JsContextWithKeyDict): typedesc = NodeJsBuffer
template allocBuffer*(ctx: JsContextWithKeyDict, size: int) : NodeJsBuffer = nodebuffer.allocUnsafe(size)

proc newKeyDict*(): CStringAtomDictRef =
  result = CStringAtomDictRef(
    values: newSeq[cstring](),
    map: newJsAssoc[cstring, AtomValue]()
  )
  ## add 2 nil values to the dict for true and false
  result.values.add(cast[cstring](jsNull))
  result.values.add(cast[cstring](jsNull))

template atomFor*(dict: CStringAtomDictRef; value: cstring): AtomValue =
  var result = dict.map[value]
  if isUndefined(result):
    result = AtomValue(dict.values.len.uint32)
    dict.map[value] = result
    dict.values.add(value)
  result

template valueFor*(dict: CStringAtomDictRef; atom: AtomValue): JsObject = dict.values[atom.uint32].toJs()



proc serialize*(obj: JsObject, maybeKeyDict: CStringAtomDictRef): JsBipfBuffer  =
  
  if isUndefined(maybeKeyDict):
    var builder = newBipfBuilder(DEFAULT_CONTEXT)
    builder.addJsObject(obj)
    result = builder.finish()
  else:
    var ctx = JsContextWithKeyDict(keyDict:maybeKeyDict)
    var builder = newBipfBuilder(ctx)
    builder.addJsObject(obj)
    result = builder.finish()
  
  markAsBipfBuffer(result.buffer)


let jsTrue {.importjs: "true", nodecl.} : JsObject
let jsFalse {.importjs: "false", nodecl.} : JsObject


type 
  DeserCtxWithoutKeyDict = distinct int
  DeserCtxWithKeyDict = object
    keyDict: CStringAtomDictRef
  DeserCtx = DeserCtxWithoutKeyDict | DeserCtxWithKeyDict

var jsObjectFactory = DeserCtxWithoutKeyDict(0)

template bufferType(ctx: DeserCtx): typedesc = NodeJsBuffer
template nodeType(ctx: DeserCtx): typedesc = JsObject

template keyFor(ctx: DeserCtxWithKeyDict; atom: AtomValue): JsObject = valueFor(ctx.keyDict, atom).toJs()

template newMap(factory: DeserCtx): JsObject = newJsObject()
template newArray(factory: DeserCtx, arr: seq[JsObject]): JsObject = arr.toJs
template setEntry(factory: DeserCtx, map: JsObject, key: cstring, value: JsObject) = map[key] = value
template setElement(factory: DeserCtx, arr: JsObject, idx: int, value: JsObject) = arr[idx] = value
template readPrefix*(buffer: NodeJsBuffer, p: var int): BipfPrefix = BipfPrefix(readVaruint32(buffer, p)) 
template readStringNode*(factory: DeserCtx, source: NodeJsBuffer, p: var int, l: int): JsObject =
  block:
    let pend = p + l
    let result = toString(source, p, pend).toJs
    p = pend
    result

template readBufferNode*(factory: DeserCtx, source: NodeJsBuffer, p: var int, l: int): JsObject =
  block:
    let pend = p + l
    let result = source.subarray(p, pend).toJs
    p = pend
    result

template readIntNode*(factory: DeserCtx, source: NodeJsBuffer, p: var int, l: int): JsObject =
  block:
    let result = source.readInt32LE(p).toJs
    p += l
    result

template readDoubleNode*(factory: DeserCtx, source: NodeJsBuffer, p: var int, l: int): JsObject =
  block:
    let result = source.readDoubleLE(p).toJs
    p += l
    result

template readAtomValue*(factory: DeserCtx, source: NodeJsBuffer, p: var int, l: int): AtomValue =
  let len = l
  var result = case len
              of 0: AtomValue(-1)
              of 1: AtomValue(source[p].uint32)
              of 2: AtomValue(source.readUInt16LE(p).uint32)
              of 3: AtomValue((source[p].uint32 shl 16) or (source[p+1].uint32 shl 8) or source[p+2].uint32)
              of 4: AtomValue(source.readUInt32LE(p))
              else:
                raise newException(ValueError, "Invalid length for Atom value (must be 0, 1, 2, 3 or 4). Got: " & $len)
  p += len
  result

template readAtomNode*(factory: DeserCtx, source: NodeJsBuffer, p: var int, l: int): JsObject =
  block:
    let result = readAtomValue(factory, source, p, l)
    case result.int:
    of -1: jsNull
    of 0: jsFalse
    of 1: jsTrue
    else: result.toJs

proc deserialize(bipf: JsBipfBuffer, maybeStartOrKeyDict: JsObject, maybeKeyDict: CStringAtomDictRef): JsObject =
  var start = 0
  if jsTypeOf(maybeStartOrKeyDict) == "number":
    start = toInt(maybeStartOrKeyDict)
    if isUndefined(maybeKeyDict):
      deserialize[DeserCtxWithoutKeyDict](jsObjectFactory, bipf, start)
    else:
      var ctx = DeserCtxWithKeyDict(keyDict: maybeKeyDict)
      deserialize[DeserCtxWithKeyDict](ctx, bipf, start)
  elif isUndefined(maybeStartOrKeyDict):
    deserialize[DeserCtxWithoutKeyDict](jsObjectFactory, bipf, start)
  else:
    var ctx = DeserCtxWithKeyDict(keyDict:CStringAtomDictRef(maybeStartOrKeyDict))
    deserialize[DeserCtxWithKeyDict](ctx, bipf, start)


## Backward compatibility with the bipf module

var lastObjectVisited: JsObject = nil
var lastBufferProduced: NodeJsBuffer

proc encodingLength(obj: JsObject): int  =
  lastBufferProduced = serialize(obj, nil).buffer
  lastObjectVisited = obj
  result = lastBufferProduced.len


proc encode(obj: JsObject, buffer: NodeJsBuffer, offset: int = 0): int =
  let offset = if isUndefined(offset): 0 else: offset

  if obj != lastObjectVisited:
    lastBufferProduced = serialize(obj, nil).buffer
    lastObjectVisited = obj

  if buffer.len - offset < lastBufferProduced.len and not isNodeJsBuffer(buffer.toJs()):
    raise newException(ValueError, "Buffer too small")
  

  var p = offset
  
  buffer.copyBuffer(lastBufferProduced, p)
  
  result = p - offset

proc allocAndEncode(obj: JsObject): NodeJsBuffer = serialize(obj, nil).buffer


proc decode(buffer: NodeJsBuffer, maybeStart: int): JsObject =
  deserialize(JsBipfBuffer(buffer: buffer), maybeStart.toJs, nil)



proc compileSimplePath(path: openArray[cstring]) : BPath[NodeJsBuffer] =
  var bufArr = newSeq[NodeJsBuffer](path.len)
  for i, p in path:
    bufArr[i] = fromCString(p)
  result = bpath.compileSimplePath(DEFAULT_CONTEXT, bufArr)


proc seekKey(buffer: NodeJsBuffer, start: int, key: JsObject): int =
  var keyBuffer = if jsTypeOf(key) == "string": nodebuffer.fromCString(key.cstring)
                  elif jsTypeOf(key) == "object" and isNodeJsBuffer(key): cast[NodeJsBuffer](key)
                  else: raise newException(ValueError, "Unsupported key type: " & $jsTypeOf(key))

  let bpath = bpath.compileSimplePath(DEFAULT_CONTEXT, [keyBuffer])


  result = JsBipfBuffer(buffer:buffer).runBPath(bpath, start)

proc seekKey2(buffer: NodeJsBuffer, start: int, key: NodeJsBuffer, keyStart: int): int =
  var pTarget = if isUndefined(keyStart): 0 else: keyStart
  let prefix = key.readPrefix(pTarget)

  assert prefix.tag == BipfTag.String, "Invalid path (formely 'seekKey2 require a string bipf'): "  & $prefix.tag  

  let bpath = bpath.compileSimplePath(DEFAULT_CONTEXT, [key.subarray(pTarget, pTarget+prefix.size)])

  result = JsBipfBuffer(buffer:buffer).runBPath(bpath, start)


var seekKeyCache = newJsAssoc[cstring, BPath[NodeJsBuffer]]()

proc seekKeyCached(buffer: NodeJsBuffer, start: int, key: cstring): int =
  if jsTypeOf(key.toJs) != "string":
    raise newException(ValueError, "Unsupported key type (formely 'seekKeyCached only supports string target'): " & $jsTypeOf(key.toJs))
  
  var bpath = seekKeyCache[key]
  if isUndefined(bpath):
    bpath = compileSimplePath([key])
    seekKeyCache[key] = bpath

  result = JsBipfBuffer(buffer:buffer).runBPath(bpath, start)


proc seekPath(buffer: NodeJsBuffer, start: int, target: NodeJsBuffer, targetStart: int): int =
  if not isNodeJsBuffer(target.toJs):
    raise newException(ValueError, "Unsupported target type (formely 'path must be encoded array'): " & $jsTypeOf(target.toJs))

  var path : seq[NodeJsBuffer] = newSeq[NodeJsBuffer]()
  var pTarget =  if isUndefined(targetStart): 0 else: targetStart
  let arrPrefix = target.readPrefix(pTarget)

  assert arrPrefix.tag == BipfTag.Array, "Unsupported target type (formely 'path must be encoded array')"

  while (pTarget < target.len):
    let prefix = target.readPrefix(pTarget)

    assert prefix.tag == BipfTag.String, "Invalid path (formely 'seekPath only supports string target'): "  & $prefix.tag  

    let size = prefix.size

    path.add(target.subarray(pTarget, pTarget+size))
    pTarget += size
    

  let bpath = bpath.compileSimplePath(DEFAULT_CONTEXT, path)


  result = JsBipfBuffer(buffer:buffer).runBPath(bpath, start)

type
  SeekFunction = proc (buffer: NodeJsBuffer, start: int): int


proc createSeekPath(path: openArray[cstring]) : SeekFunction =
  let bpath = compileSimplePath(path)

  result = proc (buffer: NodeJsBuffer, start: int): int =
    BipfBuffer[NodeJsBuffer](buffer: buffer).runBPath(bpath, start)
  
type 
  CompareFunction = proc (b1: NodeJsBuffer, b2: NodeJsBuffer): int


func compareBipfValues*(b1: NodeJsBuffer, b2: NodeJsBuffer, start1: int = 0, start2: int = 0) : int =
  assert isNodeJsBuffer(b1.toJs), "b1 must be a NodeJsBuffer"
  assert isNodeJsBuffer(b2.toJs), "b2 must be a NodeJsBuffer"
  # undefined is larger than anything
  if start1 < 0:
    if start2 < 0:
      return 0
    else:
      return 1
  elif start2 < 0:
    return -1

  var p1 = start1 
  var p2 = start2

  let prefix1 = b1.readPrefix(p1)
  let prefix2 = b2.readPrefix(p2)

  # null is smaller than anything
  if prefix1.uint32 == NULL_PREFIX.uint32:
    if prefix2.uint32 == NULL_PREFIX.uint32:
      return 0
    else:
      return -1
  elif prefix2.uint32 == NULL_PREFIX.uint32:
    return 1

  let tag1 = prefix1.tag
  let size1 = prefix1.size
  let tag2 = prefix2.tag
  let size2 = prefix2.size

  # compare number types combinations
  if tag1 == BipfTag.INT and tag2 == BipfTag.DOUBLE:
    let v1 = b1.readInt32LE(p1)
    let v2 = b2.readDoubleLE(p2)
    return float64(v1).cmp(v2)
  elif tag2 == BipfTag.INT and tag1 == BipfTag.DOUBLE:
    let v2 = b2.readInt32LE(p2)
    let v1 = b1.readDoubleLE(p1)
    return v1.cmp(float64(v2))
  
  # if not same type, compare by type
  if (tag1 != tag2):
    return tag1.int - tag2.int

  if tag1 == BipfTag.INT:
    let v1 = b1.readInt32LE(p1)
    let v2 = b2.readInt32LE(p2)
    return v1.cmp(v2)
  elif tag1 == BipfTag.DOUBLE:
    let v1 = b1.readDoubleLE(p1) # we tested yet nulls
    let v2 = b2.readDoubleLE(p2)
    return v1.cmp(v2)
  else: # make bytes comparison
    assert isNodeJsBuffer(b1.toJs), "b1 must be a NodeJsBuffer"
    assert isNodeJsBuffer(b2.toJs), "b2 must be a NodeJsBuffer : " & $jsTypeOf(b2.toJs) 

    let v1 = b1.subarray(p1, p1+size1)
    let v2 = b2.subarray(p2, p2+size2)
    return compare(v1, v2, 0, size1, 0, size2)

proc compatCompare(b1: NodeJsBuffer, start1: int, b2: NodeJsBuffer, start2: int) : int =
  compareBipfValues(b1, b2, start1, start2)


proc createCompareAt(paths: seq[seq[cstring]]) : CompareFunction =
  var bPathArray = newSeq[BPath[NodeJsBuffer]](paths.len)
  var i = 0
  for path in paths:
    bPathArray[i] = compileSimplePath(path)
    inc i
  
  result = proc (b1: NodeJsBuffer, b2: NodeJsBuffer): int =
    assert isNodeJsBuffer(b1.toJs), "b1 must be a NodeJsBuffer"
    assert isNodeJsBuffer(b2.toJs), "b2 must be a NodeJsBuffer"

    for pPath in bPathArray:
      let v1 = BipfBuffer[NodeJsBuffer](buffer: b1).runBPath(pPath, 0)
      let v2 = BipfBuffer[NodeJsBuffer](buffer: b2).runBPath(pPath, 0)


      result = compareBipfValues(b1, b2, v1, v2)
      if result != 0:
        return result
    return 0

proc slice(buffer: NodeJsBuffer, start: int): NodeJsBuffer =
  ## this function return the value buffer
  ## without the prefix
  var p = start
  let prefix = buffer.readPrefix(p)
  let size = prefix.size
  
  result = buffer.subarray(p, p+size)

proc  pluck(buffer: NodeJsBuffer, start: int): NodeJsBuffer =
  ## this function return the value buffer
  ## without the prefix
  var p = start
  let prefix = buffer.readPrefix(p)
  let size = prefix.size + (p - start)
  p = start
  
  result = buffer.subarray(p, p+size)


proc encodeIdempotent(obj: JsObject, buffer: NodeJsBuffer, offset: int = 0): int =
  result = encode(obj, buffer, offset)
  markAsBipfBuffer(result)

proc markIdempotent(buffer: NodeJsBuffer): NodeJsBuffer =
  result = buffer
  markAsBipfBuffer(result)

type 
  IterateCallback = proc (buffer: NodeJsBuffer, valuePointer: int, keyPointerOrIndex: int) : bool

proc iterate(objBuf: NodeJsBuffer, start: int, callback: IterateCallback) : int =
  var p = start
  let prefix = objBuf.readPrefix(p)
  let size = prefix.size
  let tag = prefix.tag
  let endOffset = p + size
  

  if tag == BipfTag.OBJECT:
    while p < endOffset:
      let keyPointer = p
      let keyPrefix = objBuf.readPrefix(p)
      p += keyPrefix.size
      let valuePointer = p
      let valuePrefix = objBuf.readPrefix(p)
      p += valuePrefix.size

      if callback(objBuf, valuePointer, keyPointer):
        break
    return start
  elif tag == BipfTag.ARRAY:
    var i = 0
    while p < endOffset:
      let valuePointer = p
      let valuePrefix = objBuf.readPrefix(p)
      p += valuePrefix.size

      if callback(objBuf, valuePointer, i):
        break
      inc i
    return start
  else:
    return -1

func getEncodedLength(obj: NodeJsBuffer, start: int): int =
  var p = if isUndefined(start): 0 else: start

  let prefix = obj.readPrefix(p)
  return prefix.size

func getEncodedType(obj: NodeJsBuffer, start: int): BipfTag =
  var p = if isUndefined(start): 0 else: start

  let prefix = obj.readPrefix(p)
  return prefix.tag






var typesConstants = newJsAssoc[cstring, BipfTag]()
typesConstants["object"] = BipfTag.OBJECT
typesConstants["array"] = BipfTag.ARRAY
typesConstants["string"] = BipfTag.STRING
typesConstants["buffer"] = BipfTag.BUFFER
typesConstants["int"] = BipfTag.INT
typesConstants["double"] = BipfTag.DOUBLE
typesConstants["boolnull"] = BipfTag.ATOM
typesConstants["atom"] = BipfTag.ATOM
typesConstants["extended"] = BipfTag.EXTENDED


import jsExport

#jsExportTypes:
#  NodeJsBuffer
#  JsBipfBuffer
#  CStringAtomDict
  

jsExport:
  serialize
  deserialize

  newKeyDict

  encodingLength
  encode
  allocAndEncode
  decode
  seekPath
  seekKey
  seekKey2
  seekKeyCached
  slice
  pluck
  encodeIdempotent
  markIdempotent
  getEncodedLength
  getEncodedType
  "allocAndEncodeIdempotent" = allocAndEncode
  "isIdempotent" = isBipfBuffer
  iterate
  "types" = typesConstants
  createSeekPath
  createCompareAt
  "compare" = compatCompare

