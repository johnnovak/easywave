# easyWAVE

## Overview 

**easyWAVE** is a native Nim library that supports the easy reading and
writing of the most common subset of the WAVE audio file format. It does not
completely abstract away the format; you'll still need to have some
understanding of how WAVE files are structured to use it. No esoteric sample
formats are supported, just uncompressed PCM (which is used 99.99% of the time
in the real world).

The WAVE format is not complicated, but there are lots of little details that
are quite easy to get wrong. This library gives you a toolkit to read and
write WAVE files in a safe and easy way--most of the error prone and tedious
stuff is handled by the library (e.g. chunk size calculation when writing
nested chunks, padding odd-sized chunks, performing transparent byte-order
swapping etc.)

### Features

* Reading and writing of **8/16/24/32-bit integer PCM** and **32/64-bit IEEE float PCM** WAVE files
* Reading and writing of **markers** and **regions**
* An easy way to write **nested chunks**
* Support for **little-endian (RIFF)** and **big-endian (RIFX)** files
* Works on both little-endian and big-endian architectures (byte-swapping is
  handled transparently to the user when necessary)

### Limitations

* No support for compressed formats
* No support for esoteric bit-lengths (e.g. 20-bit PCM)
* Can only read/write the format and cue chunks, and partially the
  list chunk. Reading/writing of any other chunk types has to be implemented
  by the user.
* No direct support for editing (updating) existing files
* No "recovery mode" for handling malformed files
* Only files are supported (so no streams or memory buffers)


## Usage

### Reading WAVE files

TODO

```nimrod
import strformat, tables
import easywave

var wr = parseWaveFile("example.wav", readRegions = true)

echo fmt"Endinanness: {wr.endianness}"
echo fmt"Format:      {wr.format}"
echo fmt"Samplerate:  {wr.sampleRate}"
echo fmt"Channels:    {wr.numChannels}"

for ci in wr.chunks:
  echo ci

if wr.regions.len > 0:
  for id, r in wr.regions.pairs:
    echo fmt"id: {id}, {r}"
```

### Writing WAVE files

To create a new WAVE file, a `WaveWriter` object needs to be instantiated
first:

```nimrod
import easywave

var ww = writeWaveFile(
  filename = "example.wav",
  format = wf16BitInteger,
  sampleRate = 44100,
  numChannels = 2,
  endianness = littleEndian
)
```

Note this will only write the master RIFF header; you'll need to call
`writeFormatChunk()` to write the actual format information to the file. This
gives the user the flexibility to optionally insert some other chunks before
the format chunk.

To start a new chunk, you'll need to call `startChunk("ABCD")`, where `"ABCD"`
is a 4-char chunk ID (FourCC). You can also use `startDataChunk()` shortcut
for creating the data chunk. Then you can use the various `write*` methods to
write some data into the chunk. Finally, you'll need to call `endChunk()` to
close the chunk, which will pad the chunk to an even length if necessary and
update the chunk size in the chunk's header.  Chunks can be nested, the
library will update all parent chunk headers with the correctly calculated
size values.

```nimrod
ww.startChunk("LIST")

ww.writeInt16(-442)
ww.writeUInt32(3)
ww.writeFloat64(1.12300934234)

var buf16 = array[4096, int16]
ww.writeData(buf16)           # writeData methods take an openArray argument

var buf64float: seq[float64]  
ww.writeData(buf64float, 50)  # write the first 50 elements only

ww.endChunk()
```

TODO

```nimrod
ww.regions = {
  1'u32: WaveRegion(startFrame:     0, length:     0, label: "marker1"),
  2'u32: WaveRegion(startFrame:  1000, length:     0, label: "marker2"),
  3'u32: WaveRegion(startFrame: 30000, length: 10000, label: "region2")
}.toOrderedTable

ww.writeCueChunk()
ww.writeListChunk()
```

Finally, the `endFile()` method must be called that will update the master
RIFF chunk with the correct chunk size and close the file:

```nimrod
ww.endFile()
```

## Some general notes about WAVE files

* Little-endian WAVE files start with a RIFF master chunk, big-endian files
  with a RIFX chunk. Apart from the byte-ordering, there are no differences
  between the two formats. The big-endian option is not really meant to be
  used when creating new WAVE files; I just included it because it made the
  testing of the byte-swapping code paths much easier on Intel hardware.
  Virtually nothing can read RIFX files nowadays, it's kind of a dead format.

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

