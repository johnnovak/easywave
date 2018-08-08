## :Author: John Novak <john@johnnovak.net>
##
## 
##

import endians, strformat, tables

export tables

# {{{ Common

const
  FOURCC_SIZE = 4
  CHUNK_HEADER_SIZE = 8

  FOURCC_RIFF_LE*      = "RIFF"  ## RIFF ID (little endian)
  FOURCC_RIFF_BE*      = "RIFX"  ## RIFF ID (big endian)
  FOURCC_WAVE*         = "WAVE"  ## WAVE format ID
  FOURCC_FORMAT*       = "fmt "  ## Format chunk ID
  FOURCC_DATA*         = "data"  ## Data chunk ID
  FOURCC_CUE*          = "cue "  ## Cue chunk ID
  FOURCC_LIST*         = "LIST"  ## List chunk ID
  FOURCC_ASSOC_DATA*   = "adtl"  ## Associated data list chunk ID
  FOURCC_LABEL*        = "labl"  ## Label chunk ID
  FOURCC_LABELED_TEXT* = "ltxt"  ## Labeled text chunk ID
  FOURCC_REGION*       = "rgn "  ## Region chunk ID

  WAVE_FORMAT_PCM = 1
  WAVE_FORMAT_IEEE_FLOAT = 3

type
  WaveFormat* = enum
    ## supported WAVE formats (bit-depths)
    wf8BitInteger  = (0,  "8-bit integer"),
    wf16BitInteger = (1, "16-bit integer"),
    wf24BitInteger = (2, "24-bit integer"),
    wf32BitInteger = (3, "32-bit integer"),
    wf32BitFloat   = (4, "32-bit IEEE float"),
    wf64BitFloat   = (5, "64-bit IEEE float")

  WaveChunkInfo* = object
    ## contains information about a chunk
    id*:      string  ## 4-char chunk ID (FourCC)
    size*:    uint32  ## size of chunk data in bytes
    filePos*: int64   ## file position of the chunk

  WaveRegion* = object
    ## represents a marker (if length is 0) or a region
    startFrame*: uint32  ## start sample frame of the marker/region
    length*:     uint32  ## length of the region in frames (0 for markers)
    label*:      string  ## text label

# }}}
# {{{ Reader

type
  WaveReader* = object
    filename:      string
    file:          File
    endianness:    Endianness
    format:        WaveFormat
    sampleRate:    Natural
    numChannels:   Natural
    chunks:        seq[WaveChunkInfo]
    regions:       OrderedTable[uint32, WaveRegion]

    readBuffer:    seq[uint8]
    riffChunkSize: uint32  # TODO use filesize instead?
    nextChunkPos:  int64
    swapEndian:    bool

type WaveReaderError* = object of Exception

proc filename*(wr: WaveReader): string {.inline.} =
  ## The filename of the WAVE file.
  wr.filename

proc file*(wr: WaveReader): File{.inline.} =
  ## The file object to used to read the WAVE file data.
  wr.file

proc endianness*(wr: WaveReader): Endianness {.inline.} =
  ## The endianness of the WAVE file.
  wr.endianness

proc format*(wr: WaveReader): WaveFormat {.inline.} =
  ## The format (bit-depth) of the audio data (populated by ``parseWaveFile``
  ## and ``readFormatChunk``).
  wr.format

proc sampleRate*(wr: WaveReader): Natural {.inline.} =
  ## The sample rate of audio data (populated by ``parseWaveFile`` and
  ## ``readFormatChunk``).
  wr.sampleRate

proc numChannels*(wr: WaveReader): Natural {.inline.} =
  ## The number of channels stored in the audio data (populated by
  ## ``parseWaveFile`` and ``readFormatChunk``).
  wr.numChannels

proc chunks*(wr: WaveReader): seq[WaveChunkInfo] {.inline.} =
  ## A list containing info about the chunks found in the WAVE file (populated
  ## by ``parseWaveFile`` and ``buildChunkList``).
  wr.chunks

proc regions*(wr: WaveReader): OrderedTable[uint32, WaveRegion] {.inline.} =
  wr.regions
## Returns an ordered table of regions where the key is the region ID.


proc raiseWaveReadError() {.noreturn.} =
  raise newException(WaveReaderError, fmt"Error reading file")

template readBuf(wr: WaveReader, data: pointer, len: Natural) =
  if readBuffer(wr.file, data, len) != len:
    raiseWaveReadError()

# {{{ Single-value read

proc readFourCC*(wr: WaveReader): string =
  ## Reads a 4-byte FourCC as a string from the current file position. Raises
  ## a ``WaveReadError`` on read errors.
  result = newString(4)
  wr.readBuf(result[0].addr, 4)

proc readInt8*(wr: WaveReader): int8 =
  ## Reads a single ``int8`` value from the current file position. Raises
  ## a ``WaveReadError`` on read errors.
  wr.readBuf(result.addr, 1)

proc readInt16*(wr: WaveReader): int16 =
  ## Reads a single ``int16`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  if wr.swapEndian:
    var buf: int16
    wr.readBuf(buf.addr, 2)
    swapEndian16(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 2)

proc readInt32*(wr: WaveReader): int32 =
  ## Reads a single ``int32`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  if wr.swapEndian:
    var buf: int32
    wr.readBuf(buf.addr, 4)
    swapEndian32(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 4)

proc readInt64*(wr: WaveReader): int64 =
  ## Reads a single ``int64`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  if wr.swapEndian:
    var buf: int64
    wr.readBuf(buf.addr, 8)
    swapEndian64(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 8)

proc readUInt8*(wr: WaveReader): uint8 =
  ## Reads a single ``uint8`` value from the current file position. Raises
  ## a ``WaveReadError`` on read errors.
  wr.readBuf(result.addr, 1)

proc readUInt16*(wr: WaveReader): uint16 =
  ## Reads a single ``uint16`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  if wr.swapEndian:
    var buf: uint16
    wr.readBuf(buf.addr, 2)
    swapEndian16(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 2)

proc readUInt32*(wr: WaveReader): uint32 =
  ## Reads a single ``uint32`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  if wr.swapEndian:
    var buf: uint32
    wr.readBuf(buf.addr, 4)
    swapEndian32(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 4)

proc readUInt64*(wr: WaveReader): uint64 =
  ## Reads a single ``uint64`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  if wr.swapEndian:
    var buf: uint64
    wr.readBuf(buf.addr, 8)
    swapEndian64(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 8)

proc readFloat32*(wr: WaveReader): float32 =
  ## Reads a single ``float32`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  if wr.swapEndian:
    var buf: float32
    wr.readBuf(buf.addr, 4)
    swapEndian32(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 4)

proc readFloat64*(wr: WaveReader): float64 =
  ## Reads a single ``float64`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  if wr.swapEndian:
    var buf: float64
    wr.readBuf(buf.addr, 8)
    swapEndian64(result.addr, buf.addr)
  else:
    wr.readBuf(result.addr, 8)

# }}}
# {{{ Buffered read

proc readData*(wr: var WaveReader,
               dest: var openArray[int8|uint8], len: Natural) =
  ## Reads `len` number of ``int8|uint8`` values into `dest` from the current
  ## file position and performs endianness conversion if necessary. Raises
  ## a ``WaveReadError`` on read errors.
  wr.readBuf(dest[0].addr, len)

proc readData*(wr: var WaveReader,
               dest: var openArray[int16|uint16], len: Natural) =
  ## Reads `len` number of ``int16|uint16`` values into `dest` from the
  ## current file position and performs endianness conversion if necessary.
  ## Raises a ``WaveReadError`` on read errors.
  const WIDTH = 2
  if wr.swapEndian:
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


proc readData*(wr: var WaveReader,
               dest: var openArray[int32|uint32|float32], len: Natural) =
  ## Reads `len` number of ``int32|uint32|float32`` values into `dest` from
  ## the current file position and performs endianness conversion if
  ## necessary. Raises a ``WaveReadError`` on read errors.
  const WIDTH = 4
  if wr.swapEndian:
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


proc readData*(wr: var WaveReader,
               dest: var openArray[int64|uint64|float64], len: Natural) =
  ## Reads `len` number of ``int64|uint64|float64`` values into `dest` from
  ## the current file position and performs endianness conversion if
  ## necessary.  Raises a ``WaveReadError`` on read errors.
  const WIDTH = 8
  if wr.swapEndian:
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
  ## Shortcut to fill the whole `data` buffer with data.
  readData(wr, data, data.len)

proc readData*(wr: var WaveReader,
               data: var openArray[int16|uint16|int32|uint32|int64|uint64|float32|float64]) =
  ## Shortcut to fill the whole `data` buffer with data.
  readData(wr, data, data.len)

# }}}

proc isOdd(n: SomeNumber): bool = n mod 2 == 1

proc hasNextChunk*(wr: var WaveReader): bool =
  ## Returns true iff the wave file has more chunks (to be used with
  ## ``nextChunk``).
  result = wr.nextChunkPos < CHUNK_HEADER_SIZE + wr.riffChunkSize.int64

proc setNextChunkPos(wr: var WaveReader, ci: WaveChunkInfo) =
  wr.nextChunkPos = ci.filePos + ci.size.int64 + CHUNK_HEADER_SIZE
  if isOdd(ci.size):
    inc(wr.nextChunkPos)

proc nextChunk*(wr: var WaveReader): WaveChunkInfo =
  ## Finds the next chunk in the file; raises a ``WaveReadError`` if the end
  ## of file has been reached. Returns chunk info and sets the file pointer to
  ## the start of the chunk if successful.
  if wr.nextChunkPos >= CHUNK_HEADER_SIZE + wr.riffChunkSize.int64:
    raise newException(WaveReaderError,
                       "Cannot seek to next chunk, end of file reached")

  setFilePos(wr.file, wr.nextChunkPos)

  var ci: WaveChunkInfo
  ci.id = wr.readFourCC()
  ci.size = wr.readUInt32()
  ci.filePos = wr.nextChunkPos

  setFilePos(wr.file, ci.filePos)

  wr.setNextChunkPos(ci)
  result = ci


proc readFormatChunk*(wr: var WaveReader) =
  ## Reads the format chunk from the current file position and sets the format
  ## info in the ``WaveReader`` object on success. Raises
  ## a ``WaveReaderError`` on any error (e.g. read error, chunk not found,
  ## unsupported format etc.).
  let chunkId = wr.readFourCC()
  if chunkId != FOURCC_FORMAT:
    raise newException(WaveReaderError, fmt"'{FOURCC_FORMAT}' chunk not found")

  {.hint[XDeclaredButNotUsed]: off.}
  let
    chunkSize      = wr.readUInt32()  # ignored
    format         = wr.readUInt16()
    channels       = wr.readUInt16()
    samplesPerSec  = wr.readUInt32()
    avgBytesPerSec = wr.readUInt32()  # ignored
    blockAlign     = wr.readUInt16()  # ignored
    bitsPerSample  = wr.readUInt16()

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
    chunkSize = wr.readUInt32()
    numCuePoints = wr.readUInt32()

  if numCuePoints > 0'u32:
    for i in 0..<numCuePoints:

      {.hint[XDeclaredButNotUsed]: off.}
      let
        cuePointId   = wr.readUInt32()
        position     = wr.readUInt32()  # ignored
        dataChunkId  = wr.readFourCC()    # must be 'data'
        chunkStart   = wr.readUInt32()  # ignored
        blockStart   = wr.readUInt32()  # ignored
        sampleOffset = wr.readUInt32()

      if dataChunkId == FOURCC_DATA:
        if not regions.hasKey(cuePointId):
          var wr: WaveRegion
          regions[cuePointId] = wr
        regions[cuePointId].startFrame = sampleOffset


proc readRegionLabelsAndEndOffsetsFromListChunk*(
    wr: var WaveReader, regions: var OrderedTable[uint32, WaveRegion]) =

  let chunkId = wr.readFourCC()
  if chunkId != FOURCC_LIST:
    raise newException(WaveReaderError, fmt"'{FOURCC_LIST}' chunk not found")

  let
    chunkSize  = wr.readUInt32()
    listTypeId = wr.readFourCC()

  var pos = 4  # listTypeId has to be included in the count
  while pos.uint32 < chunkSize:
    let subChunkId   = wr.readFourCC()
    var subChunkSize = wr.readUInt32()

    case subChunkId
    of FOURCC_LABEL:
      let cuePointId = wr.readUInt32()

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
        cuePointId   = wr.readUInt32()
        sampleLength = wr.readUInt32()
        purposeId    = wr.readFourCC()

      if purposeId == FOURCC_REGION:
        if regions.hasKey(cuePointId):
          regions[cuePointId].length = sampleLength

      if isOdd(subChunkSize):
        inc(subChunkSize)
      inc(pos, CHUNK_HEADER_SIZE + subChunkSize.int)
      setFilePos(wr.file, subChunkSize.int64 - (4+4+4), fspCur)

    else:
      if isOdd(subChunkSize):
        inc(subChunkSize)
      inc(pos, CHUNK_HEADER_SIZE + subChunkSize.int)
      setFilePos(wr.file, subChunkSize.int64, fspCur)


proc readWaveHeader(wr: var WaveReader) =
  let id = wr.readFourCC()
  case id
  of FOURCC_RIFF_LE: wr.endianness = littleEndian
  of FOURCC_RIFF_BE: wr.endianness = bigEndian
  else:
    raise newException(WaveReaderError, "Not a WAVE file " &
                fmt"('{FOURCC_RIFF_LE}' or '{FOURCC_RIFF_BE}' chunk not found)")

  wr.swapEndian = cpuEndian != wr.endianness

  wr.riffChunkSize = wr.readUInt32()

  if wr.readFourCC() != FOURCC_WAVE:
    raise newException(WaveReaderError,
                       "Not a WAVE file ('{FOURCC_WAVE}' chunk not found)")

  wr.nextChunkPos = FOURCC_SIZE + CHUNK_HEADER_SIZE


proc openWaveFile*(filename: string, bufSize: Natural = 4096): WaveReader =
  ## Opens a WAVE file for reading but does not parse anything else than the
  ## master RIFF header. Raises a ``WaveReaderError`` if the file is not
  ## a valid WAVE file and on read errors.
  var wr: WaveReader
  if not open(wr.file, filename, fmRead):
    raise newException(WaveReaderError, fmt"Error opening file for reading")

  wr.filename = filename
  wr.chunks = newSeq[WaveChunkInfo]()

  wr.readBuffer = newSeq[uint8](bufSize)

  wr.readWaveHeader()
  result = wr


proc buildChunkList*(wr: var WaveReader) =
  ## Finds all top-level chunks in the WAVE file and stores the result as
  ## a list of ``ChunkInfo`` objects that can be accessed through the
  ## ``chunks`` property. Raises a ``WaveReadError`` on read errors.
  while wr.hasNextChunk():
    var ci = wr.nextChunk()
    wr.chunks.add(ci)
    if ci.id == FOURCC_FORMAT:
      wr.readFormatChunk()


proc parseWaveFile*(filename: string, readRegions: bool = false,
                    bufSize: Natural = 4096): WaveReader =
  ## Opens a WAVE file for reading, builds the chunk list, reads the format
  ## chunk, reads the markers and regions if `readRegions` is true, then seeks
  ## to the start of the data chunk. Raises a ``WaveReaderError`` if the file
  ## is not a valid WAVE file and on read errors.
  var wr = openWaveFile(filename, bufSize)

  wr.buildChunkList()

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
    filename:       string
    endianness:     Endianness
    format:         WaveFormat
    sampleRate:     Natural
    numChannels:    Natural
    regions:        OrderedTable[uint32, WaveRegion]

    file:           File
    writeBuffer:    seq[uint8]
    chunkSize:      seq[int64]
    chunkSizePos:   seq[int64]
    trackChunkSize: bool
    swapEndian:     bool

  WaveWriterError* = object of Exception


proc filename*(ww: WaveWriter): string {.inline.} = ww.filename
proc endianness*(ww: WaveWriter): Endianness {.inline.} = ww.endianness
proc format*(ww: WaveWriter): WaveFormat {.inline.} = ww.format
proc sampleRate*(ww: WaveWriter): Natural {.inline.} = ww.sampleRate
proc numChannels*(ww: WaveWriter): Natural {.inline.} = ww.numChannels

proc `regions=`*(ww: var WaveWriter,
                 regions: OrderedTable[uint32, WaveRegion]) {.inline.} =
  ww.regions = regions

proc regions*(ww: WaveWriter): OrderedTable[uint32, WaveRegion] {.inline.} =
  ww.regions

proc checkFileClosed(ww: WaveWriter) =
  if ww.file == nil: raise newException(WaveReaderError, "File closed")

proc raiseWaveWriteError() {.noreturn.} =
  raise newException(WaveWriterError, "Error writing file")

proc writeBuf(ww: var WaveWriter, data: pointer, len: Natural) =
  ww.checkFileClosed()
  if writeBuffer(ww.file, data, len) != len:
    raiseWaveWriteError()
  if ww.trackChunkSize and ww.chunkSize.len > 0:
    inc(ww.chunkSize[ww.chunkSize.high], len)

# {{{ Single-value write

proc writeFourCC*(ww: var WaveWriter, fourCC: string) =
  var buf = fourCC
  ww.writeBuf(buf[0].addr, 4)

proc writeString*(ww: var WaveWriter, s: string) =
  var buf = s
  ww.writeBuf(buf[0].addr, s.len)

proc writeInt8*(ww: var WaveWriter, d: int8) =
  var dest = d
  ww.writeBuf(dest.addr, 1)

proc writeInt16*(ww: var WaveWriter, d: int16) =
  var src = d
  if ww.swapEndian:
    var dest: int16
    swapEndian16(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 2)
  else:
    ww.writeBuf(src.addr, 2)

proc writeInt32*(ww: var WaveWriter, d: int32) =
  var src = d
  if ww.swapEndian:
    var dest: int32
    swapEndian32(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 4)
  else:
    ww.writeBuf(src.addr, 4)

proc writeInt64*(ww: var WaveWriter, d: int64) =
  var src = d
  if ww.swapEndian:
    var dest: int64
    swapEndian64(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 8)
  else:
    ww.writeBuf(src.addr, 8)

proc writeUInt8*(ww: var WaveWriter, d: uint8) =
  var dest = d
  ww.writeBuf(dest.addr, 1)

proc writeUInt16*(ww: var WaveWriter, d: uint16) =
  var src = d
  if ww.swapEndian:
    var dest: int16
    swapEndian16(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 2)
  else:
    ww.writeBuf(src.addr, 2)

proc writeUInt32*(ww: var WaveWriter, d: uint32) =
  var src = d
  if ww.swapEndian:
    var dest: int32
    swapEndian32(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 4)
  else:
    ww.writeBuf(src.addr, 4)

proc writeUInt64*(ww: var WaveWriter, d: uint64) =
  var src = d
  if ww.swapEndian:
    var dest: int64
    swapEndian64(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 8)
  else:
    ww.writeBuf(src.addr, 8)

proc writeFloat32*(ww: var WaveWriter, d: float32) =
  var src = d
  if ww.swapEndian:
    var dest: float32
    swapEndian32(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 4)
  else:
    ww.writeBuf(src.addr, 4)

proc writeFloat64*(ww: var WaveWriter, d: float64) =
  var src = d
  if ww.swapEndian:
    var dest: float64
    swapEndian64(dest.addr, src.addr)
    ww.writeBuf(dest.addr, 8)
  else:
    ww.writeBuf(src.addr, 8)

# }}}
# {{{ Buffered write

# 8-bit

proc writeData*(ww: var WaveWriter, data: var openArray[int8|uint8],
                len: Natural) =
  ww.writeBuf(data[0].addr, len)

proc writeData*(ww: var WaveWriter, data: var openArray[int8|uint8]) =
  ww.writeBuf(data[0].addr, data.len)


# 16-bit

proc writeData16*(ww: var WaveWriter, data: pointer, len: Natural) =
  const WIDTH = 2
  assert len mod WIDTH == 0

  if ww.swapEndian:
    let writeBufferSize = (ww.writeBuffer.len div WIDTH) * WIDTH
    var
      src = cast[ptr UncheckedArray[uint8]](data)
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

proc writeData*(ww: var WaveWriter, data: var openArray[int16|uint16],
                len: Natural) =
  ww.writeData16(data[0].addr, len * 2)

proc writeData*(ww: var WaveWriter, data: var openArray[int16|uint16]) =
  ww.writeData16(data[0].addr, data.len * 2)


# 24-bit

proc writeData24Packed*(ww: var WaveWriter, data: pointer, len: Natural) =
  const WIDTH = 3
  assert len mod WIDTH == 0

  if ww.swapEndian:
    let writeBufferSize = (ww.writeBuffer.len div WIDTH) * WIDTH
    var
      src = cast[ptr UncheckedArray[uint8]](data)
      pos = 0
      destPos = 0

    while pos < len:
      ww.writeBuffer[destPos]   = src[pos+2]
      ww.writeBuffer[destPos+1] = src[pos+1]
      ww.writeBuffer[destPos+2] = src[pos]

      inc(destPos, WIDTH)
      inc(pos, WIDTH)
      if destPos >= writeBufferSize:
        ww.writeBuf(ww.writeBuffer[0].addr, writeBufferSize)
        destPos = 0

    if destPos > 0:
      ww.writeBuf(ww.writeBuffer[0].addr, destPos)
  else:
    ww.writeBuf(data, len)

proc writeData24Packed*(ww: var WaveWriter,
                        data: var openArray[int8|uint8], len: Natural) =
  ww.writeData24Packed(data[0].addr, len)

proc writeData24Packed*(ww: var WaveWriter, data: var openArray[int8|uint8]) =
  ww.writeData24Packed(data[0].addr, data.len)


proc writeData24Unpacked*(ww: var WaveWriter, data: pointer, len: Natural) =
  assert len mod 4 == 0

  let writeBufferSize = (ww.writeBuffer.len div 3) * 3
  var
    src = cast[ptr UncheckedArray[uint8]](data)
    pos = 0
    destPos = 0

  while pos < len:
    if ww.swapEndian:
      ww.writeBuffer[destPos]   = src[pos+2]
      ww.writeBuffer[destPos+1] = src[pos+1]
      ww.writeBuffer[destPos+2] = src[pos]
    else:
      ww.writeBuffer[destPos]   = src[pos]
      ww.writeBuffer[destPos+1] = src[pos+1]
      ww.writeBuffer[destPos+2] = src[pos+2]

    inc(destPos, 3)
    inc(pos, 4)
    if destPos >= writeBufferSize:
      ww.writeBuf(ww.writeBuffer[0].addr, writeBufferSize)
      destPos = 0

  if destPos > 0:
    ww.writeBuf(ww.writeBuffer[0].addr, destPos)

proc writeData24Unpacked*(ww: var WaveWriter,
                        data: var openArray[int32], len: Natural) =
  ww.writeData24Unpacked(data[0].addr, len * 4)

proc writeData24Unpacked*(ww: var WaveWriter, data: var openArray[int32]) =
  ww.writeData24Unpacked(data[0].addr, data.len * 4)


# 32-bit

proc writeData32*(ww: var WaveWriter, data: pointer, len: Natural) =
  const WIDTH = 4
  assert len mod WIDTH == 0

  if ww.swapEndian:
    let writeBufferSize = (ww.writeBuffer.len div WIDTH) * WIDTH
    var
      src = cast[ptr UncheckedArray[uint8]](data)
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

proc writeData*(ww: var WaveWriter,
                data: var openArray[int32|uint32|float32], len: Natural) =
  ww.writeData32(data[0].addr, len * 4)

proc writeData*(ww: var WaveWriter, data: var openArray[int32|uint32|float32]) =
  ww.writeData32(data[0].addr, data.len * 4)


# 64-bit

proc writeData64*(ww: var WaveWriter, data: pointer, len: Natural) =
  const WIDTH = 8
  assert len mod WIDTH == 0

  if ww.swapEndian:
    let writeBufferSize = (ww.writeBuffer.len div WIDTH) * WIDTH
    var
      src = cast[ptr UncheckedArray[uint8]](data)
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

proc writeData*(ww: var WaveWriter,
                data: var openArray[int64|uint64|float64], len: Natural) =
  ww.writeData64(data[0].addr, len * 8)

proc writeData*(ww: var WaveWriter, data: var openArray[int64|uint64|float64]) =
  ww.writeData64(data[0].addr, data.len * 8)

# }}}

proc startChunk*(ww: var WaveWriter, id: string) =
  ww.checkFileClosed()

  ww.trackChunkSize = false

  ww.writeFourCC(id)
  ww.chunkSizePos.add(getFilePos(ww.file))
  ww.writeUInt32(0)  # endChunk() will update this with the correct value
  ww.chunkSize.add(0)

  ww.trackChunkSize = true


proc endChunk*(ww: var WaveWriter) =
  ww.checkFileClosed()

  ww.trackChunkSize = false

  var chunkSize = ww.chunkSize.pop()
  if chunkSize mod 2 > 0:
    ww.writeInt8(0)  # padding byte (chunks must contain even number of bytes)
  setFilePos(ww.file, ww.chunkSizePos.pop())
  ww.writeUInt32(chunkSize.uint32)
  setFilePos(ww.file, 0, fspEnd)

  # Add real (potentially padded) chunk size to the parent chunk size
  if ww.chunkSize.len > 0:
    if chunkSize mod 2 > 0:
      inc(chunkSize)
    ww.chunkSize[ww.chunkSize.high] += chunkSize + CHUNK_HEADER_SIZE

  ww.trackChunkSize = true


proc writeWaveFile*(filename: string, format: WaveFormat, sampleRate: Natural,
                    numChannels: Natural, bufSize: Natural = 4096,
                    endianness = littleEndian): WaveWriter =
  var ww: WaveWriter
  ww.filename = filename

  if not open(ww.file, ww.filename, fmWrite):
    raise newException(WaveWriterError, "Error opening file for writing")

  ww.format = format
  ww.sampleRate = sampleRate
  ww.numChannels = numChannels

  ww.chunkSize = newSeq[int64]()
  ww.chunkSizePos = newSeq[int64]()
  ww.trackChunkSize = false
  ww.writeBuffer = newSeq[uint8](bufSize)
  ww.endianness = endianness
  ww.swapEndian = cpuEndian != endianness

  case ww.endianness:
  of littleEndian: ww.startChunk(FOURCC_RIFF_LE)
  of bigEndian:    ww.startChunk(FOURCC_RIFF_BE)

  ww.writeFourCC(FOURCC_WAVE)
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

  ww.writeUInt16(formatTag)
  ww.writeUInt16(ww.numChannels.uint16)
  ww.writeUInt32(ww.sampleRate.uint32)
  ww.writeUInt32(avgBytesPerSec)
  ww.writeUInt16(blockAlign)
  ww.writeUInt16(bitsPerSample)
  # TODO write extended header for float formats (and for 24 bit?)

  ww.endChunk()


proc writeCueChunk*(ww: var WaveWriter) =
  ww.startChunk(FOURCC_CUE)
  ww.writeUInt32(ww.regions.len.uint32)

  for id, region in ww.regions.pairs():
    ww.writeUInt32(id)          # cuePointId
    ww.writeUInt32(0)           # position (unused if dataChunkId is 'data')
    ww.writeFourCC(FOURCC_DATA) # dataChunkId
    ww.writeUInt32(0)           # chunkStart (unused if dataChunkId is 'data')
    ww.writeUInt32(0)           # blockStart (unused if dataChunkId is 'data')
    ww.writeUInt32(region.startFrame) # sampleOffset

  ww.endChunk()


proc writeListChunk*(ww: var WaveWriter) =
  ww.startChunk(FOURCC_LIST)
  ww.writeFourCC(FOURCC_ASSOC_DATA)

  for id, region in ww.regions.pairs():
    ww.startChunk(FOURCC_LABEL)
    ww.writeUInt32(id)            # cuePointId
    ww.writeString(region.label)  # text
    ww.writeUInt8(0)              # null terminator
    ww.endChunk()

  for id, region in ww.regions.pairs():
    if region.length > 0'u32:
      ww.startChunk(FOURCC_LABELED_TEXT)
      ww.writeUInt32(id)             # cuePointId
      ww.writeUInt32(region.length)  # sampleLength
      ww.writeFourCC(FOURCC_REGION)  # purposeId
      ww.writeUInt16(0)              # country (ignored)
      ww.writeUInt16(0)              # language (ignored)
      ww.writeUInt16(0)              # dialect (ignored)
      ww.writeUInt16(0)              # codePage (ignored)
      ww.endChunk()

  ww.endChunk()


proc startDataChunk*(ww: var WaveWriter) =
  ww.startChunk(FOURCC_DATA)

proc endFile*(ww: var WaveWriter) =
  ww.checkFileClosed()
  ww.endChunk()
  close(ww.file)
  ww.file = nil

# }}}

# vim: et:ts=2:sw=2:fdm=marker
