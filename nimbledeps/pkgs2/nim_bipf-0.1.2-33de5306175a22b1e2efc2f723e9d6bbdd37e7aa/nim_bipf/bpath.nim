# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

import common
import private/logging

type
  BipfQueryOpCode* = enum
    MatchKey

  BipfQueryOp*[ByteBuffer] = object
    case opCode*: BipfQueryOpCode
    of MatchKey:
      prefix*: BipfPrefix
      key*: ByteBuffer
  

  BPath*[ByteBuffer] = seq[BipfQueryOp[ByteBuffer]]
  BPathRef*[ByteBuffer] = ref BPath[ByteBuffer]


func compileSimplePath*[Ctx](ctx: Ctx, path: openarray[ctx.outputBufferType]): BPath[ctx.outputBufferType] =
  result = @[]
  for key in path:
    let keyPrefix = (key.len.uint32 shl 3) or BipfTag.STRING.uint32
    result.add BipfQueryOp[ctx.outputBufferType](opCode: MatchKey, prefix: BipfPrefix(keyPrefix), key: key)

template eatChar(path: openArray[char], i: var int, c: char) =
  if i < path.len and path[i] == c:
    i.inc
  else:
    raise newException(ValueError, "Invalid JsonPath")
  
template toBuffer[Ctx](ctx: Ctx, s: string): typed = 
  var r = ctx.allocBuffer(s.len)
  var p = 0
  writeUTF8(result, c, p)
  r
#[ 
func compilePath*[Ctx](ctx: Ctx, path: openArray[char]): BPath[ctx.outputBufferType] =
  var keyBuffer = newStringOfCap(255) 
  result = @[]
  ## Path parser (sqlite json path grammar)
  
  var i = 0

  eatChar(path, i, '$')

  while i < path.len:
    let c = path[i]
    case c:
    of '.': # object key
      i.inc
      if path[i] == '"': # quoted key
        i.inc
        # the identifier may contains espaced " by \"
        keyBuffer.setLen(0)
        
        while i < path.len and path[i] != '"':
          if path[i] == '\\' and path[i + 1] == '"':
            i.inc
          keyBuffer.add path[i]
          i.inc
        
        result.add BipfQueryOp[ctx.outputBufferType](opCode: MatchKey, prefix: BipfPrefix((keyBuffer.len).uint32 shl 3 or BipfTag.STRING.uint32), key: ctx.toBuffer(keyBuffer))
        i.inc
      else:
        # unquoted key, dot can be escaped by \.
        keyBuffer.setLen(0)

        while i < path.len and path[i] != '.':
          if path[i] == '\\' and path[i + 1] == '.':
            i.inc
          keyBuffer.add path[i]
          i.inc
        
        result.add BipfQueryOp[ctx.outputBufferType](opCode: MatchKey, prefix: BipfPrefix((keyBuffer.len).uint32 shl 3 or BipfTag.STRING.uint32), key: ctx.toBuffer(keyBuffer))
    of '[': # array index
      # either an integer or the char # followed by optional negative integer
      # not yet implemented
      raise newException(ValueError, "Invalid JsonPath")
 ]#  
{.push overflowChecks: off.}


func runBPath*[ByteBuffer](bipf: BipfBuffer, path: BPath[ByteBuffer] | static BPath[ByteBuffer], pathIndex: int, start: int) : int =
  var p = start
  let op = path[pathIndex]
  case op.opCode:
    of MatchKey:
      let opPrefix = op.prefix
      let opKey = op.key

      let prefix = bipf.buffer.readPrefix(p)

      if prefix.tag != BipfTag.OBJECT: 
        return -1
      else:
        let endOffset = p + prefix.size
        while p < endOffset:  
          let prefix = bipf.buffer.readPrefix(p)
            
          if prefix == opPrefix and bipf.buffer.equals(opKey, p):
            p += prefix.size
            if pathIndex < path.high:
              return runBPath(bipf, path, pathIndex + 1, p)
            else:
              return p
          p += prefix.size
          bipf.buffer.skipNext(p)

        return -1

func runBPathRecursive*[ByteBuffer](bipf: BipfBuffer, path: BPath[ByteBuffer], start: int = 0): int =
  result = runBPath(bipf, path, 0, start)
  
  

func runBPath*[ByteBuffer](bipf: BipfBuffer, path: BPath[ByteBuffer], start: int = 0): int =
  var p = start
  for op in path:
    case op.opCode:
      of MatchKey:
        let opPrefix = op.prefix
        let opKey = op.key

        let prefix = bipf.buffer.readPrefix(p)

        if prefix.tag != BipfTag.OBJECT: 
          return -1

        let endOffset = p + prefix.size
        while p < endOffset:  
          let prefix = bipf.buffer.readPrefix(p)
            
          if prefix == opPrefix and bipf.buffer.equals(opKey, p):
            p += prefix.size
            break
          p += prefix.size
          bipf.buffer.skipNext(p)

        if p >= endOffset:
          return -1
  return p

{.pop.}






