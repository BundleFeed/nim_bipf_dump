# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

import jsffi
import std/asyncjs
import jsExport
import ../../private/backend/nodebuffer
import std/sugar

type
  wasm_pointer = uint
  wasm_csize = uint
  wasm_module = JsObject
  
type 
  WasmBuffer* {.shallow.} = ref object
    instance: wasm_module
    nimRef: wasm_pointer
    begin : wasm_pointer
    cached_len : int
    len: proc(): uint
    data: proc (): Uint8Array
    copyFrom: proc (source: Uint8Array)

  Uint8Array* = JsObject


let moduleImport = require("./nim_bipf_wasm.js")

func jsCallAsyncFunction(function: JsObject): Future[wasm_module] {.importjs: "#()".}

func em_malloc(instance: wasm_module, size: uint): wasm_pointer {.importjs: "#._malloc(@)".}
func em_free(instance: wasm_module, p: wasm_pointer) {.importjs: "#._free(@)".}
func em_stackSave(instance: wasm_module): wasm_pointer {.importjs: "#.stackSave()".}
func em_stackAlloc(instance: wasm_module, size: uint): wasm_pointer {.importjs: "#.stackAlloc(@)".}
func em_stackRestore(instance: wasm_module, p: wasm_pointer) {.importjs: "#.stackRestore(@)".}

func em_dumpHeap(instance: wasm_module) {.importjs: "#._dump_heap()".}

func refHolderGen(): JsObject {.importjs: "({})".}

var referenceCounter = 0
proc dumpHeap(instance: wasm_module) = 
  instance.em_dumpHeap()
  echo "referenceCounter: ", referenceCounter

func em_copyArrayToMemory(instance: wasm_module, buffer: JsObject | NodeJsBuffer, p: wasm_pointer) {.importjs: "#.HEAP8.set(@)".}

# low level buffer management
func em_buffer_len(instance: wasm_module, p: wasm_pointer): uint  {.importjs: "#._buffer_len(@)".}
func em_buffer_data_ptr(instance: wasm_module, p: wasm_pointer): uint  {.importjs: "#._buffer_data_ptr(@)".}
func em_buffer_ref(instance: wasm_module, p: wasm_pointer) {.importjs: "#._buffer_ref(@)".}
func em_buffer_unref(instance: wasm_module, p: wasm_pointer) {.importjs: "#._buffer_unref(@)".}
func em_buffer_alloc(instance: wasm_module, size: uint): wasm_pointer {.importjs: "#._buffer_alloc(@)".}



# high level buffer Api

proc dataWasmBuffer(b: WasmBuffer): Uint8Array = 
  result = b.instance.HEAP8.subarray(b.begin, b.begin + b.len())
  b.instance.em_buffer_ref(b.nimRef)
  referenceCounter += 1
  b.instance.gc_registry.register(result, b.nimRef)
proc lenWasmBuffer(b: WasmBuffer): uint = 
  if b.cached_len == -1:
    return em_buffer_len(b.instance, b.nimRef)
  result = b.cached_len.uint


func copyFrom(b: WasmBuffer, source: Uint8Array) =
  b.instance.em_copyArrayToMemory(source, b.begin)

proc wrapBuffer(instance: wasm_module, nimRef: wasm_pointer, size: int): WasmBuffer =
  let p = instance.em_buffer_data_ptr(nimRef)
  result = WasmBuffer(instance: instance, nimRef: nimRef, begin: p, cached_len: size)
  

  result.data = bindMethod(dataWasmBuffer)
  result.copyFrom = bindMethod(copyFrom)
  result.len = bindMethod(lenWasmBuffer)
  
  referenceCounter += 1
  instance.gc_registry.register(result, nimRef)

proc allocBuffer(instance: wasm_module, size: uint): WasmBuffer =
  let r = instance.em_buffer_alloc(size)
  result = wrapBuffer(instance, r, size.int)

proc toWasmBuffer*(instance: wasm_module, nimRef: wasm_pointer): WasmBuffer =
  result = wrapBuffer(instance, nimRef, -1)

func em_parseJsonToBipf(instance: wasm_module, json_p: wasm_pointer, json_l: uint): wasm_pointer {.importjs: "#._parseJson2Bipf(@)".}
func em_addToDB(instance: wasm_module, buffer: wasm_pointer) {.importjs: "#._addToDB(@)".}
func em_searchContacts(instance: wasm_module): int {.importjs: "#._searchContacts()".}
func em_searchContactsWithIndex(instance: wasm_module): int {.importjs: "#._searchContactsWithIndex()".}
func em_sizeOfDbInMemory(instance: wasm_module): int {.importjs: "#._sizeOfDbInMemory()".}
func em_sizeOfIndexInMemory(instance: wasm_module): int {.importjs: "#._sizeOfIndexInMemory()".}

proc parseJsonBufferToBipf(instance: wasm_module, buffer: NodeJsBuffer): WasmBuffer =
  let stack = instance.em_stackSave()
  let len = buffer.len.uint
  let p = instance.em_stackAlloc(len)
  instance.em_copyArrayToMemory(buffer, p)
  
  let r = instance.em_parseJsonToBipf(p, len)
  instance.em_stackRestore(stack)
  result = instance.toWasmBuffer(r)

proc parseJson2BipfFromWasmMemory(instance: wasm_module, buffer: WasmBuffer): WasmBuffer =
  let r = instance.em_parseJsonToBipf(buffer.begin, buffer.len())

  result = instance.toWasmBuffer(r)

proc loadBufferInWasmMemory(instance: wasm_module, buffer: NodeJsBuffer): WasmBuffer =
  let len = buffer.len.uint  
  result = instance.allocBuffer(len)
  result.copyFrom(Uint8Array(buffer.toJs))
  
proc loadDB(instance: wasm_module, buffers: seq[NodeJsBuffer]) =
  var pointers: seq[WasmBuffer]
  for b in buffers:
    let wb = instance.loadBufferInWasmMemory(b)
    
    instance.em_addToDB(wb.nimRef)

proc searchContacts(instance: wasm_module): int =
  result = instance.em_searchContacts()

proc searchContactsWithIndex(instance: wasm_module): int =
  result = instance.em_searchContactsWithIndex()

proc sizeOfDbInMemory(instance: wasm_module): int =
  result = instance.em_sizeOfDbInMemory()

proc sizeOfIndexInMemory(instance: wasm_module): int =
  result = instance.em_sizeOfIndexInMemory()

proc parseJson2Bipf(instance: wasm_module, json: JsObject): WasmBuffer =
  if jsTypeOf(json) == "string":
    let buffer = fromCString(cast[cstring](json))
    result = instance.parseJsonBufferToBipf(buffer)
  elif isNodeJsBuffer(json):
    result = instance.parseJsonBufferToBipf(cast[NodeJsBuffer](json))
  else:
    result = instance.parseJson2BipfFromWasmMemory(cast[WasmBuffer](json))
  
proc initRegistry(callback: proc(r: wasm_pointer)): JsObject {.importjs: "new FinalizationRegistry(#)".}

proc register(registry: JsObject, target: JsObject, value: wasm_pointer) {.importjs: "#.register(@)".}

proc loadModule*(): Future[wasm_module] {.async, exportc.} =
  let instance = await jsCallAsyncFunction(moduleImport)

  proc gcCallback(r: wasm_pointer) =
    referenceCounter -= 1
    instance.em_buffer_unref(r)

  instance.gc_registry = initRegistry(gcCallback)
  instance.parseJson2Bipf = bindMethod(parseJson2Bipf)
  instance.loadBuffer = bindMethod(loadBufferInWasmMemory)
  instance.dumpHeap = bindMethod(dumpHeap)

  instance.loadDB = bindMethod(loadDB)
  instance.searchContacts = bindMethod(searchContacts)
  instance.sizeOfDbInMemory = bindMethod(sizeOfDbInMemory)
  instance.searchContactsWithIndex = bindMethod(searchContactsWithIndex)
  instance.sizeOfIndexInMemory = bindMethod(sizeOfIndexInMemory)

  return instance


jsSingleExport: 
  loadModule
