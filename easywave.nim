import endians, strformat, tables

export tables

# {{{ Common

const
  FOURCC_SIZE = 4
  CHUNK_HEADER_SIZE = 8

  FOURCC_RIFF         = "RIFF"
  FOURCC_WAVE         = "WAVE"
  FOURCC_FORMAT       = "fmt "
  FOURCC_DATA         = "data"
  FOURCC_CUE          = "cue "
  FOURCC_LIST         = "LIST"
  FOURCC_LABEL        = "labl"
  FOURCC_LABELED_TEXT = "ltxt"
  FOURCC_REGION       = "rgn "

  WAVE_FORMAT_PCM = 1
  WAVE_FORMAT_IEEE_FLOAT = 3

type
  WaveFormat* = enum
    wf8BitInteger  = (0,  "8-bit integer"),
    wf16BitInteger = (1, "16-bit integer"),
    wf24BitInteger = (2, "24-bit integer"),
    wf32BitInteger = (3, "32-bit integer"),
    wf32BitFloat   = (4, "32-bit IEEE float"),
    wf64BitFloat   = (5, "64-bit IEEE float")

  WaveChunkInfo* = object
    id*:      string
    size*:    uint32
    filePos*: int64

  WaveRegion* = object
    startOffset*: uint32
    endOffset*:   uint32
    label*:       string

# }}}
# {{{ Reader

type
  WaveReader* = object
    filename:      string
    file:          File
    riffChunkSize: uint32
    format:        WaveFormat
    sampleRate:    Natural
    numChannels:   Natural
    nextChunkPos:  int64
    chunks:        seq[WaveChunkInfo]
    regions:       OrderedTable[uint32, WaveRegion]
    readBuffer:    seq[uint8]

type WaveReaderError* = object of Exception

proc filename*(wr: WaveReader): string = wr.filename
proc file*(wr: WaveReader): File = wr.file
proc format*(wr: WaveReader): WaveFormat = wr.format
proc sampleRate*(wr: WaveReader): Natural = wr.sampleRate
proc numChannels*(wr: WaveReader): Natural = wr.numChannels
proc chunks*(wr: WaveReader): seq[WaveChunkInfo] = wr.chunks
proc regions*(wr: WaveReader): OrderedTable[uint32, WaveRegion] = wr.regions


proc raiseWaveReadError() {.noreturn.} =
  raise newException(WaveReaderError, fmt"Error reading file")

template readBuf(wr: WaveReader, data: pointer, len: Natural) =
  if readBuffer(wr.file, data, len) != len:
    raiseWaveReadError()

# {{{ Single-value read

proc readFourCC*(wr: WaveReader): string =
  result = newString(4)
  wr.readBuf(result[0].addr, 4)

proc readInt8*(wr: WaveReader): int8 =
  wr.readBuf(result.addr, 1)

proc readInt16LE*(wr: WaveReader): int16 =
  when system.cpuEndian == bigEndian:
    var buf: int16
    wr.readBuf(buf.addr, 2)
    swapEndian16(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 2)


proc readInt32LE*(wr: WaveReader): int32 =
  when system.cpuEndian == bigEndian:
    var buf: int32
    wr.readBuf(buf.addr, 4)
    swapEndian32(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 4)

proc readInt64LE*(wr: WaveReader): int64 =
  when system.cpuEndian == bigEndian:
    var buf: int64
    wr.readBuf(buf.addr, 8)
    swapEndian64(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 8)

proc readUInt8*(wr: WaveReader): uint8 =
  wr.readBuf(result.addr, 1)

proc readUInt16LE*(wr: WaveReader): uint16 =
  when system.cpuEndian == bigEndian:
    var buf: uint16
    wr.readBuf(buf.addr, 2)
    swapEndian16(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 2)

proc readUInt32LE*(wr: WaveReader): uint32 =
  when system.cpuEndian == bigEndian:
    var buf: uint32
    wr.readBuf(buf.addr, 4)
    swapEndian32(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 4)

proc readUInt64LE*(wr: WaveReader): uint64 =
  when system.cpuEndian == bigEndian:
    var buf: uint64
    wr.readBuf(buf.addr, 8)
    swapEndian64(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 8)

proc readFloat32LE*(wr: WaveReader): float32 =
  when system.cpuEndian == bigEndian:
    var buf: float32
    wr.readBuf(buf.addr, 4)
    swapEndian32(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 4)

proc readFloat64LE*(wr: WaveReader): float64 =
  when system.cpuEndian == bigEndian:
    var buf: float64
    wr.readBuf(buf.addr, 8)
    swapEndian64(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 8)

# }}}
# {{{ Buffered read

proc readData*(wr: var WaveReader,
               dest: var openArray[int8|uint8], len: Natural) =
  wr.readBuf(dest[0].addr, len)


proc readDataLE*(wr: var WaveReader,
                 dest: var openArray[int16|uint16], len: Natural) =
  const WIDTH = 2
  when system.cpuEndian == bigEndian:
    var
      bytesToRead = len * WIDTH
      readBufferSize = (wr.readBuffer.len div WIDTH) * WIDTH
      destPos = 0

    while bytesToRead > 0:
      let count = min(readBufferSize, bytesToRead)
      wr.readBuf(wr.readBuffer[0].addr, count)
      var pos = 0
      while pos < count:
        swapEndian16(dest[destPos].addr, wr.readBuffer[pos].addr)
        inc(pos, WIDTH)
        inc(destPos)
      dec(bytesToRead, count)
  else:
    wr.readBuf(dest[0].addr, len * WIDTH)


proc readDataLE*(wr: var WaveReader,
                 dest: var openArray[int32|uint32|float32], len: Natural) =
  const WIDTH = 4
  when system.cpuEndian == bigEndian:
    var
      bytesToRead = len * WIDTH
      readBufferSize = (wr.readBuffer.len div WIDTH) * WIDTH
      destPos = 0

    while bytesToRead > 0:
      let count = min(readBufferSize, bytesToRead)
      wr.readBuf(wr.readBuffer[0].addr, count)
      var pos = 0
      while pos < count:
        swapEndian32(dest[destPos].addr, wr.readBuffer[pos].addr)
        inc(pos, WIDTH)
        inc(destPos)
      dec(bytesToRead, count)
  else:
    wr.readBuf(dest[0].addr, len * WIDTH)


proc readDataLE*(wr: var WaveReader,
                 dest: var openArray[int64|uint64|float64], len: Natural) =
  const WIDTH = 8
  when system.cpuEndian == bigEndian:
    var
      bytesToRead = len * WIDTH
      readBufferSize = (wr.readBuffer.len div WIDTH) * WIDTH
      destPos = 0

    while bytesToRead > 0:
      let count = min(readBufferSize, bytesToRead)
      wr.readBuf(wr.readBuffer[0].addr, count)
      var pos = 0
      while pos < count:
        swapEndian64(dest[destPos].addr, wr.readBuffer[pos].addr)
        inc(pos, WIDTH)
        inc(destPos)
      dec(bytesToRead, count)
  else:
    wr.readBuf(dest[0].addr, len * WIDTH)


proc readData*(wr: var WaveReader, data: var openArray[int8|uint8]) =
  readData(wr, data, data.len)

proc readDataLE*(wr: var WaveReader,
                 data: var openArray[int16|uint16|int32|uint32|int64|uint64|float32|float64]) =
  readDataLE(wr, data, data.len)

# }}}

proc isOdd(n: SomeNumber): bool = n mod 2 == 1


proc hasNextChunk*(wr: var WaveReader): bool =
  result = wr.nextChunkPos < CHUNK_HEADER_SIZE + wr.riffChunkSize.int64

proc setNextChunkPos(wr: var WaveReader, ci: WaveChunkInfo) =
  wr.nextChunkPos = ci.filePos + ci.size.int64 + CHUNK_HEADER_SIZE
  if isOdd(ci.size):
    inc(wr.nextChunkPos)

proc nextChunk*(wr: var WaveReader): WaveChunkInfo =
  if wr.nextChunkPos >= CHUNK_HEADER_SIZE + wr.riffChunkSize.int64:
    raise newException(WaveReaderError,
                       "Cannot seek to next chunk, end of file reached")

  setFilePos(wr.file, wr.nextChunkPos)

  var ci: WaveChunkInfo
  ci.id = wr.readFourCC()
  ci.size = wr.readUInt32LE()
  ci.filePos = wr.nextChunkPos

  setFilePos(wr.file, ci.filePos)

  wr.setNextChunkPos(ci)
  result = ci


proc readFormatChunk*(wr: var WaveReader) =
  let chunkId = wr.readFourCC()
  if chunkId != FOURCC_FORMAT:
    raise newException(WaveReaderError, fmt"'{FOURCC_FORMAT}' chunk not found")

  {.hint[XDeclaredButNotUsed]: off.}
  let
    chunkSize      = wr.readUInt32LE()  # ignored
    format         = wr.readUInt16LE()
    channels       = wr.readUInt16LE()
    samplesPerSec  = wr.readUInt32LE()
    avgBytesPerSec = wr.readUInt32LE()  # ignored
    blockAlign     = wr.readUInt16LE()  # ignored
    bitsPerSample  = wr.readUInt16LE()

  case format
  of WAVE_FORMAT_PCM:
    case bitsPerSample:
    of  8: wr.format = wf8BitInteger
    of 16: wr.format = wf16BitInteger
    of 24: wr.format = wf24BitInteger
    of 32: wr.format = wf32BitInteger
    else:
      raise newException(WaveReaderError,
                         fmt"Unsupported integer bit depth: {bitsPerSample}")

  of WAVE_FORMAT_IEEE_FLOAT:
    case bitsPerSample:
    of 32: wr.format = wf32BitFloat
    of 64: wr.format = wf64BitFloat
    else:
      raise newException(WaveReaderError,
                         fmt"Unsupported float bit depth: {bitsPerSample}")
  else:
    raise newException(WaveReaderError,
                       fmt"Unsupported format code: 0x{format:04x}")

  wr.numChannels = channels
  wr.sampleRate = samplesPerSec


proc readRegionIdsAndStartOffsetsFromCueChunk*(
    wr: var WaveReader, regions: var OrderedTable[uint32, WaveRegion]) =

  let chunkId = wr.readFourCC()
  if chunkId != FOURCC_CUE:
    raise newException(WaveReaderError, fmt"'{FOURCC_CUE}' chunk not found")

  let
    chunkSize = wr.readUInt32LE()
    numCuePoints = wr.readUInt32LE()

  if numCuePoints > 0'u32:
    for i in 0..<numCuePoints:

      {.hint[XDeclaredButNotUsed]: off.}
      let
        cuePointId   = wr.readUInt32LE()
        position     = wr.readUInt32LE()  # ignored
        dataChunkId  = wr.readFourCC()    # must be 'data'
        chunkStart   = wr.readUInt32LE()  # ignored
        blockStart   = wr.readUInt32LE()  # ignored
        sampleOffset = wr.readUInt32LE()

      if dataChunkId == FOURCC_DATA:
        if not regions.hasKey(cuePointId):
          var wr: WaveRegion
          regions[cuePointId] = wr
        regions[cuePointId].startOffset = sampleOffset


proc readRegionLabelsAndEndOffsetsFromListChunk*(
    wr: var WaveReader, regions: var OrderedTable[uint32, WaveRegion]) =

  let chunkId = wr.readFourCC()
  if chunkId != FOURCC_LIST:
    raise newException(WaveReaderError, fmt"'{FOURCC_LIST}' chunk not found")

  let
    chunkSize  = wr.readUInt32LE()
    listTypeId = wr.readFourCC()

  var pos = 4  # listTypeId has to be included in the count
  while pos.uint32 < chunkSize:
    let subChunkId   = wr.readFourCC()
    var subChunkSize = wr.readUInt32LE()

    case subChunkId
    of FOURCC_LABEL:
      let cuePointId = wr.readUInt32LE()

      var textSize = subChunkSize.int - 4
      var text = newString(textSize-1)  # don't read the terminating zero byte
      wr.readBuf(text[0].addr, textSize-1)

      if regions.hasKey(cuePointId):
        regions[cuePointId].label = text

      setFilePos(wr.file, 1, fspCur)  # skip terminating zero
      if isOdd(textSize):
        inc(textSize)
        setFilePos(wr.file, 1, fspCur)
      inc(pos, CHUNK_HEADER_SIZE + 4 + textSize)

    of FOURCC_LABELED_TEXT:
      let
        cuePointId   = wr.readUInt32LE()
        sampleLength = wr.readUInt32LE()
        purposeId    = wr.readFourCC()

      if purposeId == FOURCC_REGION:
        if regions.hasKey(cuePointId):
          regions[cuePointId].endOffset =
            regions[cuePointId].startOffset + sampleLength

      if isOdd(subChunkSize):
        inc(subChunkSize)
      inc(pos, CHUNK_HEADER_SIZE + subChunkSize.int)
      setFilePos(wr.file, subChunkSize.int64 - (4+4+4), fspCur)

    else:
      if isOdd(subChunkSize):
        inc(subChunkSize)
      inc(pos, CHUNK_HEADER_SIZE + subChunkSize.int)
      setFilePos(wr.file, subChunkSize.int64, fspCur)


proc openWaveFile*(filename: string, bufSize: Natural = 4096): WaveReader =
  var wr: WaveReader
  if not open(wr.file, filename, fmRead):
    raise newException(WaveReaderError, fmt"Error opening file for reading")

  wr.filename = filename
  wr.chunks = newSeq[WaveChunkInfo]()

  when system.cpuEndian == bigEndian:
    wr.readBuffer = newSeq[uint8](bufSize)

  if wr.readFourCC() != FOURCC_RIFF:
    raise newException(WaveReaderError,
                       fmt"Not a WAVE file ('{FOURCC_RIFF}' chunk not found)")

  wr.riffChunkSize = wr.readUInt32LE()

  if wr.readFourCC() != FOURCC_WAVE:
    raise newException(WaveReaderError,
                       "Not a WAVE file ('{FOURCC_WAVE}' chunk not found)")

  wr.nextChunkPos = FOURCC_SIZE + CHUNK_HEADER_SIZE
  result = wr


proc parseWaveFile*(filename: string, readRegions: bool = false,
                    bufSize: Natural = 4096): WaveReader =

  var wr = openWaveFile(filename, bufSize)

  # Build chunk list
  while wr.hasNextChunk():
    var ci = wr.nextChunk()
    wr.chunks.add(ci)
    if ci.id == FOURCC_FORMAT:
      wr.readFormatChunk()

  wr.regions = initOrderedTable[uint32, WaveRegion]()
  if readRegions:
    for ci in wr.chunks:
      if ci.id == FOURCC_CUE:
        setFilePos(wr.file, ci.filePos)
        wr.readRegionIdsAndStartOffsetsFromCueChunk(wr.regions)

    for ci in wr.chunks:
      if ci.id == FOURCC_LIST:
        setFilePos(wr.file, ci.filePos)
        wr.readRegionLabelsAndEndOffsetsFromListChunk(wr.regions)

  # Seek to the start of the data chunk
  for ci in wr.chunks:
    if ci.id == FOURCC_DATA:
      wr.setNextChunkPos(ci)
      setFilePos(wr.file, ci.filePos)
      return wr

  raise newException(WaveReaderError, fmt"'{FOURCC_DATA}' chunk not found")

# }}}
# {{{ Writer
#
type
  WaveWriter* = object
    filename:     string
    file:         File
    format:       WaveFormat
    sampleRate:   Natural
    numChannels:  Natural
    regions:      OrderedTable[uint32, WaveRegion]

    writeBuffer:  seq[uint8]
    dataLen:      int64
    chunkSizePos: int64
    chunkStarted: bool
    fileClosed:   bool

  WaveWriterError* = object of Exception


proc filename*(ww: WaveWriter): string = ww.filename
proc format*(ww: WaveWriter): WaveFormat = ww.format
proc sampleRate*(ww: WaveWriter): Natural = ww.sampleRate
proc numChannels*(ww: WaveWriter): Natural = ww.numChannels
proc regions*(ww: WaveWriter): OrderedTable[uint32, WaveRegion] = ww.regions

proc checkFileClosed(ww: WaveWriter) =
  if ww.fileClosed:
    raise newException(WaveReaderError, "File closed")

proc checkChunkStarted(ww: WaveWriter) =
  if not ww.chunkStarted:
    raise newException(WaveReaderError, "Chunk not started")

proc raiseWaveWriteError() {.noreturn.} =
  raise newException(WaveWriterError, "Error writing file")

proc writeBuf(ww: var WaveWriter, data: pointer, len: Natural) =
  ww.checkFileClosed()
  if writeBuffer(ww.file, data, len) != len:
    raiseWaveWriteError()
  inc(ww.dataLen, len)

# {{{ Single-value write

proc writeFourCC*(ww: var WaveWriter, fourCC: string) =
  var buf = fourCC
  ww.writeBuf(buf[0].addr, 4)

proc writeInt8*(ww: var WaveWriter, d: int8) =
  var dest = d
  ww.writeBuf(dest.addr, 1)

proc writeInt16LE*(ww: var WaveWriter, d: int16) =
  var src = d
  when system.cpuEndian == bigEndian:
    var dest: int16
    swapEndian16(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 2)
  else:
    ww.writeBuf(src.addr, 2)

proc writeInt32LE*(ww: var WaveWriter, d: int32) =
  var src = d
  when system.cpuEndian == bigEndian:
    var dest: int32
    swapEndian32(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 4)
  else:
    ww.writeBuf(src.addr, 4)

proc writeInt64LE*(ww: var WaveWriter, d: int64) =
  var src = d
  when system.cpuEndian == bigEndian:
    var dest: int64
    swapEndian64(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 8)
  else:
    ww.writeBuf(src.addr, 8)

proc writeUInt8*(ww: var WaveWriter, d: uint8) =
  var dest = d
  ww.writeBuf(dest.addr, 1)

proc writeUInt16LE*(ww: var WaveWriter, d: uint16) =
  var src = d
  when system.cpuEndian == bigEndian:
    var dest: int16
    swapEndian16(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 2)
  else:
    ww.writeBuf(src.addr, 2)

proc writeUInt32LE*(ww: var WaveWriter, d: uint32) =
  var src = d
  when system.cpuEndian == bigEndian:
    var dest: int32
    swapEndian32(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 4)
  else:
    ww.writeBuf(src.addr, 4)

proc writeUInt64LE*(ww: var WaveWriter, d: uint64) =
  var src = d
  when system.cpuEndian == bigEndian:
    var dest: int64
    swapEndian64(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 8)
  else:
    ww.writeBuf(src.addr, 8)

proc writeFloat32LE*(ww: var WaveWriter, d: float32) =
  var src = d
  when system.cpuEndian == bigEndian:
    var dest: float32
    swapEndian32(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 4)
  else:
    ww.writeBuf(src.addr, 4)

proc writeFloat64LE*(ww: var WaveWriter, d: float64) =
  var src = d
  when system.cpuEndian == bigEndian:
    var dest: float64
    swapEndian64(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 8)
  else:
    ww.writeBuf(src.addr, 8)

# }}}
# {{{ Buffered write

proc writeData16LE*(ww: var WaveWriter, data: pointer, len: Natural) =
  const WIDTH = 2
  assert len mod WIDTH == 0

  when system.cpuEndian == bigEndian:
    let writeBufferSize = (ww.writeBuffer.len div WIDTH) * WIDTH
    var
      src = cast[ptr UncheckedArray[int8]](data)
      pos = 0
      destPos = 0

    while pos < len:
      swapEndian16(ww.writeBuffer[destPos].addr, src[pos].addr)
      inc(destPos, WIDTH)
      inc(pos, WIDTH)
      if destPos >= writeBufferSize:
        ww.writeBuf(ww.writeBuffer[0].addr, writeBufferSize)
        destPos = 0

    if destPos > 0:
      ww.writeBuf(ww.writeBuffer[0].addr, destPos)
  else:
    ww.writeBuf(data, len)


proc writeData32LE*(ww: var WaveWriter, data: pointer, len: Natural) =
  const WIDTH = 4
  assert len mod WIDTH == 0

  when system.cpuEndian == bigEndian:
    let writeBufferSize = (ww.writeBuffer.len div WIDTH) * WIDTH
    var
      src = cast[ptr UncheckedArray[int8]](data)
      pos = 0
      destPos = 0

    while pos < len:
      swapEndian32(ww.writeBuffer[destPos].addr, src[pos].addr)
      inc(destPos, WIDTH)
      inc(pos, WIDTH)
      if destPos >= writeBufferSize:
        ww.writeBuf(ww.writeBuffer[0].addr, writeBufferSize)
        destPos = 0

    if destPos > 0:
      ww.writeBuf(ww.writeBuffer[0].addr, destPos)
  else:
    ww.writeBuf(data, len)


proc writeData64LE*(ww: var WaveWriter, data: pointer, len: Natural) =
  const WIDTH = 8
  assert len mod WIDTH == 0

  when system.cpuEndian == bigEndian:
    let writeBufferSize = (ww.writeBuf.len div WIDTH) * WIDTH
    var
      src = cast[ptr UncheckedArray[int8]](data)
      pos = 0
      destPos = 0

    while pos < len:
      swapEndian64(ww.writeBuffer[destPos].addr, src[pos].addr)
      inc(destPos, WIDTH)
      inc(pos, WIDTH)
      if destPos >= writeBufferSize:
        ww.writeBuf(ww.writeBuffer[0].addr, writeBufferSize)
        destPos = 0

    if destPos > 0:
      ww.writeBuf(ww.writeBuffer[0].addr, destPos)
  else:
    ww.writeBuf(data, len)

proc writeData*(ww: var WaveWriter, data: var openArray[int8|uint8],
                len: Natural) =
  ww.writeBuf(data[0].addr, len)

proc writeData*(ww: var WaveWriter, data: var openArray[int8|uint8]) =
  ww.writeBuf(data[0].addr, data.len)

proc writeDataLE*(ww: var WaveWriter, data: var openArray[int16|uint16],
                  len: Natural) =
  ww.writeData16LE(data[0].addr, len * 2)

proc writeDataLE*(ww: var WaveWriter, data: var openArray[int16|uint16]) =
  ww.writeData16LE(data[0].addr, data.len * 2)

proc writeDataLE*(ww: var WaveWriter,
                  data: var openArray[int32|uint32|float32], len: Natural) =
  ww.writeData16LE(data[0].addr, len * 4)

proc writeDataLE*(ww: var WaveWriter, data: var openArray[int32|uint32|float32]) =
  ww.writeData16LE(data[0].addr, data.len * 4)

proc writeDataLE*(ww: var WaveWriter,
                  data: var openArray[int64|uint64|float64], len: Natural) =
  ww.writeData16LE(data[0].addr, len * 8)

proc writeDataLE*(ww: var WaveWriter, data: var openArray[int64|uint64|float64]) =
  ww.writeData16LE(data[0].addr, data.len * 8)

# }}}

proc startChunk*(ww: var WaveWriter, id: string) =
  ww.checkFileClosed()
  if ww.chunkStarted:
    raise newException(WaveReaderError,
      "Chunk already started; writing nested chunks is not supported")

  ww.writeFourCC(id)
  ww.chunkSizePos = getFilePos(ww.file)
  ww.writeUInt32LE(0)  # to be updated later
  ww.dataLen = 0
  ww.chunkStarted = true


proc endChunk*(ww: var WaveWriter) =
  ww.checkFileClosed()
  ww.checkChunkStarted()

  let fp = getFilePos(ww.file)
  let dataLen = ww.dataLen
  if dataLen mod 2 > 0:
    ww.writeInt8(0) # chunks must contain even number of bytes
  setFilePos(ww.file, ww.chunkSizePos)
  ww.writeUInt32LE(dataLen.uint32)
  setFilePos(ww.file, fp)
  ww.dataLen = 0
  ww.chunkStarted = false


proc writeWaveHeader(ww: var WaveWriter) =
  ww.writeFourCC(FOURCC_RIFF)
  ww.writeUint32LE(0)  # to be updated later
  ww.writeFourCC(FOURCC_WAVE)

proc writeWaveFile*(filename: string, format: WaveFormat, sampleRate: Natural,
                    numChannels: Natural,
                    bufSize: Natural = 4096): WaveWriter =
  var ww: WaveWriter
  ww.filename = filename

  if not open(ww.file, ww.filename, fmWrite):
    raise newException(WaveWriterError, "Error opening file for writing")

  when system.cpuEndian == bigEndian:
    ww.writeBuffer = newSeq[uint8](bufSize)

  ww.format = format
  ww.sampleRate = sampleRate
  ww.numChannels = numChannels

  ww.writeWaveHeader()
  result = ww


proc writeFormatChunk*(ww: var WaveWriter) =
  ww.startChunk(FOURCC_FORMAT)

  var formatTag: uint16
  var bitsPerSample: uint16

  case ww.format
  of wf8BitInteger:  formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 8
  of wf16BitInteger: formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 16
  of wf24BitInteger: formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 24
  of wf32BitInteger: formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 32
  of wf32BitFloat:   formatTag = WAVE_FORMAT_IEEE_FLOAT; bitsPerSample = 32
  of wf64BitFloat:   formatTag = WAVE_FORMAT_IEEE_FLOAT; bitsPerSample = 64

  var blockAlign = (ww.numChannels.uint16 * bitsPerSample div 8).uint16
  var avgBytesPerSec = ww.sampleRate.uint32 * blockAlign

  ww.writeUInt16LE(formatTag)
  ww.writeUInt16LE(ww.numChannels.uint16)
  ww.writeUInt32LE(ww.sampleRate.uint32)
  ww.writeUInt32LE(avgBytesPerSec)
  ww.writeUInt16LE(blockAlign)
  ww.writeUInt16LE(bitsPerSample)

  ww.endChunk()


proc startDataChunk*(ww: var WaveWriter) =
  ww.startChunk(FOURCC_DATA)


proc endFile*(ww: var WaveWriter) =
  ww.checkFileClosed()
  if ww.chunkStarted:
    ww.endChunk()

  setFilePos(ww.file, 4)
  let size = getFileSize(ww.file) - CHUNK_HEADER_SIZE
  ww.writeUInt32LE(size.uint32)

  close(ww.file)
  ww.fileClosed = true


# }}}

when isMainModule:
  import os
  var infile = paramStr(1)
#[
  var wr = openWaveFile(infile)

  while wr.hasNextChunk():
    var c = wr.nextChunk()
    echo c
    if c.id == FOURCC_FORMAT:
      wr.readFormatChunk()

  echo fmt"format: {wr.format}"
  echo fmt"sampleRate: {wr.sampleRate}"
  echo fmt"numChannels: {wr.numChannels}"
  echo ""
]#

  var wr = parseWaveFile(infile, readRegions = true)

  echo fmt"format: {wr.format}"
  echo fmt"sampleRate: {wr.sampleRate}"
  echo fmt"numChannels: {wr.numChannels}"

  echo ""
  for ci in wr.chunks:
    echo ci

  echo ""
  for id, r in wr.regions.pairs:
    echo fmt"id: {id}, {r}"

# vim: et:ts=2:sw=2:fdm=marker
