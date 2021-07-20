import unittest

# {{{ Read tests / parseWaveFile
suite "Read tests / parseWaveFile":

  test "parseWaveFile - file not found":
    parseWaveFile("testdata/emptyfile.wav")

  test "parseWaveFile - empty file":
    parseWaveFile("testdata/emptyfile.wav")

  test "parseWaveFile - no format chunk":
    parseWaveFile("testdata/emptyfile.wav")

  test "parseWaveFile - no data chunk":
    parseWaveFile("testdata/emptyfile.wav")

  test "parseWaveFile - valid file (don't read regions)":
    parseWaveFile("testdata/emptyfile.wav")

  test "parseWaveFile - valid file (read regions)":
    parseWaveFile("testdata/emptyfile.wav")

  # methods
  #   filename
  #   endianness
  #   format
  #   sampleRate
  #   numChannels
  #   chunks
  #   regions
  #   currChunk
  #
  #   readFourCC
  #   readInt8
  #   readInt16
  #   readInt32
  #   readInt64
  #   readUInt8
  #   readUInt16
  #   readUInt32
  #   readUInt64
  #   readFloat32
  #   readFloat64
  #   readData
  #
  # setCurrentChunk
  # hasNextChunk
  # nextChunk
  # setChunkPos
  # buildChunkList
  # findChunk
  # readFormatChunk
  # readRegions
  #

# }}}
# {{{ Read tests / openWaveFile
suite "Read tests / openWaveFile":

  test "openWaveFile - file not found":
    parseWaveFile("testdata/emptyfile.wav")

  test "openWaveFile - empty file":
    parseWaveFile("testdata/emptyfile.wav")


# vim: et:ts=2:sw=2:fdm=marker
