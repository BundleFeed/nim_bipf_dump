# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

{.push overflow_checks:off.}  
import ../common
import std/options

## Deserialization algorithm
proc deserializeMap[Ctx](ctx: var Ctx, buffer: ctx.bufferType, p: var int, size: int): ctx.nodeType
proc deserializeArray[Ctx](ctx: var Ctx, buffer: ctx.bufferType, p: var int, size: int): ctx.nodeType

template deserializeNext[Ctx](ctx: var Ctx, buffer: ctx.bufferType, p: var int): auto =
  let prefix = buffer.readPrefix(p)
  let size = prefix.size
  let tag = prefix.tag

  case tag
          of BipfTag.STRING:   ctx.readStringNode(buffer, p, size)
          of BipfTag.BUFFER:   ctx.readBufferNode(buffer, p, size)
          of BipfTag.INT:      ctx.readIntNode(buffer, p, size)
          of BipfTag.DOUBLE:   ctx.readDoubleNode(buffer, p, size)
          of BipfTag.ARRAY:    deserializeArray[Ctx](ctx, buffer, p, size)
          of BipfTag.OBJECT:   deserializeMap[Ctx](ctx, buffer, p, size)
          of BipfTag.ATOM:     ctx.readAtomNode(buffer, p, size)
          of BipfTag.EXTENDED: ctx.readBufferNode(buffer, p, size)
  

proc deserializeMap[Ctx](ctx: var Ctx, buffer: ctx.bufferType, p: var int, size: int): ctx.nodeType =
  result = ctx.newMap()
  let endOffset = p + size
  while p < endOffset:
    let prefix = buffer.readPrefix(p)
    when not compiles(ctx.keyFor(AtomValue(0))):
      assert prefix.tag == BipfTag.STRING, "Expected string, got [formely 'required type:string']: " 

      let key = ctx.readStringNode(buffer, p, prefix.size)
    else:
      let key = case prefix.tag
        of BipfTag.STRING:
          ctx.readStringNode(buffer, p, prefix.size)
        of BipfTag.ATOM:
          let atom =ctx.readAtomValue(buffer, p, prefix.size)
          if atom.int <= 1:
            raise newException(BipfValueError, "boolean is invalid key, got [formely 'required type:string']: " & $prefix.tag)
          else:
            ctx.keyFor(atom)
        else:
          raise newException(BipfValueError, "Expected string or atom, got [formely 'required type:string']: " & $prefix.tag)
    let value = deserializeNext[Ctx, BipfBuffer](ctx, buffer, p)
    ctx.setEntry(result, key, value)


proc deserializeArray[Ctx](ctx: var Ctx, buffer: ctx.bufferType, p: var int, size: int): ctx.nodeType =
  var stack = newSeq[type(result)]()
  let endOffset = p + size
  while p < endOffset:
    stack.add(deserializeNext[Ctx](ctx, buffer, p))
  return ctx.newArray(stack)



proc deserialize*[Ctx](ctx: var Ctx, bipf: BipfBuffer[ctx.bufferType], at: int = 0): ctx.nodeType {.inline.} =
  var p = at
  result = deserializeNext[Ctx](ctx, bipf.buffer, p)

{.pop.}
