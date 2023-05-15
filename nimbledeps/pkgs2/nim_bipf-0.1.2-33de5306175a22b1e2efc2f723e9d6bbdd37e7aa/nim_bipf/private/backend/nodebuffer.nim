# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

import std/jsffi

type 
  NodeJsBuffer* = distinct JsObject

func isNodeJsBuffer*(buffer: JsObject): bool {.importjs: "( Buffer.isBuffer(#) )".}

func allocUnsafe*(size: int): NodeJsBuffer {.importjs: "Buffer.allocUnsafe(#)".}

func fromCString*(s: cstring): NodeJsBuffer {.importjs: "Buffer.from(#)".}
func fromDataView*(s: JsObject): NodeJsBuffer {.importjs: "Buffer.from(#)".}
func len*(buffer: NodeJsBuffer): int {.importjs: "#.length".}
func toString*(buffer: NodeJsBuffer, start:int = 0, endExclusive: int = buffer.len): cstring {.importjs: "#.toString('utf8', @)".}
func subarray*(buffer: NodeJsBuffer, start:int = 0, endExclusive: int = buffer.len): NodeJsBuffer {.importjs: "#.subarray(@)".}
func readInt8*(buffer: NodeJsBuffer, offset: int=0): int8 {.importjs: "#.readInt8(@)".}
func readUInt8*(buffer: NodeJsBuffer, offset: int=0): uint8 {.importjs: "#.readUInt8(@)".}
func readInt16LE*(buffer: NodeJsBuffer, offset: int=0): int16 {.importjs: "#.readInt16LE(@)".}
func readInt16BE*(buffer: NodeJsBuffer, offset: int=0): int16 {.importjs: "#.readInt16LE(@)".}
func readUInt16LE*(buffer: NodeJsBuffer, offset: int=0): uint16 {.importjs: "#.readUInt16LE(@)".}
func readUInt16BE*(buffer: NodeJsBuffer, offset: int=0): uint16 {.importjs: "#.readUInt16LE(@)".}
func readInt32LE*(buffer: NodeJsBuffer, offset: int=0): int32 {.importjs: "#.readInt32LE(@)".}
func readInt32BE*(buffer: NodeJsBuffer, offset: int=0): int32 {.importjs: "#.readInt32LE(@)".}
func readUInt32LE*(buffer: NodeJsBuffer, offset: int=0): uint32 {.importjs: "#.readUInt32LE(@)".}
func readUInt32BE*(buffer: NodeJsBuffer, offset: int=0): uint32 {.importjs: "#.readUInt32LE(@)".}
func readFloatLE*(buffer: NodeJsBuffer, offset: int=0): float32 {.importjs: "#.readFloatLE(@)".}
func readFloatBE*(buffer: NodeJsBuffer, offset: int=0): float32 {.importjs: "#.readFloatLE(@)".}
func readDoubleLE*(buffer: NodeJsBuffer, offset: int=0): float64 {.importjs: "#.readDoubleLE(@)".}
func readDoubleBE*(buffer: NodeJsBuffer, offset: int=0): float64 {.importjs: "#.readDoubleLE(@)".}

func writeInt8*(buffer: NodeJsBuffer, value: int8, offset: int=0) {.importjs: "#.writeInt8(#,@)".}
func writeUInt8*(buffer: NodeJsBuffer, value: uint8, offset: int=0) {.importjs: "#.writeUInt8(#,@)".}
func writeInt16LE*(buffer: NodeJsBuffer, value: int16, offset: int=0) {.importjs: "#.writeInt16LE(#,@)".}
func writeInt16BE*(buffer: NodeJsBuffer, value: int16, offset: int=0) {.importjs: "#.writeInt16BE(#,@)".}
func writeUInt16LE*(buffer: NodeJsBuffer, value: uint16, offset: int=0) {.importjs: "#.writeUInt16LE(#,@)".}
func writeUInt16BE*(buffer: NodeJsBuffer, value: uint16, offset: int=0) {.importjs: "#.writeUInt16BE(#,@)".}
func writeInt32LE*(buffer: NodeJsBuffer, value: int32, offset: int=0) {.importjs: "#.writeInt32LE(#,@)".}
func writeInt32BE*(buffer: NodeJsBuffer, value: int32, offset: int=0) {.importjs: "#.writeInt32BE(#,@)".}
func writeUInt32LE*(buffer: NodeJsBuffer, value: uint32, offset: int=0) {.importjs: "#.writeUInt32LE(#,@)".}
func writeUInt32BE*(buffer: NodeJsBuffer, value: uint32, offset: int=0) {.importjs: "#.writeUInt32BE(#,@)".}
func writeFloatLE*(buffer: NodeJsBuffer, value: float32, offset: int=0) {.importjs: "#.writeFloatLE(#,@)".}
func writeFloatBE*(buffer: NodeJsBuffer, value: float32, offset: int=0) {.importjs: "#.writeFloatBE(#,@)".}
func writeDoubleLE*(buffer: NodeJsBuffer, value: float64, offset: int=0) {.importjs: "#.writeDoubleLE(#,@)".}
func writeDoubleBE*(buffer: NodeJsBuffer, value: float64, offset: int=0) {.importjs: "#.writeDoubleBE(#,@)".}

func writeString*(result: NodeJsBuffer, s: cstring, p: int): int {.importjs: "#.write(#, #)".}
func copy(source: NodeJsBuffer, target: NodeJsBuffer, targetStart: int, sourceStart: int, sourceEnd: int): int {.importjs: "#.copy(#, @)".}
func writeBuffer*(buffer: NodeJsBuffer, s: NodeJsBuffer, offset: int) = discard copy(s, buffer, offset, 0, s.len)

func compare*(source: NodeJsBuffer, target: NodeJsBuffer, targetStart: int, targetEnd: int, sourceStart: int, sourceEnd: int): int {.importjs: "#.compare(@)".}      

func `[]`*(buffer: NodeJsBuffer, p: int): byte {.importjs: "#[#]".}
func `[]=`*(buffer: NodeJsBuffer, i: int, b: byte) {.importjs: "#[#] = #".}



