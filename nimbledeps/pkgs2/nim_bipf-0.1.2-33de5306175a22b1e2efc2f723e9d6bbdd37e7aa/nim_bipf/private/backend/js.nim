# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

when not defined(js):
    {.fatal: "This module is for the JavaScript backend.".}

import jsffi
import nodebuffer
import ../../common

when defined(nodejs):
  func lenUtf8*(s: cstring): int {.importjs: "Buffer.byteLength(#)".}
else:
  func lenUtf8*(s: cstring): int {.importjs: "(new TextEncoder().encode(#)).length".}

type
    JsContext* = distinct int

const DEFAULT_CONTEXT* = JsContext(0)

template inputBufferType*(ctx: JsContext): typedesc = NodeJsBuffer
template outputBufferType*(ctx: JsContext): typedesc = NodeJsBuffer


template allocBuffer*(ctx: JsContext, size: int) : NodeJsBuffer = nodebuffer.allocUnsafe(size)

template copyBuffer*(result: NodeJsBuffer, s: NodeJsBuffer, p: var int) =
  let l = s.len
  if unlikely(l == 0):
    discard
  else:
    result.writeBuffer(s, p)
    p+=l

template writeInt32LittleEndian*(result: NodeJsBuffer, i: int32, p: var int) =
  result.writeInt32LE(i, p)
  p+=4

func writeUInt32LittleEndianTrim*(result: var NodeJsBuffer, i: uint32, p: var int) =
  var v = i
  if i <= 255:
    result[p] = byte(v)
    p+=1
  elif i <= 65535:
    result.writeUInt16LE(i.uint16, p)
    p+=2
  elif i <= 16777215:
    result[p] = byte(v shr 16)
    result[p+1] = byte(v shr 8)
    result[p+2] = byte(v)
    p+=3
  else:
    result.writeUInt32LE(i.uint32, p)
    p+=4


template writeFloat64LittleEndian*(result: NodeJsBuffer, d: float64, p: var int) =
  result.writeDoubleLE(d, p)
  p+=8


template writeUTF8*(result: NodeJsBuffer, s: cstring, p: var int) =
  p += writeString(result, s, p)
    
template writeUTF8*(result: NodeJsBuffer, s: string, p: var int) =
  copyBuffer(result, cast[NodeJsBuffer](s), p)


template equals*(source: NodeJsBuffer, target: NodeJsBuffer, p: int): bool =
  nodebuffer.compare(source, target, 0, target.len, p, p+target.len) == 0
      
