## :Author: John Novak <john@johnnovak.net>
##

import endians, strformat, tables
import bufferedio

export tables

# {{{ Common

const
  FOURCC_WAVE*         = "WAVE"  ## WAVE format ID
  FOURCC_FORMAT*       = "fmt "  ## Format chunk ID
  FOURCC_DATA*         = "data"  ## Data chunk ID
  FOURCC_CUE*          = "cue "  ## Cue chunk ID
  FOURCC_LIST*         = "LIST"  ## List chunk ID
  FOURCC_ASSOC_DATA*   = "adtl"  ## Associated data list ID
  FOURCC_LABEL*        = "labl"  ## Label chunk ID
  FOURCC_LABELED_TEXT* = "ltxt"  ## Labeled text chunk ID
  FOURCC_REGION*       = "rgn "  ## Region purpose ID

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

  Region* = object
    ## represents a marker (if length is 0) or a region
    startFrame*: uint32  ## start sample frame of the marker/region
    length*:     uint32  ## length of the region in frames (0 for markers)
    label*:      string  ## text label

  RegionTable* = OrderedTable[uint32, Region]

# }}}
# {{{ Reader

type
  WaveFormat* = object
    format*:        SampleFormat
    sampleRate*:    Natural
    numChannels*:   Natural

using rr: RiffReader

proc readData24Unpacked*(rr; dest: pointer, numItems: Natural) =
  const WIDTH = 3
  var
    bytesToRead = numItems * WIDTH
    readBufferSize = br.readBuffer.len - br.readBuffer.len mod WIDTH
    destArr = cast[ptr UncheckedArray[int32]](dest)
    destPos = 0

  while bytesToRead > 0:
    let count = min(readBufferSize, bytesToRead)
    br.readBuf(br.readBuffer[0].addr, count)
    var pos = 0
    while pos < count:
      var v: int32
      case br.endianness:
      of littleEndian:
        v = br.readBuffer[pos].int32 or
            (br.readBuffer[pos+1].int32 shl 8) or
            ashr(br.readBuffer[pos+2].int32 shl 24, 8)
      of bigEndian:
        v = br.readBuffer[pos+2].int32 or
            (br.readBuffer[pos+1].int32 shl 8) or
            ashr(br.readBuffer[pos].int32 shl 24, 8)
      destArr[destPos] = v
      inc(pos, WIDTH)
      inc(destPos)

    dec(bytesToRead, count)


proc readData24Unpacked*(br: var BufferedReader,
                         dest: var openArray[int32|uint32], numItems: Natural) =
  assert numItems <= dest.len
  br.readData24Unpacked(dest[0].addr, numItems)


proc readData24Unpacked*(br: var BufferedReader,
                         dest: var openArray[int32|uint32]) =
  br.readData24Unpacked(dest, dest.len)


proc readData24Packed*(br: var BufferedReader, dest: pointer,
                       numItems: Natural) =
  const WIDTH = 3
  var
    bytesToRead = numItems * WIDTH
    readBufferSize = br.readBuffer.len - br.readBuffer.len mod WIDTH
    destArr = cast[ptr UncheckedArray[uint8]](dest)
    destPos = 0

  while bytesToRead > 0:
    let count = min(readBufferSize, bytesToRead)
    br.readBuf(br.readBuffer[0].addr, count)
    var pos = 0
    while pos < count:
      if br.swapEndian:
        destArr[destPos]   = br.readBuffer[pos+2]
        destArr[destPos+1] = br.readBuffer[pos+1]
        destArr[destPos+2] = br.readBuffer[pos]
      else:
        destArr[destPos]   = br.readBuffer[pos]
        destArr[destPos+1] = br.readBuffer[pos+1]
        destArr[destPos+2] = br.readBuffer[pos+2]
      inc(pos, WIDTH)
      inc(destPos, WIDTH)

    dec(bytesToRead, count)


proc readData24Packed*(br: var BufferedReader, dest: var openArray[int8|uint8],
                       numItems: Natural) =
  assert numItems <= dest.len div 3
  br.readData24Packed(dest[0].addr, dest.len div 3)


proc readData24Packed*(br: var BufferedReader, dest: var openArray[int8|uint8]) =
  br.readData24Packed(dest, dest.len div 3)



proc readFormatChunk*(rr) =
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


proc readRegionIdsAndStartOffsetsFromCueChunk(rr) =
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


proc readRegionLabelsAndEndOffsetsFromListChunk() =
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


proc parseWaveFile*(filename: string, readRegions: bool = false,
                    bufSize: Natural = 4096): WaveReader =
  var wr = openWaveFile(filename, bufSize)

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

  WaveWriterError* = object of Exception

proc initWaveWriter*(): WaveWriter =
  ## TODO
  result.regions = initOrderedTable[uint32, Region]()

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

proc writeData24Packed*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * 3, ww.writer.writeData24Packed(data, numItems))

proc writeData24Unpacked*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ## TODO
  ww.writeInternal(numItems * 4, ww.writer.writeData24Unpacked(data, numItems))

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


# 24-bit

proc writeData24Packed*(bw: var BufferedWriter, src: pointer,
                        numItems: Natural) =
  ## TODO
  const WIDTH = 3
  let numBytes = numItems * WIDTH

  if bw.swapEndian:
    let writeBufferSize = bw.writeBuffer.len - bw.writeBuffer.len mod WIDTH
    var
      src = cast[ptr UncheckedArray[uint8]](src)
      pos = 0
      destPos = 0

    while pos < numBytes:
      bw.writeBuffer[destPos]   = src[pos+2]
      bw.writeBuffer[destPos+1] = src[pos+1]
      bw.writeBuffer[destPos+2] = src[pos]

      inc(destPos, WIDTH)
      inc(pos, WIDTH)
      if destPos >= writeBufferSize:
        bw.writeBuf(bw.writeBuffer[0].addr, writeBufferSize)
        destPos = 0

    if destPos > 0:
      bw.writeBuf(bw.writeBuffer[0].addr, destPos)
  else:
    bw.writeBuf(src, numBytes)


proc writeData24Packed*(bw: var BufferedWriter,
                        src: var openArray[int8|uint8], numItems: Natural) =
  ## TODO
  assert numItems * 3 <= src.len
  bw.writeData24Packed(src[0].addr, numItems)


proc writeData24Packed*(bw: var BufferedWriter,
                        src: var openArray[int8|uint8]) =
  ## TODO
  bw.writeData24Packed(src, src.len div 3)


proc writeData24Unpacked*(bw: var BufferedWriter, src: pointer,
                          numItems: Natural) =
  ## TODO
  let numBytes = numItems * 4

  let writeBufferSize = bw.writeBuffer.len - bw.writeBuffer.len mod 3
  var
    src = cast[ptr UncheckedArray[uint8]](src)
    pos = 0
    destPos = 0

  while pos < numBytes:
    if bw.swapEndian:
      bw.writeBuffer[destPos]   = src[pos+2]
      bw.writeBuffer[destPos+1] = src[pos+1]
      bw.writeBuffer[destPos+2] = src[pos]
    else:
      bw.writeBuffer[destPos]   = src[pos]
      bw.writeBuffer[destPos+1] = src[pos+1]
      bw.writeBuffer[destPos+2] = src[pos+2]

    inc(destPos, 3)
    inc(pos, 4)
    if destPos >= writeBufferSize:
      bw.writeBuf(bw.writeBuffer[0].addr, writeBufferSize)
      destPos = 0

  if destPos > 0:
    bw.writeBuf(bw.writeBuffer[0].addr, destPos)


proc writeData24Unpacked*(bw: var BufferedWriter,
                          src: var openArray[int32|uint32], numItems: Natural) =
  ## TODO
  assert numItems <= src.len
  bw.writeData24Unpacked(src[0].addr, numItems)


proc writeData24Unpacked*(bw: var BufferedWriter,
                          src: var openArray[int32|uint32]) =
  ## TODO
  bw.writeData24Unpacked(src, src.len)



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


# vim: et:ts=2:sw=2:fdm=marker
