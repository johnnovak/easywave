import math, os, strformat
import easywave

const
  SAMPLE_RATE = 44100
  NUM_CHANNELS = 2
  LENGTH_SECONDS = 1
  FREQ = 440  # A440 (standard pitch)

# {{{ write8BitTestFile

proc write8BitTestFile(outfile: string) =
  var ww = writeWaveFile(outfile, wf8BitInteger, SAMPLE_RATE, NUM_CHANNELS)

  # The format chunk must be written before the data chunk
  ww.writeFormatChunk()

  # Write a 1-second long stereo sine wave
  ww.startDataChunk()

  let amplitude = 2^7 / 4
  var
    totalFrames = LENGTH_SECONDS * SAMPLE_RATE  # 1 frame = 2 samples (stereo)
    buf: array[1024, uint8]
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SAMPLE_RATE/FREQ)

  while totalFrames > 0:
    let s = (sin(phase) * amplitude + (2^7).float).uint8
    buf[pos]   = s
    buf[pos+1] = s

    phase += phaseInc
    inc(pos, 2)
    if pos >= buf.len:
      ww.writeData(buf)
      pos = 0
    dec(totalFrames)

  if pos > 0:
    ww.writeData(buf, pos)

  ww.endChunk()

  # Must call this to update the master RIFF chunk size
  ww.endFile()

# }}}
# {{{ write16BitTestFile

proc write16BitTestFile(outfile: string) =
  var ww = writeWaveFile(outfile, wf16BitInteger, SAMPLE_RATE, NUM_CHANNELS)

  # The format chunk must be written before the data chunk
  ww.writeFormatChunk()

  # Write a 1-second long stereo sine wave
  ww.startDataChunk()

  let amplitude = 2^15 / 4
  var
    totalFrames = LENGTH_SECONDS * SAMPLE_RATE  # 1 frame = 2 samples (stereo)
    buf: array[1024, int16]
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SAMPLE_RATE/FREQ)

  while totalFrames > 0:
    let s = (sin(phase) * amplitude).int16
    buf[pos]   = s
    buf[pos+1] = s

    phase += phaseInc
    inc(pos, 2)
    if pos >= buf.len:
      ww.writeData(buf)
      pos = 0
    dec(totalFrames)

  if pos > 0:
    ww.writeData(buf, pos)

  ww.endChunk()

  # Must call this to update the master RIFF chunk size
  ww.endFile()

# }}}
# {{{ write24BitTestFile

proc write24BitTestFile(outfile: string) =
  var ww = writeWaveFile(outfile, wf24BitInteger, SAMPLE_RATE, NUM_CHANNELS)

  # The format chunk must be written before the data chunk
  ww.writeFormatChunk()

  # Write a 1-second long stereo sine wave
  ww.startDataChunk()

  let amplitude = 2^23 / 4
  var
    totalFrames = LENGTH_SECONDS * SAMPLE_RATE  # 1 frame = 2 samples (stereo)
    buf: array[1024, int32]
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SAMPLE_RATE/FREQ)

  while totalFrames > 0:
    let s = (sin(phase) * amplitude).int32
    buf[pos]   = s
    buf[pos+1] = s

    phase += phaseInc
    inc(pos, 2)
    if pos >= buf.len:
      ww.writeData24From32(buf)
      pos = 0
    dec(totalFrames)

  if pos > 0:
    ww.writeData24From32(buf, pos)

  ww.endChunk()

  # Must call this to update the master RIFF chunk size
  ww.endFile()

# }}}
# {{{ write24BitPackedTestFile

proc write24BitPackedTestFile(outfile: string) =
  var ww = writeWaveFile(outfile, wf24BitInteger, SAMPLE_RATE, NUM_CHANNELS)

  # The format chunk must be written before the data chunk
  ww.writeFormatChunk()

  # Write a 1-second long stereo sine wave
  ww.startDataChunk()

  let amplitude = 2^23 / 4
  var
    totalFrames = LENGTH_SECONDS * SAMPLE_RATE  # 1 frame = 2 samples (stereo)
    buf: array[256*6, uint8]  # must be divisible by 6!
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SAMPLE_RATE/FREQ)

  while totalFrames > 0:
    let s = (sin(phase) * amplitude).int32
    buf[pos]   = ( s         and 0xff).uint8
    buf[pos+1] = ((s shr  8) and 0xff).uint8
    buf[pos+2] = ((s shr 16) and 0xff).uint8

    buf[pos+3] = ( s         and 0xff).uint8
    buf[pos+4] = ((s shr  8) and 0xff).uint8
    buf[pos+5] = ((s shr 16) and 0xff).uint8

    phase += phaseInc
    inc(pos, 6)
    if pos >= buf.len:
      ww.writeData24Packed(buf)
      pos = 0
    dec(totalFrames)

  if pos > 0:
    ww.writeData24Packed(buf, pos)

  ww.endChunk()

  # Must call this to update the master RIFF chunk size
  ww.endFile()

# }}}
# {{{ write32BitTestFile

proc write32BitTestFile(outfile: string) =
  var ww = writeWaveFile(outfile, wf32BitInteger, SAMPLE_RATE, NUM_CHANNELS)

  # The format chunk must be written before the data chunk
  ww.writeFormatChunk()

  # Write a 1-second long stereo sine wave
  ww.startDataChunk()

  let amplitude = 2^31 / 4
  var
    totalFrames = LENGTH_SECONDS * SAMPLE_RATE  # 1 frame = 2 samples (stereo)
    buf: array[1024, int32]
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SAMPLE_RATE/FREQ)

  while totalFrames > 0:
    let s = (sin(phase) * amplitude).int32
    buf[pos]   = s
    buf[pos+1] = s

    phase += phaseInc
    inc(pos, 2)
    if pos >= buf.len:
      ww.writeData(buf)
      pos = 0
    dec(totalFrames)

  if pos > 0:
    ww.writeData(buf, pos)

  ww.endChunk()

  # Must call this to update the master RIFF chunk size
  ww.endFile()

# }}}
# {{{ write32BitFloatTestFile

proc write32BitFloatTestFile(outfile: string) =
  var ww = writeWaveFile(outfile, wf32BitFloat, SAMPLE_RATE, NUM_CHANNELS)

  # The format chunk must be written before the data chunk
  ww.writeFormatChunk()

  # Write a 1-second long stereo sine wave
  ww.startDataChunk()

  let amplitude = 1.0 / 4
  var
    totalFrames = LENGTH_SECONDS * SAMPLE_RATE  # 1 frame = 2 samples (stereo)
    buf: array[1024, float32]
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SAMPLE_RATE/FREQ)

  while totalFrames > 0:
    let s = (sin(phase) * amplitude).float32
    buf[pos]   = s
    buf[pos+1] = s

    phase += phaseInc
    inc(pos, 2)
    if pos >= buf.len:
      ww.writeData(buf)
      pos = 0
    dec(totalFrames)

  if pos > 0:
    ww.writeData(buf, pos)

  ww.endChunk()

  # Must call this to update the master RIFF chunk size
  ww.endFile()

# }}}
# {{{ write64BitFloatTestFile

proc write64BitFloatTestFile(outfile: string) =
  var ww = writeWaveFile(outfile, wf64BitFloat, SAMPLE_RATE, NUM_CHANNELS)

  # The format chunk must be written before the data chunk
  ww.writeFormatChunk()

  # Write a 1-second long stereo sine wave
  ww.startDataChunk()

  let amplitude = 1.0 / 4
  var
    totalFrames = LENGTH_SECONDS * SAMPLE_RATE  # 1 frame = 2 samples (stereo)
    buf: array[1024, float64]
    pos = 0
    phase = 0.0
    phaseInc = 2*PI / (SAMPLE_RATE/FREQ)

  while totalFrames > 0:
    let s = (sin(phase) * amplitude).float64
    buf[pos]   = s
    buf[pos+1] = s

    phase += phaseInc
    inc(pos, 2)
    if pos >= buf.len:
      ww.writeData(buf)
      pos = 0
    dec(totalFrames)

  if pos > 0:
    ww.writeData(buf, pos)

  ww.endChunk()

  # Must call this to update the master RIFF chunk size
  ww.endFile()

# }}}

write8BitTestFile("writetest-8bit.wav")
write16BitTestFile("writetest-16bit.wav")
write24BitTestFile("writetest-24bit.wav")
write24BitPackedTestFile("writetest-24bit-packed.wav")
write32BitTestFile("writetest-32bit.wav")

write32BitFloatTestFile("writetest-32bit-float.wav")
write64BitFloatTestFile("writetest-64bit-float.wav")

# vim: et:ts=2:sw=2:fdm=marker
