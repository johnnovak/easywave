## :Author: John Novak <john@johnnovak.net>
##

import endians, strformat, tables
import bufferedio

export tables

# {{{ Common

const
  FOURCC_RIFF_LE*      = "RIFF"  ## RIFF ID (little endian)
  FOURCC_RIFF_BE*      = "RIFX"  ## RIFF ID (big endian)
  FOURCC_WAVE*         = "WAVE"  ## WAVE format ID
  FOURCC_FORMAT*       = "fmt "  ## Format chunk ID
  FOURCC_DATA*         = "data"  ## Data chunk ID
  FOURCC_CUE*          = "cue "  ## Cue chunk ID
  FOURCC_LIST*         = "LIST"  ## List chunk ID
  FOURCC_ASSOC_DATA*   = "adtl"  ## Associated data list ID
  FOURCC_LABEL*        = "labl"  ## Label chunk ID
  FOURCC_LABELED_TEXT* = "ltxt"  ## Labeled text chunk ID
  FOURCC_REGION*       = "rgn "  ## Region purpose ID

  FOURCC_SIZE = 4
  CHUNK_HEADER_SIZE = 8

  WAVE_FORMAT_PCM = 1
  WAVE_FORMAT_IEEE_FLOAT = 3

type
  SampleFormat* = enum
    ## supported WAVE formats (bit-depths)
    sf8BitInteger  = (0,  "8-bit integer"),
    sf16BitInteger = (1, "16-bit integer"),
    sf24BitInteger = (2, "24-bit integer"),
    sf32BitInteger = (3, "32-bit integer"),
    sf32BitFloat   = (4, "32-bit IEEE float"),
    sf64BitFloat   = (5, "64-bit IEEE float")

  ChunkInfo* = object
    ## contains information about a chunk
    id*:      string  ## 4-char chunk ID (FourCC)
    size*:    uint32  ## size of chunk data in bytes
    filePos*: int64   ## file position of the chunk

  Region* = object
    ## represents a marker (if length is 0) or a region
    startFrame*: uint32  ## start sample frame of the marker/region
    length*:     uint32  ## length of the region in frames (0 for markers)
    label*:      string  ## text label

  RegionTable* = OrderedTable[uint32, Region]

# }}}
# {{{ Reader

type
  WaveReader* = object
    # read-only properties
    format:        SampleFormat
    sampleRate:    Natural
    numChannels:   Natural
    chunks:        seq[ChunkInfo]
    regions:       RegionTable
    currChunk:     ChunkInfo

    # private
    reader:           BufferedReader
    riffChunkSize:    uint32
    nextChunkPos:     int64
    chunkPos:         int64
    checkChunkLimits: bool

  WaveReaderError* = object of Exception


proc initWaveReader(): WaveReader =
  result.regions = initOrderedTable[uint32, Region]()
  result.checkChunkLimits = true

func filename*(wr: WaveReader): string {.inline.} =
  ## The filename of the WAVE file.
  wr.reader.filename

func endianness*(wr: WaveReader): Endianness {.inline.} =
  ## The endianness of the WAVE file.
  wr.reader.endianness

func format*(wr: WaveReader): SampleFormat {.inline.} =
  ## The format (bit-depth) of the audio data (populated by ``parseWaveFile``
  ## and ``readFormatChunk``).
  wr.format

func sampleRate*(wr: WaveReader): Natural {.inline.} =
  ## The sample rate of audio data (populated by ``parseWaveFile`` and
  ## ``readFormatChunk``).
  wr.sampleRate

func numChannels*(wr: WaveReader): Natural {.inline.} =
  ## The number of channels stored in the audio data (populated by
  ## ``parseWaveFile`` and ``readFormatChunk``).
  wr.numChannels

func chunks*(wr: WaveReader): seq[ChunkInfo] {.inline.} =
  ## A sequence containing info about the chunks found in the WAVE file (populated
  ## by ``parseWaveFile`` and ``buildChunkList``).
  wr.chunks

func regions*(wr: WaveReader): RegionTable {.inline.} =
  ## TODO
  wr.regions

func currChunk*(wr: WaveReader): ChunkInfo {.inline.} =
  ## TODO
  wr.currChunk

proc checkReadLen(wr: WaveReader, numBytes: Natural) =
  let chunkSize = wr.currChunk.size.int64
  if wr.chunkPos + numBytes > chunkSize:
    raise newException(WaveReaderError,
      "Cannot read past the end of the chunk, " &
      fmt"chunk size: {chunkSize}, chunk pos: {wr.chunkPos}, " &
      fmt"bytes to read: {numBytes}")

proc doCheckChunkLimits(wr: var WaveReader, numBytes: Natural) =
  if wr.checkChunkLimits:
    wr.checkReadLen(numBytes)

proc incChunkPos(wr: var WaveReader, numBytes: Natural) =
  inc(wr.chunkPos, numBytes)

template readBuf(wr: var WaveReader, numBytes: Natural, read: untyped) =
  doCheckChunkLimits(wr, numBytes)
  read
  incChunkPos(wr, numBytes)

template readSingle(wr: var WaveReader, numBytes: Natural,
                    read: untyped): untyped =
  doCheckChunkLimits(wr, numBytes)
  result = read
  incChunkPos(wr, numBytes)

# {{{ Single-value read

proc readInt8*(wr: var WaveReader): int8 =
  ## Reads a single ``int8`` value from the current file position. Raises
  ## a ``WaveReadError`` on read errors.
  wr.readSingle(sizeof(result), wr.reader.readInt8())

proc readInt16*(wr: var WaveReader): int16 =
  ## Reads a single ``int16`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  wr.readSingle(sizeof(result), wr.reader.readInt16())

proc readInt32*(wr: var WaveReader): int32 =
  ## Reads a single ``int32`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  wr.readSingle(sizeof(result), wr.reader.readInt32())

proc readInt64*(wr: var WaveReader): int64 =
  ## Reads a single ``int64`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  wr.readSingle(sizeof(result), wr.reader.readInt64())

proc readUInt8*(wr: var WaveReader): uint8 =
  ## Reads a single ``uint8`` value from the current file position. Raises
  ## a ``WaveReadError`` on read errors.
  wr.readSingle(sizeof(result), wr.reader.readUInt8())

proc readUInt16*(wr: var WaveReader): uint16 =
  ## Reads a single ``uint16`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  wr.readSingle(sizeof(result), wr.reader.readUInt16())

proc readUInt32*(wr: var WaveReader): uint32 =
  ## Reads a single ``uint32`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  wr.readSingle(sizeof(result), wr.reader.readUInt32())

proc readUInt64*(wr: var WaveReader): uint64 =
  ## Reads a single ``uint64`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  wr.readSingle(sizeof(result), wr.reader.readUInt64())

proc readFloat32*(wr: var WaveReader): float32 =
  ## Reads a single ``float32`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  wr.readSingle(sizeof(result), wr.reader.readFloat32())

proc readFloat64*(wr: var WaveReader): float64 =
  ## Reads a single ``float64`` value from the current file position and
  ## performs endianness conversion if necessary. Raises a ``WaveReadError`` on
  ## read errors.
  wr.readSingle(sizeof(result), wr.reader.readFloat64())

proc readString*(wr: var WaveReader, numBytes: Natural): string =
  ## TODO
  wr.readSingle(numBytes, wr.reader.readString(numBytes))

proc readFourCC*(wr: var WaveReader): string =
  ## Reads a 4-byte FourCC as a string from the current file position. Raises
  ## a ``WaveReadError`` on read errors.
  wr.readSingle(4, wr.reader.readString(4))

# }}}
# {{{ Buffered read (pointer variants)

proc readData8*(wr: var WaveReader, dest: pointer, numItems: Natural) =
  ## TODO
  wr.readBuf(numItems, wr.reader.readData8(dest, numItems))

proc readData16*(wr: var WaveReader, dest: pointer, numItems: Natural) =
  ## TODO
  wr.readBuf(numItems * 2, wr.reader.readData16(dest, numItems))

proc readData24Unpacked*(wr: var WaveReader, dest: pointer, numItems: Natural) =
  ## TODO
  wr.readBuf(numItems * 4, wr.reader.readData24Unpacked(dest, numItems))

proc readData24Packed*(wr: var WaveReader, dest: pointer, numItems: Natural) =
  ## TODO
  wr.readBuf(numItems * 3, wr.reader.readData24Packed(dest, numItems))

proc readData32*(wr: var WaveReader, dest: pointer, numItems: Natural) =
  ## TODO
  wr.readBuf(numItems * 4, wr.reader.readData32(dest, numItems))

proc readData64*(wr: var WaveReader, dest: pointer, numItems: Natural) =
  ## TODO
  wr.readBuf(numItems * 8, wr.reader.readData64(dest, numItems))

# }}}
# {{{ Buffered read (openArray variants)
proc readData24Unpacked*(wr: var WaveReader, dest: var openArray[int32],
                         numItems: Natural) =
  ## TODO
  wr.readBuf(numItems * 4, wr.reader.readData24Unpacked(dest, numItems))

proc readData24Unpacked*(wr: var WaveReader, dest: var openArray[int32]) =
  ## TODO
  wr.readData24Unpacked(dest, dest.len)

proc readData24Packed*(wr: var WaveReader, dest: var openArray[uint8],
                       numItems: Natural) =
  ## TODO
  wr.readBuf(numItems * 3, wr.reader.readData24Packed(dest, numItems))

proc readData24Packed*(wr: var WaveReader, dest: var openArray[uint8]) =
  ## TODO
  wr.readData24Packed(dest, dest.len div 3)

# TODO find better name
type AllDataBufferTypes = int8|uint8|int16|uint16|int32|uint32|float32|int64|uint64|float64

proc getByteWidth(arr: var openArray[AllDataBufferTypes]): int =
  if   typeof(arr) is openArray[int8|uint8]:           result = 1
  elif typeof(arr) is openArray[int16|uint16]:         result = 2
  elif typeof(arr) is openArray[int32|uint32|float32]: result = 4
  elif typeof(arr) is openArray[int64|uint64|float64]: result = 8

proc readData*(wr: var WaveReader, dest: var openArray[AllDataBufferTypes],
               numItems: Natural) =
  ## Reads `numItems` number of ``int8|uint8`` values into `dest` from the
  ## current file position and performs endianness conversion if necessary.
  ## Raises a ``WaveReadError`` on read errors.
  # TODO
  wr.readBuf(numItems * getByteWidth(dest), wr.reader.readData(dest, numItems))

proc readData*(wr: var WaveReader, dest: var openArray[AllDataBufferTypes]) =
  # TODO
  wr.readData(dest, dest.len)

# }}}

proc isOdd(n: SomeNumber): bool = n mod 2 == 1

proc setNextChunkPos(wr: var WaveReader, ci: ChunkInfo) =
  wr.nextChunkPos = ci.filePos + ci.size.int64 + CHUNK_HEADER_SIZE
  if isOdd(ci.size):
    inc(wr.nextChunkPos)

proc setCurrentChunk*(wr: var WaveReader, ci: ChunkInfo) =
  ## TODO
  wr.currChunk = ci
  wr.setNextChunkPos(ci)
  wr.chunkPos = 0
  setFilePos(wr.reader.file, ci.filePos + CHUNK_HEADER_SIZE)

proc hasNextChunk*(wr: var WaveReader): bool =
  ## Returns true iff the wave file has more chunks.
  result = wr.nextChunkPos < CHUNK_HEADER_SIZE + wr.riffChunkSize.int64

proc nextChunk*(wr: var WaveReader): ChunkInfo =
  ## Finds the next chunk in the file; raises a ``WaveReadError`` if the end
  ## of file has been reached. Returns chunk info and sets the file pointer to
  ## the start of the chunk if successful.
  wr.checkChunkLimits = false

  if wr.nextChunkPos >= CHUNK_HEADER_SIZE + wr.riffChunkSize.int64:
    raise newException(WaveReaderError,
                       "Cannot seek to next chunk, end of file reached")

  setFilePos(wr.reader.file, wr.nextChunkPos)

  var ci: ChunkInfo
  ci.id = wr.readFourCC()
  ci.size = wr.readUInt32()
  ci.filePos = wr.nextChunkPos

  wr.setCurrentChunk(ci)
  result = ci

  wr.checkChunkLimits = true


proc setChunkPos(wr: var WaveReader, pos: int64, mode: FileSeekPos = fspSet) =
  let chunkSize = wr.currChunk.size.int64
  var newPos: int64
  case mode
  of fspSet: newPos = pos
  of fspCur: newPos = wr.chunkPos + pos
  of fspEnd: newPos = chunkSize - pos

  if newPos < 0 or newPos > chunkSize-1:
    raise newException(WaveReaderError, "Invalid chunk position")

  setFilePos(wr.reader.file, wr.currChunk.filePos + CHUNK_HEADER_SIZE + newPos)
  wr.chunkPos = newPos


proc buildChunkList*(wr: var WaveReader) =
  ## Finds all top-level chunks in the WAVE file and stores the result as
  ## a list of ``ChunkInfo`` objects that can be accessed through the
  ## ``chunks`` property. Raises a ``WaveReadError`` on read errors.
  while wr.hasNextChunk():
    var ci = wr.nextChunk()
    wr.chunks.add(ci)


proc findChunk*(wr: WaveReader, chunkId: string): tuple[found: bool,
                                                        chunk: ChunkInfo] =
  ## TODO
  for ci in wr.chunks:
    if ci.id == chunkId:
      return (true, ci)


proc readFormatChunk*(wr: var WaveReader) =
  ## Reads the format chunk from the current file position and sets the format
  ## info in the ``WaveReader`` object on success. Raises
  ## a ``WaveReaderError`` on any error (e.g. read error, chunk not found,
  ## unsupported format etc.).
  {.hint[XDeclaredButNotUsed]: off.}
  let
    format         = wr.readUInt16()
    channels       = wr.readUInt16()
    samplesPerSec  = wr.readUInt32()
    avgBytesPerSec = wr.readUInt32()  # ignored
    blockAlign     = wr.readUInt16()  # ignored
    bitsPerSample  = wr.readUInt16()

  case format
  of WAVE_FORMAT_PCM:
    case bitsPerSample:
    of  8: wr.format = sf8BitInteger
    of 16: wr.format = sf16BitInteger
    of 24: wr.format = sf24BitInteger
    of 32: wr.format = sf32BitInteger
    else:
      raise newException(WaveReaderError,
                         fmt"Unsupported integer bit depth: {bitsPerSample}")

  of WAVE_FORMAT_IEEE_FLOAT:
    case bitsPerSample:
    of 32: wr.format = sf32BitFloat
    of 64: wr.format = sf64BitFloat
    else:
      raise newException(WaveReaderError,
                         fmt"Unsupported float bit depth: {bitsPerSample}")
  else:
    raise newException(WaveReaderError,
                       fmt"Unsupported format code: 0x{format:04x}")

  wr.numChannels = channels
  wr.sampleRate = samplesPerSec


proc readRegionIdsAndStartOffsetsFromCueChunk(wr: var WaveReader) =
  let numCuePoints = wr.readUInt32()

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
        if not wr.regions.hasKey(cuePointId):
          var region: Region
          wr.regions[cuePointId] = region
        wr.regions[cuePointId].startFrame = sampleOffset


proc readRegionLabelsAndEndOffsetsFromListChunk(wr: var WaveReader) =
  let assocDataListId = wr.readFourCC()
  if assocDataListId != FOURCC_ASSOC_DATA:
    raise newException(WaveReaderError,
      fmt"Associated data list ID ('{FOURCC_ASSOC_DATA}') not found)")
  var pos = 4

  while pos.uint32 < wr.currChunk.size:
    let subChunkId   = wr.readFourCC()
    var subChunkSize = wr.readUInt32()

    case subChunkId
    of FOURCC_LABEL:
      let cuePointId = wr.readUInt32()

      var textSize = subChunkSize.int - 4
      # TODO use read string
      var text = newString(textSize-1)  # don't read the terminating zero byte
      wr.readData8(text[0].addr, textSize-1)

      if wr.regions.hasKey(cuePointId):
        wr.regions[cuePointId].label = text

      setFilePos(wr.reader.file, 1, fspCur)  # skip terminating zero
      if isOdd(textSize):
        inc(textSize)
        setFilePos(wr.reader.file, 1, fspCur)
      inc(pos, CHUNK_HEADER_SIZE + 4 + textSize)

    of FOURCC_LABELED_TEXT:
      let
        cuePointId   = wr.readUInt32()
        sampleLength = wr.readUInt32()
        purposeId    = wr.readFourCC()

      if purposeId == FOURCC_REGION:
        if wr.regions.hasKey(cuePointId):
          wr.regions[cuePointId].length = sampleLength

      if isOdd(subChunkSize):
        inc(subChunkSize)
      inc(pos, CHUNK_HEADER_SIZE + subChunkSize.int)
      setFilePos(wr.reader.file, subChunkSize.int64 - (4+4+4), fspCur)

    else:
      if isOdd(subChunkSize):
        inc(subChunkSize)
      inc(pos, CHUNK_HEADER_SIZE + subChunkSize.int)
      setFilePos(wr.reader.file, subChunkSize.int64, fspCur)


proc readRegions*(wr: var WaveReader, cueChunk, listChunk: ChunkInfo) =
  ## TODO
  wr.setCurrentChunk(cueChunk)
  wr.readRegionIdsAndStartOffsetsFromCueChunk()
  wr.setCurrentChunk(listChunk)
  wr.readRegionLabelsAndEndOffsetsFromListChunk()


proc readWaveHeader(wr: var WaveReader) =
  wr.checkChunkLimits = false

  let id = wr.readFourCC()
  case id
  of FOURCC_RIFF_LE: wr.reader.endianness = littleEndian
  of FOURCC_RIFF_BE: wr.reader.endianness = bigEndian
  else:
    raise newException(WaveReaderError, "Not a WAVE file " &
                fmt"('{FOURCC_RIFF_LE}' or '{FOURCC_RIFF_BE}' chunk not found)")

  wr.riffChunkSize = wr.readUInt32()

  if wr.readFourCC() != FOURCC_WAVE:
    raise newException(WaveReaderError,
                       "Not a WAVE file ('{FOURCC_WAVE}' chunk not found)")

  wr.nextChunkPos = FOURCC_SIZE + CHUNK_HEADER_SIZE
  wr.checkChunkLimits = true


proc openWaveFile*(filename: string, bufSize: Natural = 4096): WaveReader =
  ## Opens a WAVE file for reading but does not parse anything else than the
  ## master RIFF header. Raises a ``WaveReaderError`` if the file is not
  ## a valid WAVE file and on read errors.
  var wr = initWaveReader()
  try:
    wr.reader = openFile(filename)
  except IOError:
    raise newException(WaveReaderError, fmt"Error opening file for reading")

  wr.chunks = newSeq[ChunkInfo]()
  wr.readWaveHeader()
  result = wr


proc parseWaveFile*(filename: string, readRegions: bool = false,
                    bufSize: Natural = 4096): WaveReader =
  ## Opens a WAVE file for reading, builds the chunk list, reads the format
  ## chunk, reads the markers and regions if `readRegions` is true, then seeks
  ## to the start of the data chunk. Raises a ``WaveReaderError`` if the file
  ## is not a valid WAVE file and on read errors.
  var wr = openWaveFile(filename, bufSize)

  wr.buildChunkList()

  let (fmtFound, fmtChunk) = wr.findChunk(FOURCC_FORMAT)
  if fmtFound:
    wr.setCurrentChunk(fmtChunk)
    wr.readFormatChunk()
  else:
    raise newException(WaveReaderError, fmt"'{FOURCC_FORMAT}' chunk not found")

  if readRegions:
    let (cueFound, cueChunk) = wr.findChunk(FOURCC_CUE)
    let (listFound, listChunk) = wr.findChunk(FOURCC_LIST)
    if cueFound and listFound:
      wr.readRegions(cueChunk, listChunk)

  let (dataFound, dataChunk) = wr.findChunk(FOURCC_DATA)
  if dataFound:
    wr.setCurrentChunk(dataChunk)
    return wr
  else:
    raise newException(WaveReaderError, fmt"'{FOURCC_DATA}' chunk not found")


proc close*(wr: var WaveReader) =
  # TODO
  wr.reader.close()

# }}}
# {{{ Writer
#
type
  WaveWriter* = object
    # read-only properties
    format:         SampleFormat
    sampleRate:     Natural
    numChannels:    Natural
    regions:        RegionTable

    # private
    writer:         BufferedWriter
    chunkSize:      seq[int64]
    chunkSizePos:   seq[int64]
    trackChunkSize: bool


proc initWaveWriter*(): WaveWriter =
  ## TODO
  result.regions = initOrderedTable[uint32, Region]()

func filename*(ww: WaveWriter): string {.inline.} =
  ## TODO
  ww.writer.filename

func endianness*(ww: WaveWriter): Endianness {.inline.} =
  ## TODO
  ww.writer.endianness

func format*(ww: WaveWriter): SampleFormat {.inline.} =
  ## TODO
  ww.format

func sampleRate*(ww: WaveWriter): Natural {.inline.} =
  ## TODO
  ww.sampleRate

func numChannels*(ww: WaveWriter): Natural {.inline.} =
  ## TODO
  ww.numChannels

func `regions=`*(ww: var WaveWriter, regions: RegionTable) {.inline.} =
  ## TODO
  ww.regions = regions

func regions*(ww: WaveWriter): RegionTable {.inline.} =
  ## TODO
  ww.regions

proc checkFileClosed(ww: var WaveWriter) =
  if ww.writer.file == nil:
    raise newException(WaveReaderError, "File closed")

proc incChunkSize(ww: var WaveWriter, numBytes: Natural) =
  if ww.trackChunkSize and ww.chunkSize.len > 0:
    inc(ww.chunkSize[ww.chunkSize.high], numBytes)

template writeInternal(ww: var WaveWriter, numBytes: Natural, write: untyped) =
  checkFileClosed(ww)
  write
  incChunkSize(ww, numBytes)

# {{{ Single-value write

proc writeInt8*(ww: var WaveWriter, d: int8) =
  ww.writeInternal(sizeof(d), ww.writer.writeInt8(d))

proc writeInt16*(ww: var WaveWriter, d: int16) =
  ww.writeInternal(sizeof(d), ww.writer.writeInt16(d))

proc writeInt32*(ww: var WaveWriter, d: int32) =
  ww.writeInternal(sizeof(d), ww.writer.writeInt32(d))

proc writeInt64*(ww: var WaveWriter, d: int64) =
  ww.writeInternal(sizeof(d), ww.writer.writeInt64(d))

proc writeUInt8*(ww: var WaveWriter, d: uint8) =
  ww.writeInternal(sizeof(d), ww.writer.writeUInt8(d))

proc writeUInt16*(ww: var WaveWriter, d: uint16) =
  ww.writeInternal(sizeof(d), ww.writer.writeUInt16(d))

proc writeUInt32*(ww: var WaveWriter, d: uint32) =
  ww.writeInternal(sizeof(d), ww.writer.writeUInt32(d))

proc writeUInt64*(ww: var WaveWriter, d: uint64) =
  ww.writeInternal(sizeof(d), ww.writer.writeUInt64(d))

proc writeFloat32*(ww: var WaveWriter, d: float32) =
  ww.writeInternal(sizeof(d), ww.writer.writeFloat32(d))

proc writeFloat64*(ww: var WaveWriter, d: float64) =
  ww.writeInternal(sizeof(d), ww.writer.writeFloat64(d))

proc writeString*(ww: var WaveWriter, s: string) =
  ww.writeInternal(s.len, ww.writer.writeString(s))

proc writeString*(ww: var WaveWriter, s: string, numBytes: Natural) =
  ww.writeInternal(numBytes, ww.writer.writeString(s, numBytes))

proc writeFourCC*(ww: var WaveWriter, fourCC: string) =
  ww.writeInternal(4, ww.writer.writeString(fourCC, 4))

# }}}
# {{{ Buffered write (pointer variants)

proc writeData8*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems, ww.writer.writeData8(data, numItems))

proc writeData16*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * 2, ww.writer.writeData16(data, numItems))

proc writeData32*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * 4, ww.writer.writeData32(data, numItems))

proc writeData24Packed*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * 3, ww.writer.writeData24Packed(data, numItems))

proc writeData24Unpacked*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * 4, ww.writer.writeData24Unpacked(data, numItems))

proc writeData64*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * 8, ww.writer.writeData64(data, numItems))

# }}}
# {{{ Buffered write (openArray variants)

proc writeData*(ww: var WaveWriter, src: var openArray[AllDataBufferTypes],
                numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * getByteWidth(src),
                   ww.writer.writeData(src, numItems))

proc writeData*(ww: var WaveWriter, src: var openArray[AllDataBufferTypes]) =
  ## TODO
  ww.writeData(src, src.len)

proc writeData24Packed*(ww: var WaveWriter,
                        src: var openArray[int8|uint8], numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * 3,
                   ww.writer.writeData24Packed(src, numItems))

proc writeData24Packed*(ww: var WaveWriter, src: var openArray[int8|uint8]) =
  ## TODO
  ww.writeData24Packed(src, src.len div 3)

proc writeData24Unpacked*(ww: var WaveWriter, src: var openArray[int32|uint32],
                          numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * 4,
                   ww.writer.writeData24Unpacked(src, numItems))

proc writeData24Unpacked*(ww: var WaveWriter,
                          src: var openArray[int32|uint32]) =
  ## TODO
  ww.writeData24Unpacked(src, src.len)

# }}}

proc startChunk*(ww: var WaveWriter, id: string) =
  ## TODO
  ww.checkFileClosed()

  ww.trackChunkSize = false

  ww.writeFourCC(id)
  ww.chunkSizePos.add(getFilePos(ww.writer.file))
  ww.writeUInt32(0)  # endChunk() will update this with the correct value
  ww.chunkSize.add(0)

  ww.trackChunkSize = true


proc endChunk*(ww: var WaveWriter) =
  ## TODO
  ww.checkFileClosed()

  ww.trackChunkSize = false

  var chunkSize = ww.chunkSize.pop()
  if chunkSize mod 2 > 0:
    ww.writeInt8(0)  # padding byte (chunks must contain even number of bytes)
  setFilePos(ww.writer.file, ww.chunkSizePos.pop())
  ww.writeUInt32(chunkSize.uint32)
  setFilePos(ww.writer.file, 0, fspEnd)

  # Add real (potentially padded) chunk size to the parent chunk size
  if ww.chunkSize.len > 0:
    if chunkSize mod 2 > 0:
      inc(chunkSize)
    ww.chunkSize[ww.chunkSize.high] += chunkSize + CHUNK_HEADER_SIZE

  ww.trackChunkSize = true


proc writeWaveFile*(filename: string, format: SampleFormat, sampleRate: Natural,
                    numChannels: Natural, bufSize: Natural = 4096,
                    endianness = littleEndian): WaveWriter =
  ## TODO
  var ww = initWaveWriter()

  ww.writer = createFile(filename, bufSize, endianness)

  ww.format = format
  ww.sampleRate = sampleRate
  ww.numChannels = numChannels

  ww.chunkSize = newSeq[int64]()
  ww.chunkSizePos = newSeq[int64]()
  ww.trackChunkSize = false

  case ww.writer.endianness:
  of littleEndian: ww.startChunk(FOURCC_RIFF_LE)
  of bigEndian:    ww.startChunk(FOURCC_RIFF_BE)

  ww.writeFourCC(FOURCC_WAVE)
  result = ww


proc writeFormatChunk*(ww: var WaveWriter) =
  ## TODO
  ww.startChunk(FOURCC_FORMAT)

  var formatTag: uint16
  var bitsPerSample: uint16

  case ww.format
  of sf8BitInteger:  formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 8
  of sf16BitInteger: formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 16
  of sf24BitInteger: formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 24
  of sf32BitInteger: formatTag = WAVE_FORMAT_PCM;        bitsPerSample = 32
  of sf32BitFloat:   formatTag = WAVE_FORMAT_IEEE_FLOAT; bitsPerSample = 32
  of sf64BitFloat:   formatTag = WAVE_FORMAT_IEEE_FLOAT; bitsPerSample = 64

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
  ## TODO
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
  ## TODO
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
  ## TODO
  ww.startChunk(FOURCC_DATA)

proc close*(ww: var WaveWriter) =
  ww.checkFileClosed()
  ww.endChunk()
  ww.writer.close()

# }}}

# vim: et:ts=2:sw=2:fdm=marker
