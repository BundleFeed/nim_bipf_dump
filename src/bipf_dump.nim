
import nim_bipf
import std/[os, streams, json]

const BLOCK_SIZE = 64 * 1024

proc getAppDataDir() : string =
  when defined(osx):
    return getHomeDir() / "Library" / "Application Support"
  else:
    return getConfigDir()


proc exportManyverseToJson(logBipfPath: string) =
  ## read per block of BLOCK_SIZE
  ## which each block, several records.  
  ## structure is:
  ## <block>
  ##  <record>
  ##    <length: UInt16LE>
  ##    <data: Bytes>
  ##  </record>*
  ## </block>*
  
  let logBipf = newFileStream(logBipfPath, fmRead)
  defer: logBipf.close()

  var recordBlock : array[BLOCK_SIZE, byte]

  if not isNil(logBipf):
    #debugEcho "Reading log.bipf file at: ", logBipfPath
    while logBipf.atEnd() == false:
      logBipf.read(recordBlock)
      var blockOffset = 0.uint
      while blockOffset < BLOCK_SIZE:
        #debugEcho "Reading record at offset: ", blockOffset
        let recordLength = recordBlock[blockOffset] + recordBlock[blockOffset + 1] * 256
        if (recordLength == 0):
          break
        else:
          var bifBuffer : BipfBuffer[seq[byte]]
          bifBuffer.buffer.setLen(recordLength)
          copyMem(bifBuffer.buffer[0].addr, recordBlock[blockOffset + 2].addr, recordLength)
          
          let data = deserializeToJsonNode(bifBuffer)
          echo data
          blockOffset += 2 + recordLength

  else:
    echo "logBipf file not found at: ", logBipfPath
    quit(1)



when isMainModule:
  # if some arg is provided, use it as the log.bipf path

  let logBipfPath = if paramCount() == 1:
    paramStr(1)
  elif paramCount() == 0:
    getAppDataDir() / "manyverse" / "ssb" / "db2" / "log.bipf"
  else:
    echo "Usage: ", paramStr(0), " [log.bipf path]"
    quit(1)
  
  exportManyverseToJson(logBipfPath)
    