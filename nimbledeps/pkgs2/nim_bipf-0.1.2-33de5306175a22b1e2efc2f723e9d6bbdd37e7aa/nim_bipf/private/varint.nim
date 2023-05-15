# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

{.push checks:off.}  

when defined(alt_varint):
  ## Alternative varint implementation
  ## We use 2 bits to encode the number of bytes used after the first byte

  template lenVaruint32*(v: uint32): int =
    if v < 64:
      1
    elif v < 16384:
      2
    elif v < 4194304:
      3
    elif v < 536870912:
      4
    else:
      5

  func writeVaruint32*[BB](buf: var BB, v: uint32, p: var int) {.inline.} =
    
    ## we encode numBytes in the 2 least significant bits of the first byte
    ## Then 6 bits of the value in the 6 most significant bits of the first byte
    ## Then 8 bits of the value in the second byte
    ## Then 8 bits of the value in the third byte
    ## Then the remaining use a continuation bit like in the original varint, so if less than 7 bits are left, we use 7 bits and 0 for the continuation bit
    ## If more than 7 bits are left, we use 7 bits and 1 for the continuation bit, then the remainings bits
    if v < 64:
      # up to 00000000 00000000 00000000 00aaaaaa
      # is encoded as aaaaaa00
      buf[p] = byte(v shl 2 or 0b00)
      p+=1
    elif v < 16384:
      # up to 00000000 00000000 00bbbbbb bbaaaaaa
      # is encoded as aaaaaa01 bbbbbbbb
      buf[p] = byte(v shl 2 or 0b01)
      buf[p+1] = byte(v shr 6)
      p+=2
    elif v < 4194304:
      # up to 00000000 00cccccc ccbbbbbb bbaaaaaa
      # is encoded as aaaaaa10 bbbbbbbb cccccccc
      buf[p] = byte(v shl 2 or 0b10)
      buf[p+1] = byte(v shr 6)
      buf[p+2] = byte(v shr 14)
      p+=3
    elif v < 536870912:
      # up to 000ddddd ddcccccc ccbbbbbb bbaaaaaa
      # is encoded as aaaaaa11 bbbbbbbb cccccccc 0ddddddd
      buf[p] = byte(v shl 2 or 0b11)
      buf[p+1] = byte(v shr 6)
      buf[p+2] = byte(v shr 14)
      buf[p+3] = byte(v shr 22)
      p+=4
    else:
      # up to eeeddddd ddcccccc ccbbbbbb bbaaaaaa
      # is encoded as aaaaaa11 bbbbbbbb cccccccc 1ddddddd 00000eee
      buf[p] = byte(v shl 2 or 0b11)
      buf[p+1] = byte(v shr 6)
      buf[p+2] = byte(v shr 14)
      buf[p+3] = byte(v shr 22 or 0b10000000)
      buf[p+4] = byte(v shr 29)
      p+=5


  template readVaruint32*[BB](data: BB, p: var int): uint32 =
    let b: uint8 = data[p]
    let branch = b and 0b11
    var result = uint32(b shr 2)
    inc p

    if branch == 0b01:
      # up to 00000000 00000000 00bbbbbb bbaaaaaa
      # is encoded as aaaaaa01 bbbbbbbb
      result += uint32(data[p]) shl 6
      inc p
    elif branch == 0b10:
      # up to 00000000 00cccccc ccbbbbbb bbaaaaaa
      # is encoded as aaaaaa10 bbbbbbbb cccccccc
      result += uint32(data[p]) shl 6
      inc p
      result += uint32(data[p]) shl 14
      inc p
    elif branch == 0b11:
      # up to 000ddddd ddcccccc ccbbbbbb bbaaaaaa
      # is encoded as aaaaaa11 bbbbbbbb cccccccc 0ddddddd
      # or
      # up to eeeddddd ddcccccc ccbbbbbb bbaaaaaa
      # is encoded as aaaaaa11 bbbbbbbb cccccccc 1ddddddd 00000eee
      result += uint32(data[p]) shl 6
      inc p
      result += uint32(data[p]) shl 14
      inc p
      let lb = data[p]
      if (lb and 0b10000000) == 0:
        # up to 000ddddd ddcccccc ccbbbbbb bbaaaaaa
        # is encoded as aaaaaa11 bbbbbbbb cccccccc 0ddddddd
        result += uint32(lb) shl 22
        inc p
      else:
        # up to eeeddddd ddcccccc ccbbbbbb bbaaaaaa
        # is encoded as aaaaaa11 bbbbbbbb cccccccc 1ddddddd 00000eee
        result += uint32(lb and 0b01111111) shl 22
        inc p
        result += uint32(data[p]) shl 29
        inc p
    result

elif defined(no_varint):
  template lenVaruint32*(v: uint32): int =
    4
  
  func writeVaruint32*[BB](buf: var BB, v: uint32, p: var int) {.inline.} =
    buf[p] = byte(v)
    buf[p+1] = byte(v shr 8)
    buf[p+2] = byte(v shr 16)
    buf[p+3] = byte(v shr 24)
    p+=4
  
  template readVaruint32*[BB](data: BB, p: var int): uint32 =
    let result = uint32(data[p]) or (uint32(data[p+1]) shl 8) or (uint32(data[p+2]) shl 16) or (uint32(data[p+3]) shl 24)
    p+=4
    result


else:
  func writeVaruint32*[BB](buf: var BB, v: uint32, p: var int) {.inline.} =
    if v < 0x80:
      buf[p] = byte(v)
      p+=1
    elif v < 0x4000:
      buf[p] = byte(v or 0x80)
      buf[p+1] = byte(v shr 7)
      p+=2
    elif v < 0x200000:
      buf[p] = byte(v or 0x80)
      buf[p+1] = byte((v shr 7) or 0x80)
      buf[p+2] = byte(v shr 14)
      p+=3
    elif v < 0x10000000:
      buf[p] = byte(v or 0x80)
      buf[p+1] = byte((v shr 7) or 0x80)
      buf[p+2] = byte((v shr 14) or 0x80)
      buf[p+3] = byte(v shr 21)
      p+=4
    else:
      buf[p] = byte(v or 0x80)
      buf[p+1] = byte((v shr 7) or 0x80)
      buf[p+2] = byte((v shr 14) or 0x80)
      buf[p+3] = byte((v shr 21) or 0x80)
      buf[p+4] = byte(v shr 28)
      p+=5


  template readVaruint32*[BB](data: BB, p: var int): uint32 =
    var b: uint8 = data[p]
    var result = uint32(b and 0x7f)
    inc p

    for i in 0..<4:
      if (b and 0x80) != 0: 
        b = data[p]
        result += uint32(b and 0x7f) shl (7 + 7*i)
        inc p
      else:
        break

    if (b and 0x80) != 0:
      raise newException(Exception, "Malformed Varint")
    
    result

  template lenVaruint32*(v: uint32): int =
    if v < 0x80:
      1
    elif v < 0x4000:
      2
    elif v < 0x200000:
      3
    elif v < 0x10000000:
      4
    else:
      5
  
{.pop.}
      
