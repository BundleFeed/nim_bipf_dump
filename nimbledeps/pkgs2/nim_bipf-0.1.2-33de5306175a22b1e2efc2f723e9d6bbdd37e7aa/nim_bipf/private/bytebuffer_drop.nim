# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

import std/hashes

when defined(js):
  import jsffi
  
  type ByteBuffer* = distinct JSObject # JS Uint8Array

  type ArrayBuffer = distinct JSObject # JS ArrayBuffer
  type DataView = distinct JSObject # JS DataView


  func buffer*(a: ByteBuffer): ArrayBuffer {.importjs: "#.buffer".}
  func byteOffset*(a: ByteBuffer): int {.importjs: "#.byteOffset".}
  func byteLength*(a: ByteBuffer): int {.importjs: "#.byteLength".}
  func newDataView*(a: ArrayBuffer): DataView {.importjs: "new DataView(#)".}
  func getInt32*(a: DataView, p: int, l: bool): int32 {.importjs: "#.getInt32(#, #)".}
  func setInt32*(a: DataView, p: int, d: int32, l: bool) {.importjs: "#.setInt32(#, #, #)".}
  func getFloat64*(a: DataView, p: int, l: bool): float64 {.importjs: "#.getFloat64(#, #)".}
  func setFloat64*(a: DataView, p: int, d: float64, l: bool) {.importjs: "#.setFloat64(#, #, #)".}

  when defined(nodejs):
    func newByteBuffer*(size: int): ByteBuffer {.importjs: "Buffer.allocUnsafe(#)".}
    func newByteBuffer*(s: cstring): ByteBuffer {.importjs: "Buffer.from(#)".}
  else:
    func newByteBuffer*(size: int): ByteBuffer {.importjs: "new Uint8Array(#)".}

  func newByteBuffer(buffer: ArrayBuffer, offset: int, size: int): ByteBuffer {.importjs: "new Uint8Array(@)".}

  func len*(v:ByteBuffer): int {.importjs: "#.length".}
  func `[]=`*(v: ByteBuffer, i: int, b: byte) {.importjs: "#[#] = #".}
  func `[]`*(v: ByteBuffer, i: int): byte {.importjs: "#[#]".}
  func `$`*(v: ByteBuffer): string {.importjs: "#.toString()".}
  func `==`*(a, b: ByteBuffer): bool {.importjs: "#.equals(#)".}
  template hash*(v: ByteBuffer): Hash =
    var h : Hash = 0
    for i in 0..<v.len:
      h = h !& hash(v[i])
    !$h
    
  
  func set*(bb: ByteBuffer, s: ByteBuffer, p: int) {.importjs: "#.set(#,#);".}

  template writeBuffer*(result: ByteBuffer, s: ByteBuffer, p: var int) =
    if unlikely(s.len == 0):
      discard
    else:
      set(result, s, p)
      p+=s.len
    
  template readBuffer*(source: ByteBuffer, p: var int, l: int): ByteBuffer =
    if unlikely(l == 0):
      newByteBuffer(0)
    else:
      p+=l
      newByteBuffer(source.buffer, source.byteOffset + p-l, l)

    
  when defined(nodejs):
    func bufferWriteInt32LittleEndian*(result: ByteBuffer, i: int32, p: int) {.importjs: "#.writeInt32LE(#, #)".}

    func bufferWriteUInt16LittleEndian*(result: ByteBuffer, i: uint16, p: int) {.importjs: "#.writeUInt16LE(#, #)".}
    func bufferWriteUInt32LittleEndian*(result: ByteBuffer, i: uint32, p: int) {.importjs: "#.writeUInt32LE(#, #)".}
    

    template writeInt32LittleEndian*(result: ByteBuffer, i: int32, p: var int) =
      bufferWriteInt32LittleEndian(result, i, p)
      p+=4

    template writeUInt32LittleEndianTrim*(result: ByteBuffer, i: uint32, p: var int) =
      if i <= 255:
        result[p] = byte(i)
        p+=1
      elif i <= 65535:
        bufferWriteUInt16LittleEndian(result, i.uint16, p)
        p+=2
      elif i <= 16777215:
        result[p] = byte(i shr 16)
        result[p+1] = byte(i shr 8)
        result[p+2] = byte(i)
        p+=3
      else:
        bufferWriteUInt32LittleEndian(result, i, p)
        p+=4



    func bufferWriteFloat64LittleEndian*(result: ByteBuffer, d: float64, p: int) {.importjs: "#.writeDoubleLE(#, #)".}

    template writeFloat64LittleEndian*(result: ByteBuffer, d: float64, p: var int) =
      bufferWriteFloat64LittleEndian(result, d, p)
      p+=8

    func bufferReadInt32LittleEndian*(source: ByteBuffer, p: int): int32 {.importjs: "#.readInt32LE(#)".}

    template readInt32LittleEndian*(source: ByteBuffer, p: var int): int32 =
      block:
        let result = bufferReadInt32LittleEndian(source, p)
        p+=4
        result

    func bufferReadFloat64LittleEndian*(source: ByteBuffer, p: int): float64 {.importjs: "#.readDoubleLE(#)".}

    template readFloat64LittleEndian*(source: ByteBuffer, p: var int): float64 =
      block:
        let result = bufferReadFloat64LittleEndian(source, p)
        p+=8
        result
    #func lenUtf8*(s: NativeString): int {.importjs: "Buffer.byteLength(#)".}

    func bufferWriteUtf8*(result: ByteBuffer, s: cstring, p: int): int {.importjs: "#.write(#, #)".}

    template writeUTF8*(result: ByteBuffer, s: cstring, p: var int) =
      trace "writeUTF8(cstring) with '", $s, "'", " at ", p
      p += bufferWriteUtf8(result, s, p)
    
    func bufferWriteUTF8*(bb: ByteBuffer, s: string, p: int) {.importjs: "#.set(#,#);".}

    template writeUTF8*(result: ByteBuffer, s: string, p: var int) =
      trace "writeUTF8(string) with '", $s, "'", " at ", p
      p += s.len


    #func bufferReadUtf8*(source: ByteBuffer, p: int, pend: int): NativeString {.importjs: "#.toString('utf8', #, #)".}

    #template readUTF8*(source: ByteBuffer, p: var int, len: int): NativeString =
    # block:
    #    let result = bufferReadUtf8(source, p, p+len)
    #    p+=len
    #    result
    
    func bufferCompare(source: ByteBuffer, target: ByteBuffer, targetStart: int, targetEnd: int, sourceStart: int, sourceEnd: int): int {.importjs: "#.compare(@)".}

    template equals*(source: ByteBuffer, target: ByteBuffer, p: int): bool =
      bufferCompare(source, target, 0, target.len, p, p+target.len) == 0
      
    func compare*(source: ByteBuffer, target: ByteBuffer, targetStart: int, targetLen: int, sourceStart: int, sourceLen: int): int =
      let len = min(sourceLen, targetLen)
      result = bufferCompare(source, target, targetStart, targetStart + len, sourceStart, sourceStart + len)
      if result == 0:
        result = sourceLen - targetLen

  else:
    template writeInt32LittleEndian*(result: ByteBuffer, i: int32, p: var int) =
      newDataView(buffer(result)).setInt32(byteOffset(result) + p, i, true)
      p+=4

    template writeFloat64LittleEndian*(result: ByteBuffer, d: float64, p: var int) =
      newDataView(buffer(result)).setFloat64(byteOffset(result) + p, d, true)
      p+=8

    func readInt32LittleEndian*(source: ByteBuffer, p: var int): int32 {.inline.} =
      result =  newDataView(buffer(source)).getInt32(byteOffset(source) + p, true)
      p+=4

    func readFloat64LittleEndian*(source: ByteBuffer, p: var int): float64 {.inline.} =
      result =  newDataView(buffer(source)).getFloat64(byteOffset(source) + p, true)
      p+=8
    
    func lenUtf8*(s: cstring): int {.importjs: "new TextEncoder().encode(#).length".} # todo optimize
    template writeUTF8*(result: ByteBuffer, s: cstring, p: var int) =
      writeBuffer(result, cast[ByteBuffer]($s), p)

    template readUtf8*(source: ByteBuffer, p: var int, l: int): cstring =
      let utf8String = cast[string](readBuffer(source, p, l))
      utf8String.cstring    

else:
  import std/endians


  type ByteBuffer* = distinct seq[byte]


  template newByteBuffer*(size: int): ByteBuffer = ByteBuffer(newSeq[byte](size))
  func newByteBuffer*(s: sink string): ByteBuffer {.inline.} = ByteBuffer(cast[seq[byte]](s))
  func len*(x: ByteBuffer): int {.borrow.}
  template `[]=`*(v: ByteBuffer, i: int, b: byte) = (seq[byte](v))[i] = b
  template `[]`*(v: ByteBuffer, i: int): byte = (seq[byte](v))[i]
  template `[]`*(v: ByteBuffer, i: HSlice[system.int, system.int]): byte = (seq[byte](v))[i]
  template `$`*(v: ByteBuffer): string = $(seq[byte](v))
  template hash*(buffer: ByteBuffer): Hash = hash(seq[byte](buffer))
  template `==`*(a, b: ByteBuffer): bool = seq[byte](a) == seq[byte](b)
  
  template writeUTF8*(result: ByteBuffer, s: string, p: var int) =
    let l = s.len
    if unlikely(l == 0):
      discard
    else:
      copyMem(result[p].addr, unsafeAddr(s[0]), l)
      p+=l
  
  template writeUTF8*(result: ByteBuffer, s: cstring, p: var int) =
    let str = $s
    writeUTF8(result, str, p)

  func readUtf8*(source: ByteBuffer, p: var int, l: int): string {.noinit, inline.} =
    result = newString(l)
    if unlikely(l == 0):
      discard
    else:
      copyMem(addr(result[0]), source[p].unsafeAddr, l)
      p+=l
    
  
  template copyBuffer*(result: var ByteBuffer, s: ByteBuffer, p: var int) =
    let l = s.len
    if unlikely(l == 0):
      discard
    else:
      copyMem(result[p].addr, s[0].unsafeAddr, l)
      p+=l

  func readBuffer*(source: ByteBuffer, p: var int, l: int): ByteBuffer {.inline.} =
    if unlikely(l == 0):
      result = newByteBuffer(0)
    else:
      result = newByteBuffer(l)
      copyMem(result[0].unsafeAddr, source[p].unsafeAddr, l)
      p+=l

  template writeInt32LittleEndian*(result: ByteBuffer, i: int32, p: var int) =
    littleEndian32(cast[ptr uint32](result[p].addr), unsafeAddr i)
    p+=4

  func writeUInt32LittleEndianTrim*(result: var ByteBuffer, i: uint32, p: var int) =
    var v = i
    if i <= 255:
      result[p] = byte(v)
      p+=1
    elif i <= 65535:
      littleEndian16(cast[ptr uint16](result[p].addr), v.addr)
      p+=2
    elif i <= 16777215:
      result[p] = byte(v shr 16)
      result[p+1] = byte(v shr 8)
      result[p+2] = byte(v)
      p+=3
    else:
      let i: int = p
      littleEndian32(cast[ptr uint32](result[i].addr), v.addr)
      p+=4


  template writeFloat64LittleEndian*(result: ByteBuffer, d: float64, p: var int) =
    littleEndian64(cast[ptr uint64](result[p].addr), unsafeAddr d)
    p+=8


  func readInt32LittleEndian*(source: ByteBuffer, p: var int): int32 {.inline.} =
    littleEndian32(addr result, cast[ptr uint32](source[p]))
    p+=4
  
  func readFloat64LittleEndian*(source: ByteBuffer, p: var int): float64 {.inline.} =
    littleEndian64(addr result, cast[ptr uint64](source[p]))
    p+=8
  
  
  func compare*(source: ByteBuffer, target: ByteBuffer, targetStart: int, targetLen: int, sourceStart: int, sourceLen: int): int {.inline.} =
    result = cmpMem(source[sourceStart].unsafeAddr, target[targetStart].unsafeAddr, min(sourceLen, targetLen))
    if result == 0:
      result = sourceLen - targetLen

  func equals*(source: ByteBuffer, target: ByteBuffer, p: int): bool {.inline.} =
    if (source.len - p) < target.len:
      return false
    for i in 0..<target.len:
      if source[p+i] != target[i]:
        return false
    return true


