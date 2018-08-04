import os, strformat, tables
import easywave

if paramCount() == 0:
  echo "Usage: readtest WAVEFILE"
  quit()

var infile = paramStr(1)
var wr = parseWaveFile(infile, readRegions = true)

echo fmt"Format:     {wr.format}"
echo fmt"Samplerate: {wr.sampleRate}"
echo fmt"Channels:   {wr.numChannels}"

echo "\nChunks:"
for ci in wr.chunks:
  echo ci

if wr.regions.len > 0:
  echo "\nRegions:"
  for id, r in wr.regions.pairs:
    echo fmt"id: {id}, {r}"

