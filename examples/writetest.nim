import math
import os
import tables

import easywave

const
  SampleRate = 44100
  NumChannels = 2
  LengthSeconds = 1
  FreqHz = 440

let regions = {
  1'u32: Region(startFrame:     0, length:     0, label: "marker1"),
  2'u32: Region(startFrame:  1000, length:     0, label: "marker2"),
  3'u32: Region(startFrame:  3000, length:     0, label: "marker3"),
  4'u32: Region(startFrame: 10000, length:  5000, label: "region1"),
  5'u32: Region(startFrame: 30000, length: 10000, label: "region2")
}.toOrderedTable


proc writeTestFile[T: SomeNumber](filename: string, endian: Endianness,
                                  sampleFormat: SampleFormat,
                                  bitsPerSample: Natural) =
  var rw = createRiffFile(filename, FourCC_WAVE, endian)

  let wf = WaveFormat(
    sampleFormat:  sampleFormat,
    bitsPerSample: sizeof(T) * 8,
    sampleRate:    SampleRate,
    numChannels:   NumChannels
  )

  rw.writeFormatChunk(wf)
  rw.beginChunk(FourCC_WAVE_data)

  var amplitude = case bitsPerSample
  of  8: 2^7 / 4
  of 16: 2^15 / 4
  of 24: 2^23 / 4
  of 32:
    if sampleFormat == sfPCM: 2^31 / 4 else: 1.0 / 4
  of 64: 1.0 / 4
  else: 0

  var
    totalFrames = LengthSeconds * SampleRate  # 1 frame = 2 samples (stereo)
    buf: array[1024, T]
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SampleRate/FreqHz)

  while totalFrames > 0:
    var s = if sizeof(T) == 1: T(sin(phase) * amplitude + (2^7).float)
    else:                      T(sin(phase) * amplitude)

    buf[pos]   = s
    buf[pos+1] = s

    inc(pos, 2)
    if pos >= buf.len:
      rw.write(buf, 0, buf.len)
      pos = 0
    dec(totalFrames)

    phase += phaseInc

  if pos > 0:
    rw.write(buf, 0, pos)

  rw.endChunk()

  rw.writeCueChunk(regions)
  rw.writeAdtlListChunk(regions)
  rw.close()

#[
# {{{ write24BitPackedTestFile

proc write24BitPackedTestFile(outfile: string, endian: endian) =
  var ww = writeWaveFile(outfile, sf24BitInteger, SampleRate, NumChannels,
                         endian)
  ww.writeFormatChunk()
  ww.startDataChunk()

  let amplitude = 2^23 / 4
  var
    totalFrames = LengthSeconds * SampleRate  # 1 frame = 2 samples (stereo)
    buf: array[256*6, uint8]  # must be divisible by 6!
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SampleRate/FreqHz)

  while totalFrames > 0:
    let s = (sin(phase) * amplitude).int32
    buf[pos]   = ( s         and 0xff).uint8
    buf[pos+1] = ((s shr  8) and 0xff).uint8
    buf[pos+2] = ((s shr 16) and 0xff).uint8

    buf[pos+3] = ( s         and 0xff).uint8
    buf[pos+4] = ((s shr  8) and 0xff).uint8
    buf[pos+5] = ((s shr 16) and 0xff).uint8

    inc(pos, 6)
    if pos >= buf.len:
      ww.writeData24Packed(buf)
      pos = 0
    dec(totalFrames)

    phase += phaseInc

  if pos > 0:
    ww.writeData24Packed(buf, pos)

  ww.endChunk()

  ww.setRegions()
  ww.writeCueChunk()
  ww.writeListChunk()

  ww.close()

# }}}
]#

writeTestFile[uint8]("writetest-PCM8-LE.wav", littleEndian, sfPCM, 8)
writeTestFile[uint16]("writetest-PCM16-LE.wav", littleEndian, sfPCM, 16)
writeTestFile[uint32]("writetest-PCM24-unpacked-LE.wav", littleEndian, sfPCM, 24)
# write24BitPackedTestFile("writetest-24bit-packed-LE.wav", littleEndian)
writeTestFile[uint32]("writetest-PCM32-LE.wav", littleEndian, sfPCM, 32)
writeTestFile[float32]("writetest-Float32-LE.wav", littleEndian, sfFloat, 32)
writeTestFile[float64]("writetest-Float64-LE.wav", littleEndian, sfFloat, 64)


writeTestFile[uint8]("writetest-PCM8-BE.wav", bigEndian, sfPCM, 8)
writeTestFile[uint16]("writetest-PCM16-BE.wav", bigEndian, sfPCM, 16)
writeTestFile[uint32]("writetest-PCM24-unpacked-BE.wav", bigEndian, sfPCM, 24)
# write24BitPackedTestFile("writetest-24bit-packed-BE.wav", littleEndian)
writeTestFile[uint32]("writetest-PCM32-BE.wav", bigEndian, sfPCM, 32)
writeTestFile[float32]("writetest-Float32-BE.wav", bigEndian, sfFloat, 32)
writeTestFile[float64]("writetest-Float64-BE.wav", bigEndian, sfFloat, 64)

# vim: et:ts=2:sw=2:fdm=marker
