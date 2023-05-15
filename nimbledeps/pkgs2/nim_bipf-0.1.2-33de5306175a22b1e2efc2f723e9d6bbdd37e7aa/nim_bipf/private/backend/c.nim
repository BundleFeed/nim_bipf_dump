# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

when defined(js):
  {.fatal: "This module is not designed to be used with the JavaScript backend.".}

import std/endians

template lenUTF8*(s: cstring): int = s.len


type
    NimContext* = distinct int
    ByteBuffer* = distinct string

const DEFAULT_CONTEXT* = NimContext(0)

template inputBufferType*(ctx: NimContext): typedesc = ByteBuffer
template outputBufferType*(ctx: NimContext): typedesc = ByteBuffer

## ByteBuffer API

template allocBuffer*(ctx: NimContext, size: int): ByteBuffer = ByteBuffer(newString(size))
func len*(x: ByteBuffer): int {.borrow.}
template `[]=`*(v: var ByteBuffer, i: int, b: byte) = 
  string(v)[i] = char(b)
template `[]`*(v: ByteBuffer, i: int): byte = 
  string(v)[i].byte


template writeUTF8*(result: ByteBuffer, s: cstring, p: var int) =
  let str = $s
  let l = str.len
  for i in 0..<l:
    result[p+i] = byte(str[i])
  p+=l

template writeUTF8*(result: ByteBuffer, s: string, p: var int) =
  let str = s
  let l = str.len
  for i in 0..<l:
    result[p+i] = byte(str[i])
  p+=l

template copyBuffer*(result: var ByteBuffer, s: ByteBuffer, p: var int) =
  let l = s.len
  for i in 0..<l:
    result[p+i] = s[i]
  p+=l

template writeInt32LittleEndian*(result: ByteBuffer, i: int32, p: var int) =
  littleEndian32(cast[ptr uint32](string(result)[p].addr), unsafeAddr i)
  p+=4

func writeUInt32LittleEndianTrim*(result: var ByteBuffer, i: uint32, p: var int) =
  var v = i
  if i <= 255:
    result[p] = byte(v)
    p+=1
  elif i <= 65535:
    littleEndian16(cast[ptr uint16](string(result)[p].addr), v.addr)
    p+=2
  elif i <= 16777215:
    result[p] = byte(v shr 16)
    result[p+1] = byte(v shr 8)
    result[p+2] = byte(v)
    p+=3
  else:
    let i: int = p
    littleEndian32(cast[ptr uint32](string(result)[i].addr), v.addr)
    p+=4


template writeFloat64LittleEndian*(result: ByteBuffer, d: float64, p: var int) =
  littleEndian64(cast[ptr uint64](string(result)[p].addr), unsafeAddr d)
  p+=8

