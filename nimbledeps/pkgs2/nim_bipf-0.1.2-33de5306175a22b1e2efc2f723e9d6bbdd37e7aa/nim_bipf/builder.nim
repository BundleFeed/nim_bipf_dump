# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

import common
import private/varint
import private/logging
import std/typetraits

import std/json
import tables

type

  StackValueTag = enum
    svtSTRING   = 0, # (000) // utf8 encoded string
    svtBUFFER   = 1, # (001) // raw binary buffer
    svtINT      = 2, # (010) // little endian 32 bit integer
    svtDOUBLE   = 3, # (011) // little endian 64 bit float
    svtARRAY    = 4, # (100) // sequence of any other value
    svtOBJECT   = 5, # (101) // sequence of alternating bipf encoded key and value
    svtATOM = 6, # (110) // 1 = true, 0 = false, no value means null, rest is for apps
    svtEXTENDED = 7 # (111)  // custom type. Specific type should be indicated by varint at start of buffer

    svtBIPF_BUFFER,
    svtCSTRING,
    svtNULL

  StackValue[InputBuffer] = object
    encodedSize : int
    case tag: StackValueTag
    of svtSTRING:
      str: string
    of svtCSTRING:
      cstr: cstring
    of svtBUFFER:
      buf: InputBuffer
    of svtBIPF_BUFFER:
      bipf: BipfBuffer[InputBuffer]
    of svtINT:
      i: int32
    of svtDOUBLE:
      d: float64
    of svtATOM:
      b: AtomValue
    of svtEXTENDED:
      ext: InputBuffer
    of svtARRAY, svtOBJECT:
      size: int
    of svtNULL:
      discard

  BuilderCtx =  concept ctx
    ctx.inputBufferType is typedesc

  BipfBuilderObj[Ctx: BuilderCtx; I; O] = object
    stack    : seq[StackValue[I]]
    pointers : seq[int]
    ctx*     : Ctx
  
  BipfBuilder*[Ctx: BuilderCtx; I; O] = ref BipfBuilderObj[Ctx, I, O]


type
  DynNodeKind* = enum
      nkUndefined,
      nkNull, 
      nkBool, 
      nkInt, 
      nkDouble, 
      nkString, 
      nkBuffer,
      nkBipfBuffer, 
      nkArray, 
      nkMap,
      nkAtom
  
  MapDynNodeKey* = concept n

  BaseDynNode* = concept n
    n.dnKind is DynNodeKind

  ArrayDynNode* = concept n, v
    #for v in n.dnItems:
    #  v is BaseDynNode

  MapDynNode* = concept n, e
    #for e in n.dnPairs:
    #  e is (MapDynNodeKey, BaseDynNode)

  DynNode* {.explain.} = concept n
      n is BaseDynNode
      n is ArrayDynNode
      n is MapDynNode

  NULLTYPE = distinct int

const NULL = NULLTYPE(0)


template tagLen(v: int): int =
  assert v >= 0 and v <= high(int32), "Value out of range:" & $v
  
  let u = v.uint32 shl 3
  lenVaruint32(u)

  

template toStackValue(value: typed, StackValueImpl: typedesc[StackValue]): StackValue =
  when typeof(value) is string:
    StackValueImpl(tag: svtSTRING, str: value, encodedSize: value.len)    
  elif typeof(value) is cstring:
    StackValueImpl(tag: svtCSTRING, cstr: value, encodedSize: lenUtf8(value))
  elif typeof(value) is int32:
    StackValueImpl(tag: svtINT, i: value, encodedSize: 4)
  elif typeof(value) is float64:
    StackValueImpl(tag: svtDOUBLE, d: value, encodedSize: 8)
  elif value is NULLTYPE:
    StackValueImpl(tag: svtNULL, encodedSize: 0)
  elif typeof(value) is AtomValue:
    StackValueImpl(tag: svtATOM, b: value, encodedSize: encodingSize(value))
  elif (typeof(value) is StackValueTag):
    when value == svtARRAY or value == svtOBJECT:
      StackValueImpl(tag: value, size: 0, encodedSize: 0) ## size is set when the array/map is closed
  elif (typeof(value) is BipfBuffer):
    StackValueImpl(tag: svtBIPF_BUFFER, bipf: value, encodedSize: len(value))
  elif typeof(value) is StackValueImpl:
    value
  elif typeof(value) is InputBuffer:
    StackValueImpl(tag: svtBUFFER, buf: value, encodedSize: len(value))
  else:
    raise newException(BipfValueError, "Unsupported type: " & $typeof(value))



template addValueToStack(b: BipfBuilder, value: typed) =
  var v = toStackValue(value, elementType(b.stack))

  if unlikely(b.pointers.len == 0):
    if unlikely(b.stack.len > 0):
      raise newException(BipfValueError, "Cannot add value at root when root is not empty")
    when typeof(value) is StackValueTag:
      when (value == svtOBJECT or value == svtARRAY):
        b.pointers.add(b.stack.len)
    b.stack.add(move(v))
  else:
    let p = b.pointers[^1]
  
    if b.stack[p].tag == svtARRAY:
      b.stack[p].size += 1
      var added = v.encodedSize
      when typeof(value) is StackValueTag:
        when (value == svtOBJECT or value == svtARRAY):
          b.pointers.add(b.stack.len)
        else:
          {.fatal: "Unreachable".}
      elif not (typeof(value) is BipfBuffer):
        added += tagLen(v.encodedSize)
      b.stack[p].encodedSize += added
      b.stack.add(move(v))
    else:
      raise newException(BipfValueError, "Cannot add a value in a map without a key")

template addKeyedValueToStack(b: BipfBuilder, key: cstring | string | AtomValue, value: typed) =
  if unlikely(b.pointers.len == 0):
    raise newException(BipfValueError, "Cannot add value with a key at root")
  else:
    let p = b.pointers[^1]
    
    if b.stack[p].tag == svtOBJECT:
      b.stack[p].size += 1
      
      var k = toStackValue(key, elementType(b.stack))
      var v = toStackValue(value, elementType(b.stack))

      var added = k.encodedSize + v.encodedSize + tagLen(k.encodedSize)
      b.stack.add(move(k))

      when typeof(value) is StackValueTag:
        when value == svtOBJECT or value == svtARRAY:
          b.pointers.add(b.stack.len)
        else:
          {.fatal: "Unreachable".}
      elif not (typeof(value) is BipfBuffer):
        added += tagLen(v.encodedSize)

      b.stack[p].encodedSize += added
      b.stack.add(move(v))
    else:
      raise newException(BipfValueError, "Cannot add a value with a key in an array")


func newBipfBuilder*[Ctx: BuilderCtx](ctx: Ctx): BipfBuilder[Ctx, ctx.inputBufferType, ctx.outputBufferType] =
  ## Creates a new BipfWriter.
  result = BipfBuilder[Ctx, ctx.inputBufferType, ctx.outputBufferType](ctx: ctx)

func startMap*(b: var BipfBuilder)  {.inline.} =
  ## Starts a new map at root or in an array.
  addValueToStack(b, svtOBJECT)

func startMap*(b: var BipfBuilder, key: sink string | cstring | AtomValue)  {.inline.} =
  ## Starts a new map in a map.
  addKeyedValueToStack(b, key, svtOBJECT)

func startArray*(b: var BipfBuilder) {.inline.} =
  ## Starts a new array.
  addValueToStack(b, svtARRAY)

func startArray*(b: var BipfBuilder, key: sink string | cstring | AtomValue) {.inline.}  =
  ## Starts a new array in a map.
  addKeyedValueToStack(b, key, svtARRAY)

func addInt*(b: var BipfBuilder, i: sink int32) {.inline.} =
  ## Adds an integer to the current array.
  addValueToStack(b, i)

func addDouble*(b: var BipfBuilder, d: sink float64)  {.inline.} =
  ## Adds a double to the current array.
  addValueToStack(b, d)

func addString*(b: var BipfBuilder, s: sink string | cstring | AtomValue)  {.inline.} =
  ## Adds a NativeString to the current array.
  addValueToStack(b, s)

func addBuffer*[InputBuffer](b: var BipfBuilder, buff: InputBuffer)  {.inline.} =
  ## Adds a buffer to the current array.
  addValueToStack(b, buff)

func addBipfBuffer*(b: var BipfBuilder, buff: sink BipfBuffer)  {.inline.} =
  ## Adds a buffer to the current array.
  addValueToStack(b, buff)

func addAtom*(b: var BipfBuilder, v: sink AtomValue) {.inline.} =
  ## Adds a atom to the current array.
  addValueToStack(b, v)

func addBool*(b: var BipfBuilder, v: sink bool) {.inline.} =
  ## Adds a boolean to the current array.
  addValueToStack(b, if v: TRUE else: FALSE)

func addNull*(b: var BipfBuilder)  {.inline.} =
  ## Adds a null to the current array.
  addValueToStack(b, NULL)

func addExtended*[InputBuffer](b: var BipfBuilder, ext: InputBuffer)  {.inline.} =
  ## Adds an extended value to the current array.
  addValueToStack(b, StackValue(tag:svtEXTENDED, ext: ext))

func addInt*(b: var BipfBuilder, k: sink string | cstring | AtomValue, i: sink int32)  {.inline.} =
  ## Adds an integer to the current map.
  addKeyedValueToStack(b, k, i)

func addDouble*(b: var BipfBuilder, k: sink string | cstring | AtomValue, d: sink float64)  {.inline.} =
  ## Adds a double to the current map.
  addKeyedValueToStack(b, k, d)

func addString*(b: var BipfBuilder, k: sink string | cstring | AtomValue, s: sink string | cstring)  {.inline.} =
  ## Adds a NativeString to the current map.
  addKeyedValueToStack(b, k, s)

func addBuffer*[InputBuffer](b: var BipfBuilder, k: sink string | cstring | AtomValue, buf: InputBuffer)  {.inline.} =
  ## Adds a buffer to the current map.
  addKeyedValueToStack(b, k, buf)

func addBipfBuffer*(b: var BipfBuilder, k: sink string | cstring | AtomValue, buf: sink BipfBuffer)  {.inline.} =
  ## Adds a buffer to the current map.
  addKeyedValueToStack(b, k, buf)

func addBool*(b: var BipfBuilder, k: sink string | cstring | AtomValue, v: sink bool)  {.inline.} =
  ## Adds a boolean to the current map.
  addKeyedValueToStack(b, k, if v: TRUE else: FALSE)

func addAtom*(b: var BipfBuilder, k: sink string | cstring | AtomValue, v: sink AtomValue)  {.inline.} =
  ## Adds a boolean to the current map.
  addKeyedValueToStack(b, k, v)

func addNull*(b: var BipfBuilder, k: sink string | cstring | AtomValue)  {.inline.} =
  ## Adds a null to the current map.
  addKeyedValueToStack(b, k, NULL)

func addExtended*[InputBuffer](b: var BipfBuilder, k: sink string | cstring | AtomValue, ext: InputBuffer)  {.inline.} =
  ## Adds an extended value to the current map.
  addKeyedValueToStack(b, k, StackValue(tag:svtEXTENDED, ext: ext))

template endBlock(b: var BipfBuilder, blockTag: static StackValueTag) =

  if unlikely(b.pointers.len == 0):
    raise newException(BipfValueError, "Cannot end " & $blockTag & " before starting it")
  else:
    let p = b.pointers.pop()

    if b.stack[p].tag != blockTag:
      raise newException(BipfValueError, "Cannot end " & $blockTag & " before starting it")
    
    if (b.pointers.len > 0): # if we are not at root, update the size of the parent block
      let parentP = b.pointers[^1]
      let pEncodedSize = b.stack[p].encodedSize
      b.stack[parentP].encodedSize += pEncodedSize + tagLen(pEncodedSize)


func endArray*(b: var BipfBuilder)  {.inline.} =
  ## Ends the current array.
  endBlock(b, svtARRAY)

func endMap*(b: var BipfBuilder)  {.inline.} =
  ## Ends the current map.
  endBlock(b, svtOBJECT)



proc addNodeWithKey*[N:DynNode, K:MapDynNodeKey](builder: var BipfBuilder, key: sink K, obj: sink N)

proc addNode*[N:DynNode](builder: var BipfBuilder, obj: sink N) =
  let nodeKind = obj.dnKind
  case nodeKind
  of nkUndefined:
    discard
  of nkNull:
    builder.addNull()
  of nkBool:
    builder.addBool(obj.toBool)
  of nkInt:
    builder.addInt(obj.toInt32)
  of nkDouble:
    builder.addDouble(obj.toDouble)
  of nkString:
    builder.addString(obj.toString)
  of nkBuffer:
    builder.addBuffer(obj.toInputBuffer)
  of nkArray:
    builder.startArray()
    for value in obj.dnItems:
      addNode(builder, value)
    builder.endArray()
  of nkMap:
    builder.startMap()
    for key, value in obj.dnPairs:
      #when KD is NoopKeyDict:
        addNodeWithKey(builder, key, value)
      #else:
      #  let atom : AtomValue = atomFor(keyDict,key)
      #  addNodeWithKey(builder, atom, value, keyDict)
    builder.endMap()
  of nkBipfBuffer:
    builder.addBipfBuffer(obj.toBipfBuffer)
  of nkAtom:
    builder.addAtom(obj)
  
proc addNodeWithKey*[N:DynNode, K:MapDynNodeKey](builder: var BipfBuilder, key: sink K, obj: sink N) =
  let nodeKind = obj.dnKind

  case nodeKind
  of nkUndefined:
    discard
  of nkNull:
    builder.addNull(key)
  of nkBool:
    builder.addBool(key, obj.toBool)
  of nkInt:
    builder.addInt(key, obj.toInt32)
  of nkDouble:
    builder.addDouble(key, obj.toDouble)
  of nkString:
    builder.addString(key, obj.toString)
  of nkBuffer:
    builder.addBuffer(key, obj.toInputBuffer)
  of nkArray:
    builder.startArray(key)
    for value in obj.dnItems:
      addNode(builder, value)
    builder.endArray()
  of nkMap:
    builder.startMap(key)
    for key, value in obj.dnPairs:
      #when KD is NoopKeyDict:
        addNodeWithKey(builder, key, value)
      #else:
      #  let atom : AtomValue = keyDict.atomFor(key)
      #  addNodeWithKey(builder, atom, value, keyDict)
    builder.endMap()
  of nkBipfBuffer:
    builder.addBipfBuffer(key, obj.toBipfBuffer)
  of nkAtom:
    builder.addAtom(key, obj.toAtom)

func encodingSize*(b: var BipfBuilder): int =
  ## Returns the size of the current bipf document.
  if b.stack.len == 0:
    raise newException(BipfValueError, "Cannot get encoding size before adding any value")
  if b.pointers.len > 0:
    raise newException(BipfValueError, "Cannot get encoding size before ending all arrays and maps")

  result = b.stack[0].encodedSize + tagLen(b.stack[0].encodedSize)

const mapTagCode : array[StackValueTag, uint32] =
  [
    svtSTRING.uint32, 
    svtBUFFER.uint32, 
    svtINT.uint32, 
    svtDOUBLE.uint32, 
    svtARRAY.uint32, 
    svtOBJECT.uint32, 
    svtATOM.uint32,
    svtEXTENDED.uint32, 
    
    svtBUFFER.uint32, 
    svtSTRING.uint32,
    svtATOM.uint32
  ]



func finish*[Ctx: BuilderCtx, InputBuffer, OutputBuffer](b: var BipfBuilder[Ctx, InputBuffer, OutputBuffer]) : BipfBuffer[OutputBuffer] =
  result.buffer = b.ctx.allocBuffer(b.encodingSize)
  ## Finishes the current bipf document and returns the result.
  var p = 0
  for sv in b.stack:
    if unlikely(sv.tag == svtBIPF_BUFFER):
      result.buffer.copyBuffer(sv.bipf.buffer, p)
    else:
      let tagCode = mapTagCode[sv.tag]
      let tag = tagCode.uint32 + sv.encodedSize.uint32 shl 3
      writeVaruint32(result.buffer, tag, p)
      case sv.tag:
        of svtOBJECT, svtARRAY:
          discard
        of svtINT:
          result.buffer.writeInt32LittleEndian(sv.i, p)
        of svtDOUBLE:
          result.buffer.writeFloat64LittleEndian(sv.d, p)
        of svtATOM:
          result.buffer.writeUInt32LittleEndianTrim(uint32(sv.b), p)
        of svtNULL:
          discard
        of svtSTRING:
          result.buffer.writeUtf8(sv.str, p)
        of svtCSTRING:
          result.buffer.writeUtf8(sv.cstr, p)
        of svtEXTENDED:
          result.buffer.copyBuffer(sv.ext, p)
        of svtBUFFER:
          result.buffer.copyBuffer(sv.buf, p)
        of svtBIPF_BUFFER:
          discard

