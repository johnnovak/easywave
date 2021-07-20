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

  WaveFormatPCM = 1'u16
  WaveFormatIEEEFloat = 3'u16

type
  SampleFormat* = enum
    sfPCM     = (0, "PCM"),
    sfFloat   = (1, "IEEE Float"),
    sfUnknown = (2, "Unknown")

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


proc initRegions*(): RegionTable =
  result = initOrderedTable[uint32, Region]()

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
  of WaveFormatIEEEFloat: sfFloat
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


proc readRegionLabelsAndEndOffsetsFromListChunk*(rr;
                                                 regions: var RegionTable) =
  while rr.hasNextChunk():
    let ci = rr.nextChunk()

    case ci.id
    of FourCC_WAVE_labl:
      let
        cuePointId = rr.read(uint32)
        textLen = ci.size.int - sizeof(cuePointId) - 1  # minus trailing zero
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
  result.regions = initRegions()

  if readRegions and cueCursor.isSome and adtlCursor.isSome:
    rr.cursor = cueCursor.get
    rr.readRegionIdsAndStartOffsetsFromCueChunk(result.regions)

    rr.cursor = adtlCursor.get
    discard rr.enterGroup()
    rr.readRegionLabelsAndEndOffsetsFromListChunk(result.regions)


# }}}
# {{{ Writer

using rw: RiffWriter

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

proc writeFormatChunk*(rw; wf: WaveFormat) =
  rw.beginChunk(FourCC_WAVE_fmt)

  var formatTag: uint16 = case wf.sampleFormat:
  of sfPCM:     WaveFormatPCM
  of sfFloat:   WaveFormatIEEEFloat
  of sfUnknown: 0

  var blockAlign = (wf.numChannels * wf.bitsPerSample div 8).uint16
  var avgBytesPerSec = wf.sampleRate.uint32 * blockAlign.uint32

  rw.write(formatTag)
  rw.write(wf.numChannels.uint16)
  rw.write(wf.sampleRate.uint32)
  rw.write(avgBytesPerSec)
  rw.write(blockAlign)
  rw.write(wf.bitsPerSample.uint16)
  # TODO write extended header for float formats (and for 24 bit) ?

  rw.endChunk()


proc writeCueChunk*(rw; regions: RegionTable) =
  rw.beginChunk(FourCC_WAVE_cue)
  rw.write(regions.len.uint32)  # number of markers/regions

  for id, region in regions.pairs:
    rw.write(id)                 # cuePointId
    rw.write(0'u32)              # position (unused if dataChunkId is 'data')
    rw.writeFourCC(FourCC_WAVE_data) # dataChunkId
    rw.write(0'u32)              # chunkStart (unused if dataChunkId is 'data')
    rw.write(0'u32)              # blockStart (unused if dataChunkId is 'data')
    rw.write(region.startFrame)  # sampleOffset

  rw.endChunk()


proc writeAdtlListChunk*(rw; regions: RegionTable) =
  rw.beginListChunk(FourCC_WAVE_adtl)

  for id, region in regions.pairs:
    rw.beginChunk(FourCC_WAVE_labl)
    rw.write(id)               # cuePointId
    rw.writeStr(region.label)  # text
    rw.write(0'u8)             # null terminator
    rw.endChunk()

  for id, region in regions.pairs:
    if region.length > 0:
      rw.beginChunk(FourCC_WAVE_ltxt)
      rw.write(id)                     # cuePointId
      rw.write(region.length.uint32)   # sampleLength
      rw.writeFourCC(FourCC_WAVE_rgn)  # purposeId
      rw.write(0'u16)                  # country (ignored)
      rw.write(0'u16)                  # language (ignored)
      rw.write(0'u16)                  # dialect (ignored)
      rw.write(0'u16)                  # codePage (ignored)
      rw.endChunk()

  rw.endChunk()


# vim: et:ts=2:sw=2:fdm=marker
