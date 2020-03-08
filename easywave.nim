## :Author: John Novak <john@johnnovak.net>
##

import endians
import options
import strformat
import tables

import riff

export riff
export tables

# {{{ Common

const
  FourCC_WAVE_fmt*  = "fmt "  ## Format chunk ID
  FourCC_WAVE_data* = "data"  ## Data chunk ID
  FourCC_WAVE_cue*  = "cue "  ## Cue chunk ID
  FourCC_WAVE_adtl* = "adtl"  ## Associated data list ID
  FourCC_WAVE_labl* = "labl"  ## Label chunk ID
  FourCC_WAVE_ltxt* = "ltxt"  ## Labeled text chunk ID
  FourCC_WAVE_rgn*  = "rgn "  ## Region purpose ID

  WaveFormatPCM = 1
  WaveFormatIEEEFloat = 3

type
  SampleFormat* = enum
    sfPCM       = (0, "PCM"),
    sfIEEEFloat = (1, "IEEE Float"),
    sfUnknown   = (2, "Unknown")

  Region* = object
    ## represents a marker (if length is 0) or a region
    startFrame*: uint32  ## start sample frame of the marker/region
    length*:     uint32  ## length of the region in frames (0 for markers)
    label*:      string  ## text label

  RegionTable* = OrderedTable[uint32, Region]

  WaveFormat* = object
    sampleFormat*:  SampleFormat
    bitsPerSample*: Natural
    sampleRate*:    Natural
    numChannels*:   Natural

# }}}
# {{{ Reader

type
  WaveInfo* = object
    reader*:     RiffReader
    format*:     WaveFormat
    regions*:    RegionTable
    dataCursor*: Cursor

using rr: RiffReader

#[
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
]#


proc readFormatChunk*(rr): WaveFormat =
  ## Reads the format chunk from the current file position and sets the format
  ## info in the ``WaveReader`` object on success. Raises
  ## a ``WaveReaderError`` on any error (e.g. read error, chunk not found,
  ## unsupported format etc.).
  {.hint[XDeclaredButNotUsed]: off.}
  let
    format         = rr.read(uint16)
    channels       = rr.read(uint16)
    samplesPerSec  = rr.read(uint32)
    avgBytesPerSec = rr.read(uint32)  # ignored
    blockAlign     = rr.read(uint16)  # ignored
    bitsPerSample  = rr.read(uint16)

  var wf: WaveFormat
  wf.bitsPerSample = bitsPerSample
  wf.numChannels = channels
  wf.sampleRate = samplesPerSec

  wf.sampleFormat = case format
  of WaveFormatPCM:       sfPCM
  of WaveFormatIEEEFloat: sfIEEEFloat
  else:                   sfUnknown

  result = wf


proc readRegionIdsAndStartOffsetsFromCueChunk*(rr; regions: var RegionTable) =
  let numCuePoints = rr.read(uint32)

  if numCuePoints > 0'u32:
    for i in 0..<numCuePoints:

      {.hint[XDeclaredButNotUsed]: off.}
      let
        cuePointId   = rr.read(uint32)
        position     = rr.read(uint32)  # ignored
        dataChunkId  = rr.readFourCC()
        chunkStart   = rr.read(uint32)  # ignored
        blockStart   = rr.read(uint32)  # ignored
        sampleOffset = rr.read(uint32)

      if dataChunkId == FourCC_WAVE_data:
        if not regions.hasKey(cuePointId):
          var region: Region
          regions[cuePointId] = region
        regions[cuePointId].startFrame = sampleOffset


proc readRegionLabelsAndEndOffsetsFromListChunk*(rr; regions: var RegionTable) =
  while rr.hasNextChunk():
    let ci = rr.nextChunk()

    case ci.id
    of FourCC_WAVE_labl:
      let
        cuePointId = rr.read(uint32)
        # do not read terminating zero byte
        textLen = ci.size.int - sizeof(cuePointId) - 1
        text = rr.readStr(textLen)

      if regions.hasKey(cuePointId):
        regions[cuePointId].label = text

    of FourCC_WAVE_ltxt:
      let
        cuePointId   = rr.read(uint32)
        sampleLength = rr.read(uint32)
        purposeId    = rr.readFourCC()

      if purposeId == FourCC_WAVE_rgn:
        if regions.hasKey(cuePointId):
          regions[cuePointId].length = sampleLength

type
  WaveReadError* = object of Exception


proc openWaveFile*(filename: string, readRegions: bool = false,
                   bufSize: int = -1): WaveInfo =
  var rr = openRiffFile(filename, bufSize)

  var
    fmtCursor  = Cursor.none
    cueCursor  = Cursor.none
    adtlCursor = Cursor.none
    dataCursor = Cursor.none

  proc storeCursor(cur: var Option[Cursor], fourCC: string) =
    if cur.isNone: cur = rr.cursor.some
    else: raise newException(
      WaveReadError, fmt"multiple '{fourCC}' chunks found")

  while rr.hasNextChunk():
    let ci = rr.nextChunk()
    if ci.kind == ckGroup:
      if readRegions and ci.formatTypeId == FourCC_WAVE_adtl:
        storeCursor(adtlCursor, FourCC_WAVE_adtl)
    else:
      case ci.id
      of FourCC_WAVE_fmt: storeCursor(fmtCursor, FourCC_WAVE_fmt)
      of FourCC_WAVE_cue: storeCursor(cueCursor, FourCC_WAVE_cue)
      of FourCC_WAVE_data:
        if readRegions: storeCursor(dataCursor, FourCC_WAVE_data)
  rr.exitGroup()

  if fmtCursor.isNone:
    raise newException(WaveReadError, fmt"chunks '{FourCC_WAVE_fmt}' found")

  if dataCursor.isNone:
    raise newException(WaveReadError, fmt"chunks '{FourCC_WAVE_data}' found")

  rr.cursor = fmtCursor.get
  result.format = rr.readFormatChunk()

  result.reader = rr
  result.dataCursor = dataCursor.get
  result.regions = initOrderedTable[uint32, Region]()

  if readRegions and cueCursor.isSome and adtlCursor.isSome:
    rr.cursor = cueCursor.get
    rr.readRegionIdsAndStartOffsetsFromCueChunk(result.regions)

    rr.cursor = adtlCursor.get
    rr.enterGroup()
    rr.readRegionLabelsAndEndOffsetsFromListChunk(result.regions)


#[
  let (fmtFound, fmtChunk) = rr.findChunk(FourCC_WAVE_fmt)
  if fmtFound:
    rr.setCurrentChunk(fmtChunk)
    rr.readFormatChunk()
  else:
    raise newException(WaveReaderError, fmt"'{FourCC_WAVE_fmt}' chunk not found")

  if readRegions:
    let (cueFound, cueChunk) = rr.findChunk(FourCC_WAVE_cue)
    let (listFound, listChunk) = rr.findChunk(FourCC_LIST)
    if cueFound and listFound:
      rr.readRegions(cueChunk, listChunk)

  let (dataFound, dataChunk) = rr.findChunk(FourCC_WAVE_data)
  if dataFound:
    rr.setCurrentChunk(dataChunk)
    return wr
  else:
    raise newException(WaveReaderError, fmt"'{FourCC_WAVE_data}' chunk not found")
]#

# }}}
# {{{ Writer

#[
type
  WaveWriter* = object
    # read-only properties
    format:         SampleFormat
    sampleRate:     Natural
    numChannels:    Natural
    regions:        RegionTable

  WaveWriterError* = object of Exception

proc initWaveWriter*(): WaveWriter =
  result.regions = initOrderedTable[uint32, Region]()

func format*(ww: WaveWriter): SampleFormat {.inline.} =
  ww.format

func sampleRate*(ww: WaveWriter): Natural {.inline.} =
  ww.sampleRate

func numChannels*(ww: WaveWriter): Natural {.inline.} =
  ww.numChannels

func `regions=`*(ww: var WaveWriter, regions: RegionTable) {.inline.} =
  ww.regions = regions

func regions*(ww: WaveWriter): RegionTable {.inline.} =
  ww.regions

]#

#[
proc writeData24Packed*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ww.writeInternal(numItems * 3, ww.writer.writeData24Packed(data, numItems))

proc writeData24Unpacked*(ww: var WaveWriter, data: pointer, numItems: Natural) =
  ww.writeInternal(numItems * 4, ww.writer.writeData24Unpacked(data, numItems))

proc writeData24Packed*(ww: var WaveWriter,
                        src: var openArray[int8|uint8], numItems: Natural) =
  ww.writeInternal(numItems * 3,
                   ww.writer.writeData24Packed(src, numItems))

proc writeData24Packed*(ww: var WaveWriter, src: var openArray[int8|uint8]) =
  ww.writeData24Packed(src, src.len div 3)

proc writeData24Unpacked*(ww: var WaveWriter, src: var openArray[int32|uint32],
                          numItems: Natural) =
  ww.writeInternal(numItems * 4,
                   ww.writer.writeData24Unpacked(src, numItems))

proc writeData24Unpacked*(ww: var WaveWriter,
                          src: var openArray[int32|uint32]) =
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
  assert numItems <= src.len
  bw.writeData24Unpacked(src[0].addr, numItems)


proc writeData24Unpacked*(bw: var BufferedWriter,
                          src: var openArray[int32|uint32]) =
  bw.writeData24Unpacked(src, src.len)


]#

#[
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
  of littleEndian: ww.startChunk(FourCC_RIFF_LE)
  of bigEndian:    ww.startChunk(FourCC_RIFF_BE)

  ww.writeFourCC(FourCC_WAVE)
  result = ww


proc writeFormatChunk*(ww: var WaveWriter) =
  ## TODO
  ww.startChunk(FourCC_WAVE_fmt)

  var formatTag: uint16
  var bitsPerSample: uint16

  case ww.format
  of sf8BitInteger:  formatTag = WaveFormatPCM;       bitsPerSample = 8
  of sf16BitInteger: formatTag = WaveFormatPCM;       bitsPerSample = 16
  of sf24BitInteger: formatTag = WaveFormatPCM;       bitsPerSample = 24
  of sf32BitInteger: formatTag = WaveFormatPCM;       bitsPerSample = 32
  of sf32BitFloat:   formatTag = WaveFormatIEEEFloat; bitsPerSample = 32
  of sf64BitFloat:   formatTag = WaveFormatIEEEFloat; bitsPerSample = 64

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
  ww.startChunk(FourCC_WAVE_cue)
  ww.writeUInt32(ww.regions.len.uint32)

  for id, region in ww.regions.pairs():
    ww.writeUInt32(id)          # cuePointId
    ww.writeUInt32(0)           # position (unused if dataChunkId is 'data')
    ww.writeFourCC(FourCC_WAVE_data) # dataChunkId
    ww.writeUInt32(0)           # chunkStart (unused if dataChunkId is 'data')
    ww.writeUInt32(0)           # blockStart (unused if dataChunkId is 'data')
    ww.writeUInt32(region.startFrame) # sampleOffset

  ww.endChunk()


proc writeListChunk*(ww: var WaveWriter) =
  ## TODO
  ww.startChunk(FourCC_LIST)
  ww.writeFourCC(FourCC_WAVE_adtl)

  for id, region in ww.regions.pairs():
    ww.startChunk(FourCC_WAVE_labl)
    ww.writeUInt32(id)            # cuePointId
    ww.writeString(region.label)  # text
    ww.writeUInt8(0)              # null terminator
    ww.endChunk()

  for id, region in ww.regions.pairs():
    if region.length > 0'u32:
      ww.startChunk(FourCC_WAVE_ltxt)
      ww.writeUInt32(id)             # cuePointId
      ww.writeUInt32(region.length)  # sampleLength
      ww.writeFourCC(FourCC_WAVE_rgn)  # purposeId
      ww.writeUInt16(0)              # country (ignored)
      ww.writeUInt16(0)              # language (ignored)
      ww.writeUInt16(0)              # dialect (ignored)
      ww.writeUInt16(0)              # codePage (ignored)
      ww.endChunk()

  ww.endChunk()
]#


# vim: et:ts=2:sw=2:fdm=marker
