# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)
   
import macros
import std/intsets
import std/packedsets


macro EMSCRIPTEN_KEEPALIVE*(someProc: untyped) =
  result = someProc
  #[
      Ident !"exportc"
      ExprColonExpr
      Ident !"codegenDecl"
      StrLit __attribute__((used)) $# $#$#
  ]#
  result.addPragma(newIdentNode("exportc"))
  # emcc mangle cpp function names. This code fix it
  # when defined(cpp):
  #   result.addPragma(newNimNode(nnkExprColonExpr).add(
  #       newIdentNode("codegenDecl"),
  #       newLit("__attribute__((used)) extern \"C\" $# $#$#")))
  # else:
  result.addPragma(newNimNode(nnkExprColonExpr).add(
      newIdentNode("codegenDecl"),
      newLit("__attribute__((used)) $# $#$#")))

type 
  Buffer* = ref object
    data: string

import ../../common
import ../../builder
import ../../serde_json
import ../../bpath
import ../../private/backend/c

{.emit: """#include <emscripten.h>""".}
{.emit: """#include <sanitizer/lsan_interface.h>""".}


proc buffer_len*(buffer: Buffer): int {.EMSCRIPTEN_KEEPALIVE.} =
  result = buffer.data.len

proc buffer_data_ptr*(buffer: Buffer): pointer {.EMSCRIPTEN_KEEPALIVE.} =
  result = buffer.data[0].addr

proc buffer_unref*(buffer: Buffer) {.EMSCRIPTEN_KEEPALIVE.} =
  #echo "Echo from Webassembly: received buffer_unref"
  GC_unref(buffer)
  #echo "Echo from Webassembly: buffer_unref done"

proc buffer_ref*(buffer: Buffer) {.EMSCRIPTEN_KEEPALIVE.} =
  #echo "Echo from Webassembly: received buffer_unref"
  GC_ref(buffer)
  #echo "Echo from Webassembly: buffer_unref done"

proc buffer_alloc*(size: int): Buffer {.EMSCRIPTEN_KEEPALIVE.} =
  #echo "Echo from Webassembly: received buffer_alloc"
  result = Buffer(data: newString(size))
  #echo "Echo from Webassembly: buffer_alloc done"

proc dump_heap*() {.EMSCRIPTEN_KEEPALIVE.} =
  #echo "Echo from Webassembly: received dump_heap"
  #echo "Echo from Webassembly: dump_heap done"
  GC_fullCollect()
  echo "--------------------------"
  echo GC_getStatistics()
  discard

proc parseJson2Bipf(json_p: ptr char, json_len: int): Buffer {.EMSCRIPTEN_KEEPALIVE.} =
  try:
    var builder = newBipfBuilder[NimContext](DEFAULT_CONTEXT)
      
    builder.addJson(cast[ptr UncheckedArray[char]](json_p).toOpenArray(0, json_len-1))

    let data = builder.finish()

    result = Buffer(data: string(data.buffer))
  except Exception as e:
    echo "Error: ", e.msg, e.getStackTrace()
  #echo "Echo from Webassembly: result ", result.data.len
  #GC_ref(result)
  #debugEcho "gc stats: ", GC_getStatistics()

var db : seq[BipfBuffer[ByteBuffer]] = @[]
var typePathIdx : seq[int] = @[]
var contactIdx : IntSet = initIntSet()


proc sizeOfDbInMemory*(): int {.EMSCRIPTEN_KEEPALIVE.} =
  result = 0
  for msg in db:
    result += msg.buffer.len

proc sizeOfIndexInMemory*(): int {.EMSCRIPTEN_KEEPALIVE.} =
  result = 0
  for i in typePathIdx:
    result += sizeof(i)

func equals(a: ByteBuffer, b: ByteBuffer | string, p: int): bool =
  if a.len - p < b.len:
    return false
  result = true
  for i in 0 ..< b.len:
    result = result and (a[p + i] == byte(b[i]))


func match(msg: ByteBuffer, value: ByteBuffer, at: int): bool =
  result = true
  for j in 0..<value.len:
    result = result and (msg[at + j] == value[j])


proc compileQuery2() : auto =   
  var path : BPath[string] = @[]
  
  for key in @["value", "content", "type"].items:
    let keyPrefix = (key.len.uint32 shl 3) or BipfTag.STRING.uint32
    path.add BipfQueryOp[string](opCode: MatchKey, prefix: BipfPrefix(keyPrefix), key: key)
  
  return path

const SearchContactBPath = compileQuery2()

proc searchTypePos[ByteBuffer](msg: BipfBuffer[ByteBuffer]) : auto =
  runBPath(msg, SearchContactBPath, 0)

const contactVal = block:
  var b = newBipfBuilder[NimContext](DEFAULT_CONTEXT)
  
  b.addString("contact")
  b.finish().buffer
  


proc addToDB*(buffer: Buffer) {.EMSCRIPTEN_KEEPALIVE.} =
  let msg = BipfBuffer[ByteBuffer](buffer: ByteBuffer(buffer.data))
  db.add(msg)
  let r = searchTypePos(msg)
  typePathIdx.add r
  if r != -1:
    if match(msg.buffer, contactVal, r):
      contactIdx.incl db.len - 1


proc searchContacts*() : int {.EMSCRIPTEN_KEEPALIVE.} =
  var count = 0
  
  for msg in db:

    let r = searchTypePos(msg)
    if r == -1:
      continue

    if match(msg.buffer, contactVal, r):
      count.inc
      if count == 100:
        break

  result = db.len

proc searchContactsWithIndex*() : int {.EMSCRIPTEN_KEEPALIVE.} =
  var count = 0
  
  for i in contactIdx:
    
    inc count
    if count == 100:
      break
#[   for i, msg in db.pairs:

    let r = typePathIdx[i]
    if r == -1:
      continue

    if match(msg.buffer, contactVal, r):
      count.inc
      if count == 100:
        break
 ]#


  result = count