import macros

import
  jsNativeApiTypes,
  jsNativeApi,
  nodeApi,
  utils

export jsNativeApiTypes, jsNativeApi, nodeApi

type NapiStatusError = object of CatchableError

var `env$`*: napi_env = nil
##Global environment variable; state maintained by various hooks; used internally


proc assessStatus*(status: NapiStatus) {.raises: [NapiStatusError].} =
  ##Asserts that a call returns correctly;
  if status != napi_ok:
    raise newException(NapiStatusError, "NAPI call returned non-zero status (" & $status & ": " & $NapiStatus(status) & ")")



type Module* = ref object
  val*: napi_value
  env*: napi_env
  descriptors: seq[NapiPropertyDescriptor]


proc newNodeValue*(val: napi_value, env: napi_env): Module =
  ##Used internally, disregard
  Module(val: val, env: env, descriptors: @[])

proc kind(env: napi_env, val: napi_value): NapiValueType =
  assessStatus ( napi_typeof(env, val, addr result) )



proc create*(env: napi_env, n: bool): napi_value {.inline.} =
  assessStatus (napi_get_boolean(env, n, addr result))

proc create*(env: napi_env, n: int32): napi_value {.inline.} =
  assessStatus ( napi_create_int32(env, n, addr result) )

proc create*(env: napi_env, n: int64): napi_value {.inline.} =
  assessStatus ( napi_create_int64(env, n, addr result) )

proc create*(env: napi_env, n: uint32): napi_value {.inline.} =
  assessStatus ( napi_create_uint32(env, n, addr result) )

proc create*(env: napi_env, n: uint64): napi_value {.inline.} =
  assessStatus ( napi_create_uint64(env, n, addr result) )

proc create*(env: napi_env, n: float64): napi_value {.inline.} =
  assessStatus ( napi_create_double(env, n, addr result) )

proc create*(env: napi_env, s: string): napi_value {.inline.} =
  assessStatus ( napi_create_string_utf8(env, s, s.len.csize_t, addr result) )

proc create*(env: napi_env, p: openarray[(string, napi_value)]): napi_value {.inline.} =
  assessStatus napi_create_object(env, addr result)
  for name, val in items(p):
    assessStatus napi_set_named_property(env, result, cstring(name), val)

proc createObject*(env: napi_env): napi_value {.inline.} =
  assessStatus napi_create_object(env, addr result)


proc setProperty*(env: napi_env, obj: napi_value, key: string, value: napi_value) {.inline.} =
  assessStatus napi_set_named_property(env, obj, cstring(key), value)

proc setProperty*(env: napi_env, obj: napi_value, key: napi_value, value: napi_value) {.inline.} =
  assessStatus napi_set_property(env, obj, key, value)


proc create*(env: napi_env, a: openarray[napi_value]): napi_value {.inline.} =
  assessStatus( napi_create_array_with_length(env, a.len.csize_t, addr result) )
  for i, elem in a.enumerate: assessStatus napi_set_element(env, result, i.uint32, a[i])

proc create*(env: napi_env, a: seq[napi_value]): napi_value {.inline.} =
  assessStatus( napi_create_array_with_length(env, a.len.csize_t, addr result) )
  for i, elem in a.enumerate: assessStatus napi_set_element(env, result, i.uint32, a[i])

proc createArray*(env: napi_env): napi_value {.inline.} =
  assessStatus( napi_create_array(env, addr result) )

proc setElement*(env: napi_env, a: napi_value, i: uint32, v: napi_value) {.inline.} =
  assessStatus napi_set_element(env, a, i, v)

proc create[T: int | uint | string](env: napi_env, a: openarray[T]): napi_value =
  var elements = newSeq[napi_value]()
  for elem in a: elements.add(env.create(elem))
  env.create(elements)


proc create[T: int | uint | string](env: napi_env, a: openarray[(string, T)]): napi_value =
  var properties = newSeq[(string, napi_value)]()
  for prop in a: properties.add((prop[0], create(prop[1])))
  env.create(a)

proc createBuffer(env: napi_env, a: seq[byte]): napi_value {.inline.} =
  let len = a.len.csize_t
  assessStatus napi_create_buffer_copy(env, len, unsafeAddr a[0], nil, addr result)


proc freeRef[T](environment: napi_env, finalize_data, finalize_hint: pointer) {.cdecl.} =
  var reference = cast[ref T](finalize_hint)

  GC_unref(reference)

proc createRef*[T](env: napi_env, reference: ref T): napi_value {.inline.} =
  GC_ref(reference)

  assessStatus napi_create_external(env, cast[pointer](reference), freeRef[reference.type], nil, addr result)


type
  SharedBuffer* = ref object
    data: seq[byte]


      
proc freeSharedBuffer(environment: napi_env, finalize_data, finalize_hint: pointer) {.cdecl.} =
  var reference = cast[SharedBuffer](finalize_hint)
  #echo "freeing : " & $reference.id
  GC_unref(reference)


proc createSharedBuffer(env: napi_env, reference: SharedBuffer): napi_value {.inline.} =
  
  #inc refId
  GC_ref(reference)

  #echo "lock reference" & $reference.id
  let buffer: pointer = addr reference.data[0]
  let len = reference.data.len.csize_t
  let hint : pointer = cast[pointer](reference)
  let cb : napi_finalize = freeSharedBuffer

  assessStatus napi_create_external_buffer(env, len, buffer, cb, hint, addr result)



proc createFn*(env: napi_env, fname: string, cb: napi_callback): napi_value =
  assessStatus ( napi_create_function(env, fname, fname.len.csize_t, cb, nil, addr result) )

proc create(env: napi_env, v: napi_value): napi_value = v


proc create*[T](n: Module, t: T): napi_value {.inline.} =
  n.env.create(t)

proc createTypedArray*[T](n: Module, t: T): napi_value {.inline.} =
  n.env.createTypedArray(t)

proc createSharedTypedArray*[T](n: Module, t: T): napi_value {.inline.} =
  n.env.createTypedArray(t)

proc kind*(val: napi_value): NapiValueType {.inline.}=
  kind(`env$`, val)

proc getInt64*(n: napi_value): int64 {.inline.} =
  ##Retrieves value from node; raises exception on failure
  assessStatus napi_get_value_int64(`env$`, n, addr result)

proc getInt64*(n: napi_value, default: int64): int64 {.inline.} =
  ##Retrieves value from node; returns default on failure
  try: assessStatus napi_get_value_int64(`env$`, n, addr result)
  except: result = default


proc getInt32*(n: napi_value): int32 {.inline.} =
  ##Retrieves value from node; raises exception on failure
  assessStatus napi_get_value_int32(`env$`, n, addr result)

proc getInt32*(n: napi_value, default: int32): int32 {.inline.} =
  ##Retrieves value from node; returns default on failure
  try: assessStatus napi_get_value_int32(`env$`, n, addr result)
  except: result = default

type NapiBuffer* = object
  data*: pointer
  private_len*: csize_t

template len*(x: NapiBuffer): int = x.private_len.int

template `[]`*(v: NapiBuffer, i: int): byte = 
  # TODO: check bounds
  cast[ptr byte]((cast[uint](v.data) + i.uint))[]

template toOpenArrayByte*(v: NapiBuffer): openArray[byte] =
  cast[ptr UncheckedArray[byte]](v.data).toOpenArray(0, int(v.private_len - 1))
  

template address*(x: NapiBuffer, i: int): pointer = 
  # todo: check bounds
  cast[pointer](cast[uint](x.data) + i.uint)

template view*(x: NapiBuffer, start:int, len: int): NapiBuffer = 
  # TODO: check bounds
  NapiBuffer(
    data: cast[ptr byte]((cast[uint](x.data) + start.uint)),
    private_len: len.csize_t
  )

func createString*(env: napi_env, x: NapiBuffer): napi_value {.inline.} =
  assessStatus napi_create_string_utf8(env, cast[cstring](x.data), x.len.csize_t, addr result)

func createBuffer*(env: napi_env, x: NapiBuffer): napi_value {.inline.} =
  let len = x.len.csize_t
  assessStatus napi_get_null(env, addr result)
  assessStatus napi_create_buffer_copy(env, len, x.data, nil, addr result)

func toString*(x: NapiBuffer): string {.inline.} =
  result = newString(x.len)
  if unlikely(x.len == 0):
    discard
  else:
    copyMem(addr(result[0]), x.data, x.len)

proc getBuffer*(n: napi_value): NapiBuffer {.inline.} =
  ##Retrieves value from node; raises exception on failure
  assessStatus napi_get_buffer_info(`env$`, n, addr result.data, addr result.private_len)

proc getRef*[T](n: napi_value, reference: var T) {.inline.} =
  ##Retrieves value from node; raises exception on failure
  var p : pointer

  assert n.kind == napi_external, "Expected external value but got " & $n.kind & " instead"

  assessStatus napi_get_value_external(`env$`, n, addr p)
  reference = cast[T](p)

template getInt*(n: napi_value): int =
  ##Retrieves value from node based on bitness of architecture; raises exception on failure
  when sizeof(int) == 8:
    int(n.getInt64())
  else:
    int(n.getInt32())

template getInt*(n: napi_value, default: int): int =
  ##Retrieves value from node based on bitness of architecture; returns default on failure
  when sizeof(int) == 8:
    int(n.getInt64(default))
  else:
    int(n.getInt32(default))

proc getFloat64*(n: napi_value): float64 {.inline.} =
  ##Retrieves value from node; raises exception on failure
  assessStatus napi_get_value_double(`env$`, n, addr result)

proc getBool*(n: napi_value): bool {.inline.} =
  ##Retrieves value from node; raises exception on failure
  assessStatus napi_get_value_bool(`env$`, n, addr result)

proc getBool*(n: napi_value, default: bool): bool {.inline.} =
  ##Retrieves value from node; returns default on failure
  try: assessStatus napi_get_value_bool(`env$`, n, addr result)
  except: result = default

proc getStr*(n: napi_value): string {.inline.} =
  var bufSize: csize_t
  assessStatus napi_get_value_string_utf8(`env$`, n, cast[cstring](nil), cast[csize_t](nil), addr bufSize)
  result = newString(bufSize)
  if unlikely(bufSize == 0):
    discard
  else:
    assessStatus napi_get_value_string_utf8(`env$`, n, addr result[0], bufSize+1, addr bufSize)

proc getStr*(n: napi_value, default: string, bufsize: int = 40): string =
  ##Retrieves utf8 encoded value from node; returns default on failure
  ##Maximum return string length is equal to ``bufsize``
  var
    buf = cast[cstring](alloc(bufsize))
    res: csize_t
  defer: dealloc(buf)
  try:
    assessStatus napi_get_value_string_utf8(`env$`, n, buf, bufsize.csize_t, addr res)
    result = ($buf)[0..res-1]
  except: result = default


proc hasProperty*(obj: napi_value, key: string): bool {.raises: [ValueError, NapiStatusError], inline.} =
  ##Checks whether or not ``obj`` has a property ``key``; Panics if ``obj`` is not an object
  if kind(obj) != napi_object: raise newException(ValueError, "value is not an object")

  assessStatus napi_has_named_property(`env$`, obj, (key), addr result)

proc getPropertyUnsafe*(obj: napi_value, key: napi_value): napi_value {.inline.} =
  ##Retrieves property ``key`` from ``obj``; Panics if ``obj`` is not an object
  assessStatus napi_get_property(`env$`, obj, (key), addr result)

proc getProperty*(obj: napi_value, key: string): napi_value {.raises: [KeyError, ValueError, NapiStatusError].}=
  ##Retrieves property ``key`` from ``obj``; Panics if ``obj`` is not an object
  if not hasProperty(obj, key): raise newException(KeyError, "property not contained for key " & key)
  assessStatus napi_get_named_property(`env$`, obj, (key), addr result)

proc getProperty*(obj: napi_value, key: string, default: napi_value): napi_value {.inline.} =
  ##Retrieves property ``key`` from ``obj``; returns default if ``obj`` is not an object or does not contain ``key``
  try: obj.getProperty(key)
  except: default

proc setProperty*(obj: napi_value, key: string, value: napi_value) {.raises: [ValueError, NapiStatusError].}=
  ##Sets property ``key`` in ``obj`` to ``value``; raises exception if ``obj`` is not an object
  if kind(obj) != napi_object: raise newException(ValueError, "value is not an object")
  assessStatus napi_set_named_property(`env$`, obj, key, value)

proc `[]`*(obj: napi_value, key: string): napi_value =
  ##Alias for ``getProperty``, raises exception
  obj.getProperty(key)
proc `[]=`*(obj: napi_value, key: string, value: napi_value) =
  ##Alias for ``setProperty``, raises exception
  obj.setProperty(key, value)



proc isArray*(obj: napi_value): bool =
  assessStatus napi_is_array(`env$`, obj, addr result)

proc isArrayBuffer*(obj: napi_value): bool =
  assessStatus napi_is_arraybuffer(`env$`, obj, addr result)

proc isTypedArray*(obj: napi_value): bool =
  assessStatus napi_is_typedarray(`env$`, obj, addr result)

proc isBuffer*(obj: napi_value): bool =
  assessStatus napi_is_buffer(`env$`, obj, addr result)

proc isDataView*(obj: napi_value): bool =
  assessStatus napi_is_dataview(`env$`, obj, addr result)


proc getTypedArrayInfo*(obj: napi_value): (NApiTypedArrayType, csize_t, pointer, napi_value, csize_t) =
  var arrType: NApiTypedArrayType
  var length: csize_t
  var data: pointer
  var arrayBuffer: napi_value
  var byteOffset: csize_t

  assessStatus napi_get_typedarray_info(`env$`, obj, addr arrType, addr length, addr data, addr arrayBuffer, addr byteOffset)
  (arrType, length, data, arrayBuffer, byteOffset)

proc hasElement*(obj: napi_value, index: int): bool {.inline.} =
  ##Checks whether element is contained in ``obj``; raises exception if ``obj`` is not an array
  if not isArray(obj): raise newException(ValueError, "value is not an array")
  assessStatus napi_has_element(`env$`, obj, uint32 index, addr result)

proc getElement*(obj: napi_value, index: int): napi_value {.inline.} =
  ##Retrieves value from ``index`` in  ``obj``; raises exception if ``obj`` is not an array or ``index`` is out of bounds
  if not hasElement(obj, index): raise newException(IndexDefect, "index out of bounds")
  assessStatus napi_get_element(`env$`, obj, uint32 index, addr result)

proc getElementUnsafe*(obj: napi_value, index: int): napi_value {.inline.} =
  ##Retrieves value from ``index`` in  ``obj``; raises exception if ``obj`` is not an array or ``index`` is out of bounds
  assessStatus napi_get_element(`env$`, obj, uint32 index, addr result)

proc getElement*(obj: napi_value, index: int, default: napi_value): napi_value {.inline.} =
  try: obj.getElement(index)
  except: default

proc setElement*(obj: napi_value, index: int, value: napi_value) =
  ##Sets value at ``index``; raises exception if ``obj`` is not an array
  if not isArray(obj): raise newException(ValueError, "value is not an array")
  assessStatus napi_set_element(`env$`, obj, uint32 index, value)

proc len*(arr: napi_value): int {.inline.} =
  if not isArray(arr): raise newException(ValueError, "value is not an array")
  arr.getProperty("length").getInt

proc lenUnsafe(arr: napi_value): int {.inline.} =
  if not isArray(arr): raise newException(ValueError, "value is not an array")
  arr.getProperty("length").getInt

proc `[]`*(obj: napi_value, index: int): napi_value {.inline.} =
  ##Alias for ``getElement``; raises exception
  obj.getElement(index)
proc `[]=`*(obj: napi_value, index: int, value: napi_value) {.inline.} =
  ##Alias for ``setElement``; raises exception
  obj.setElement(index, value)

proc getNull*(env: napi_env): napi_value {.inline.} =
  ##Returns JavaScript ``null`` value
  assessStatus napi_get_null(env, addr result)


proc getNull*: napi_value =
  ##Returns JavaScript ``null`` value
  assessStatus napi_get_null(`env$`, addr result)

proc getUndefined*: napi_value =
  ##Returns JavaScript ``undefined`` value
  assessStatus napi_get_undefined(`env$`, addr result)

proc getGlobal*: napi_value =
  ##Returns NodeJS global variable
  assessStatus napi_get_global(`env$`, addr result)

proc throwError*(env: napi_env, error: ref Exception) {.inline.} =
  ##Throws JavaScript exception with message ``msg``
  assessStatus napi_throw_error(env, error.name, error.msg.cstring)

proc registerBase(obj: Module, name: string, value: napi_value, attr: int) =
  obj.descriptors.add(
    NapiPropertyDescriptor(
      utf8name: name,
      value: value,
      attributes: napi_default
    )
  )

proc register*[T: int | uint | string | napi_value](obj: Module, name: string, value: T, attr: int = 0) =
  ##Adds field to exports object ``obj``
  obj.registerBase(name, create(obj.env, value), attr)

proc register*[T: int | uint | string | napi_value](obj: Module, name: string, values: openarray[T], attr: int = 0) =
  ##Adds field to exports object ``obj``
  var elements =  newSeq[napi_value]()
  for v in values: elements.add(obj.create(v))

  obj.registerBase(name, create(obj.env, elements), attr)

proc register*[T: int | uint | string | napi_value](obj: Module, name: string, values: openarray[(string, T)], attr: int = 0) =
  ##Adds field to exports object ``obj``
  var properties = newSeq[(string, napi_value)]()
  for v in values: properties.add((v[0], obj.create(v[1])))

  obj.registerBase(name, create(obj.env, properties), attr)

proc register*(obj: Module, name: string, cb: napi_callback) =
  obj.registerBase(name, createFn(obj.env, name, cb), 0)


proc `%`*[T](t: T): napi_value =
  `env$`.create(t)

const emptyArr: array[0, (string, napi_value)] = []

proc callFunction*(fn: napi_value, args: openarray[napi_value] = [], this = %emptyArr): napi_value =
  assessStatus napi_call_function(`env$`, this, fn, args.len.csize_t, cast[ptr napi_value](args.toUnchecked()), addr result)

proc callMethod*(instance: napi_value, methd: string, args: openarray[napi_value] = []): napi_value =
  assessStatus napi_call_function(`env$`, instance, instance.getProperty(methd), args.len.csize_t, cast[ptr napi_value](args.toUnchecked()), addr result)

template getIdentStr*(n: untyped): string = $n


template fn*(paramCt: int, name, cushy: untyped): untyped {.dirty.} =
  var name {.inject.}: napi_value
  block:
    proc `wrapper$`(environment: napi_env, info: napi_callback_info): napi_value {.cdecl.} =
      var
        `argv$` = cast[ptr UncheckedArray[napi_value]](alloc(paramCt * sizeof(napi_value)))
        argc: csize_t = paramCt
        this: napi_value
        args = newSeq[napi_value]()
      `env$` = environment
      assessStatus napi_get_cb_info(environment, info, addr argc, `argv$`, addr this, nil)
      for i in 0..<min(argc, paramCt):
        args.add(`argv$`[][i])
      dealloc(`argv$`)
      cushy

    name = createFn(`env$`, getIdentStr(name), `wrapper$`)


template registerFn*(exports: Module, paramCt: int, name: string, cushy: untyped): untyped {.dirty.}=
  block:
    proc `wrapper$`(environment: napi_env, info: napi_callback_info): napi_value {.cdecl.} =
      var
        `argv$` = cast[ptr UncheckedArray[napi_value]](alloc(paramCt * sizeof(napi_value)))
        argc: csize_t = paramCt
        this: napi_value
        args = newSeq[napi_value]()
      `env$` = environment

      assessStatus napi_get_cb_info(environment, info, addr argc, `argv$`, addr this, nil)
      for i in 0..<min(argc, paramCt):
        args.add(`argv$`[][i])
      dealloc(`argv$`)
      cushy
    exports.register(name, `wrapper$`)


proc defineProperties*(obj: Module) =
  assessStatus napi_define_properties(obj.env, obj.val, obj.descriptors.len.csize_t, cast[ptr NapiPropertyDescriptor](obj.descriptors.toUnchecked))

proc napiCreate*[T](t: T): napi_value =
  `env$`.create(t)

proc napiCreateRef*[T](t: ref T): napi_value =
  `env$`.createRef(t)

proc napiCreateObject*(): napi_value =
  `env$`.createObject()

proc napiCreateBuffer*(t: seq[byte]): napi_value =
  `env$`.createBuffer(t)

proc napiCreateSharedBuffer*(t: SharedBuffer): napi_value =
  `env$`.createSharedBuffer(t)

proc napiThrowError*(e: ref Exception) =
  `env$`.throwError(e)

proc toNapiValue(x: NimNode): NimNode {.compiletime.} =
  case x.kind
  of nnkBracket:
    var brackets = newNimNode(nnkBracket)
    for i in 0..<x.len: brackets.add(toNapiValue(x[i]))
    newCall("napiCreate", brackets)
  of nnkTableConstr:
    var table = newNimNode(nnkTableConstr)
    for i in 0..<x.len:
      x[i].expectKind nnkExprColonExpr
      table.add newTree(nnkExprColonExpr, x[i][0], toNapiValue(x[i][1]))
    newCall("napiCreate", table)
  else:
    newCall("napiCreate", x)

macro `%*`*(x: untyped): untyped =
  return toNapiValue(x)

iterator items*(n: napi_value): napi_value =
  if not n.isArray: raise newException(ValueError, "value is not an array")
  for index in 0..<n.lenUnsafe:
    yield n.getElementUnsafe(index)

iterator itemsUnsafe*(n: napi_value): napi_value {.inline.} =
  for index in 0..<n.lenUnsafe:
    yield n.getElementUnsafe(index)

iterator getAllPropertyNames*(n: napi_value): napi_value {.inline.} =
  var names: napi_value
  assessStatus napi_get_property_names(`env$`, n, addr names)
  for name in names.itemsUnsafe:
    yield name


macro init*(initHook: proc(exports: Module)): void =
  ##Bootstraps module; use by calling ``register`` to add properties to ``exports``
  ##
  ##.. code-block:: Nim
  ##  init proc(exports: Module) =
  ##    exports.register("hello", "hello world")
  var nimmain = newProc(ident("NimMain"))
  nimmain.addPragma(ident("importc"))
  var cinit = newProc(
    name = ident("cinit"),
    params = [ident("napi_value") , newIdentDefs(ident("environment"), ident("napi_env")), newIdentDefs(ident("exportsPtr"), ident("napi_value"))],
    body = newStmtList(
      nimmain,
      newCall("NimMain"),
      newVarStmt(ident("exports"), newCall("newNodeValue", [ident("exportsPtr"), ident("environment")])),
      newAssignment(ident("env$"), ident("environment")),
      newCall(initHook, ident("exports")),
      newCall("defineProperties", ident("exports")),
      newNimNode(nnkReturnStmt).add(ident("exportsPtr"))
    )
  )
  cinit.addPragma(ident("exportc"))
  result = newStmtList(
    cinit,
    newNimNode(nnkPragma).add(newColonExpr(ident("emit"), newStrLitNode("""/*VARSECTION*/ NAPI_MODULE(NODE_GYP_MODULE_NAME, cinit)"""))),
  )

