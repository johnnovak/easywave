# easyWAVE

**Work in progress, not ready for public use yet!**

## Overview

**easyWAVE** is a native Nim library that supports the reading and writing of
the most common subset of the WAVE audio file format. Only uncompressed PCM
data is supported (which is used 99.99% of the time in the real world).  The
library does not abstract away the file format; you'll still need to have some
understanding of how WAVE files are structured to use it.

The WAVE format is not complicated, but there are lots of little details that
are quite easy to get wrong. This library gives you a toolkit to read and
write WAVE files in a safe and easy manner—most of the error prone and tedious
stuff is handled by the library (e.g. chunk size calculation when writing
nested chunks, automatic padding of odd-sized chunks, transparent byte-order
swapping in I/O methods etc.)

### Features

* Reading and writing of **8/16/24/32-bit integer PCM** and **32/64-bit IEEE float PCM** WAVE files
* Reading and writing of **markers** and **regions**
* An easy way to write **nested chunks**
* Support for **little-endian (RIFF)** and **big-endian (RIFX)** files
* Works on both little-endian and big-endian architectures (byte-swapping is
  handled transparently to the client code)
* Native Nim implementation, no external dependencies
* Released under [WTFPL](http://www.wtfpl.net/)

### Limitations

* No support for compressed formats
* No support for esoteric bit-lengths (e.g. 20-bit PCM)
* Can only read/write the format and cue chunks, and partially the
  list chunk. Reading/writing of any other chunk types has to be implemented
  by the user.
* No direct support for editing (updating) existing files
* No "recovery mode" for handling malformed files
* Only file I/O is supported (so no streams or memory buffers)

## Installation

The best way to install the library is by using `nimble`:

```
nimble install easywave
```

## Usage

### Reading WAVE files

Reading WAVE files is accomplished through `WaveReader` objects.
A `WaveReaderError` will be raised if an I/O error was encountered or if the
WAVE file is invalid.

#### Basic usage

Just call `parseWaveFile()` with the filename of the WAVE file. You can set
the `readRegions` option to `true` if you're interested in the markers/regions
stored in the file as well.

This method will:

* Parse the WAVE file headers and the **format chunk** (`"fmt "`). Information
  about the sample format will be available via the `endianness`, `format`,
  `sampleRate` and `numChannels` properties.

* Find all chunks in the file and store this info as a sequence of
  `ChunkInfo` objects in the `chunks` property. The size of the sample
  data in bytes will be available through the `dataSize` property.

* If `readRegions` was set to `true`, try to read marker and region
  info from the **cue** (`"cue "`) and **list chunks** (`"LIST"`).

* Set the file pointer to the start of the sample data in the **data chunk**
  (`"data"`).

A simple example that illustrates all these points:

```nimrod
import strformat, tables
import easywave

var wr = parseWaveFile("example.wav", readRegions = true)

echo fmt"Endianness: {wr.endianness}"
echo fmt"Format:     {wr.format}"
echo fmt"Samplerate: {wr.sampleRate}"
echo fmt"Channels:   {wr.numChannels}"

for ci in wr.chunks:
  echo ci

if wr.regions.len > 0:
  for id, r in wr.regions.pairs:
    echo fmt"id: {id}, {r}"

var numBytes = wr.dataSize
echo fmt"Sample data size: {numBytes} bytes"

# File pointer is now at the start of the sample data
```

Reading single values or chunks of data from the file is accomplished through
the various `read*` methods. See the API docs for the full list. It's your
responsibility to ensure that you read the sample data with the appropriate
read method; there's nothing stopping you from reading 16-bit integer data as
64-bit floats, for example, if that's what you really want
:stuck_out_tongue_winking_eye:

```nimrod
# Single value read
let v3 = wr.readInt8()
let v1 = wr.readUInt16()
let v2 = wr.readFloat32()

# Buffered read
var buf16: array[4096, int16]
wr.readData(buf16)            # read until the buffer is full

var buf32float = newSeq[float32](1024)
wr.readData(buf32float, 50)   # read only 50 elements
```

#### Advanced usage

While the above basic usage pattern would be probably sufficient for most use
cases, you can do the reading fully manually by calling the low-level read
methods. 

The below code is an example for that; it approximates what `parseWaveFile()`
is doing, minus the error checking. Consult the API docs for the list of
available functions.

```nimrod
var wr = openWaveFile("example.wav")

var cueChunk, listChunk, dataChunk: ChunkInfo

# Iterate through all chunks
while wr.hasNextChunk():
  var ci = wr.nextChunk()
  case ci.id
  of FOURCC_FORMAT: wr.readFormatChunk(ci)
  of FOURCC_CUE:    cueChunk = ci
  of FOURCC_LIST:   listChunk = ci
  of FOURCC_DATA:   dataChunk = ci
  else: discard

ww.readRegions(cueChunk, listChunk)

# Seek to the start of the sample data
setFilePos(wr.file, dataChunk.filePos + CHUNK_HEADER_SIZE)
```

### Writing WAVE files

Similarly to reading, writing WAVE files is accomplished through `WaveWriter`
objects.  A `WaveWriterError` will be raised if an I/O error was encountered
or if you tried to perform an invalid operation (e.g. writing to a closed
file, attempting to write data between chunks etc.)

#### Creating a WAVE file

To create a new WAVE file, a `WaveWriter` object needs to be instantiated
first:

```nimrod
import easywave

var ww = writeWaveFile(
  filename = "example.wav",
  format = wf16BitInteger,
  sampleRate = 44100,
  numChannels = 2
)
```

Note that this will only create the file and write the master RIFF chunk
(`"RIFF"`) header.

#### Writing the format chunk

You'll need to explicitly call `writeFormatChunk()` to write the actual format
information to the file in the form of a **format chunk** (`"fmt "`). This
gives you the flexibility to optionally insert some other chunks before the
format chunk.

#### Writing markers and regions

To write markers and regions to the file, you'll need to descibe them as a
table of values where the keys are the marker/region IDs (32-bit unsigned
integers unique per marker/region) and the values `Region` objects.
Markers are defined simply as regions with a length of zero.

```nimrod
ww.regions = {
  1'u32: Region(startFrame:     0, length:     0, label: "marker1"),
  2'u32: Region(startFrame:  1000, length:     0, label: "marker2"),
  3'u32: Region(startFrame: 30000, length: 10000, label: "region2")
}.toOrderedTable

ww.writeRegions()
```

Note that the start positions and lengths of the markers/regions need to be
specified in sample frames—these are *not* byte offsets! (1 sample frame = *N*
number of samples, where *N* is the number of channels)

`writeRegions()` will technically create two new chunks right next to each
other:

* A **cue chunk** (`"cue "`) containing the IDs and the
  start offsets of the cue points (markers)
* A **list chunk** (`"LIST"`) containing label (`"labl"`) and labeled text
  (`"ltxt"`) sub-chunks to store the labels and region lengths of the
  markers/regions, respectively

The list chunks allows lots of other types of information to be stored in its
various sub-chunks. If you need to store such extra data, you cannot use
`writeRegions()`; you'll need to implement your own list chunk writing logic.


#### Writing the data chunk and other chunks

To write any other other chunks types, you'll need to do the following:

1. Call `startChunk("ABCD")`, where `"ABCD"` is the 4-char chunk ID
   ([FourCC](https://en.wikipedia.org/wiki/FourCC)).
   `startDataChunk()` is a shortcut for creating the data chunk (`"data"`).

2. Use the various `write*` methods to write the data (see the API docs for
   the full list). Byte-order swapping will be handled automatically depending
   on the CPU architecture and the endianness of the file. You need to ensure
   that you use the correct write method variant for the particular sample
   format you're using.

3. When you're done, call `endChunk()` to close the chunk. This will pad the
   data automatically with an extra byte at the end if an odd number of bytes
   have been written so far, and it will update the chunk size field in the chunk
   header.

```nimrod
ww.startChunk("LIST")

# Write single values
ww.writeInt16(-442)
ww.writeUInt32(3)
ww.writeFloat64(1.12300934234)

# Write buffered data
var buf16 = array[4096, int16]
ww.writeData(buf16)           # writeData methods take an openArray argument

var buf64float: seq[float64]
ww.writeData(buf64float, 50)  # write the first 50 elements only

ww.endChunk()
```

Chunks can be nested; the library will make sure to calculate the correct
chunk sizes for all parent chunks.

Bear in my mind that it is invalid to write data "between chunks"—an error
will be raised if you tried to write some data after ending a chunk but before
starting a new one.

#### Closing the file

Finally, the `endFile()` method must be called to update the master
RIFF chunk with the correct master chunk size. This will also close the file.

## Handling 24-bit data

The library provides two ways to deal with 24-bit data:

* **As packed data:** `readData24Packed()` and `writeData24Packed()` treat
    24-bit data as a continuous stream of bytes (as they actually appear in
    the file). The first sample is bytes 1, 2 and 3, the second sample bytes
    4, 5 and 6, and so on. Because of this, the size of the buffer used with
    these two methods must be divisable by three, otherwise an assertion error
    will be raised at runtime. The read and write methods only perform
    byte-order swapping, if necessary.

* **As unpacked data:** `readData24Unpacked()` and `writeData24Unpacked()`
    treat 24-bit data as a stream of 32-bit integers. The read method unpacks
    the packed data from the file into a stream of 32-bit integers (with the
    most significant byte set to zero), while the write does the opposite.

It is important to stress out that the data will be always written to the WAVE
file in packed form—it's just sometimes more convenient to deal with 32-bit
integers than with packed data, hence the two different methods.


## Some general notes about WAVE files

* Little-endian WAVE files start with the `"RIFF"` master chunk ID, big-endian
  files start with `"RIFX"`. Apart from the byte-ordering, there are no
  differences between the two formats. The big-endian option is not really
  meant to be used when creating new WAVE files; I just included it because
  it made the testing of the byte-swapping code paths much easier on Intel
  hardware.  Virtually nothing can read RIFX files nowadays, it's kind of a
  dead format.

* The only restriction on the order of chunks is that the format chunk *must*
  appear before the data chunk (but not necessarily *immediately* before it).
  Apart from this restriction, other chunks can appear in *any* order. For
  example, there is no guarantee that the format chunk is always the first
  chunk (some old software mistakenly assumes this).

* All chunks must start at even offsets. If a chunk contains an odd number of
  bytes, it must be padded with an extra byte at the end. However, the chunk
  header must contain the *original unpadded chunk length* in its size field
  (the writer takes care of this, but this might surprise some people when
  reading files).

## License

Copyright © 2018-2019 John Novak <<john@johnnovak.net>>

This work is free. You can redistribute it and/or modify it under the terms of
the **Do What The Fuck You Want To Public License, Version 2**, as published
by Sam Hocevar. See the `COPYING` file for more details.
