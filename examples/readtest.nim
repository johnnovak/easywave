import os
import strformat
import strutils
import times

import easywave


proc toTimeString(millis: Natural): string =
  let p = initDuration(milliseconds = millis).toParts
  fmt"{p[Hours]:02}:{p[Minutes]:02}:{p[Seconds]:02}.{p[Milliseconds]:03}"

proc framesToMillis(frames, sampleRate: Natural): Natural =
  const MillisInSecond = 1000
  (frames / sampleRate * MillisInSecond).int

proc printWaveInfo(wi: WaveInfo, dataChunk: ChunkInfo) =
  let
    sampleRate      = wi.format.sampleRate
    bitsPerSample   = wi.format.bitsPerSample
    numChans        = wi.format.numChannels
    numBytes        = dataChunk.size.int
    numBytesHuman   = formatSize(numBytes, includeSpace=true)
    numSamples      = numBytes div (bitsPerSample div 8)
    numSampleFrames = numSamples div numChans
    numMillis       = framesToMillis(numSampleFrames, sampleRate)

  echo fmt"Endianness:         {wi.reader.endian}"
  echo fmt"Sample format:      {wi.format.sampleFormat}"
  echo fmt"Bits per sample:    {bitsPerSample}"
  echo fmt"Sample rate:        {sampleRate}"
  echo fmt"Channels:           {numChans}"
  echo ""
  echo fmt"Sample data size:   {numBytes} bytes ({numBytesHuman})"
  echo fmt"Num samples:        {numSamples}"
  echo fmt"Num samples frames: {numSampleFrames}"
  echo fmt"Length:             {toTimeString(numMillis)}"


proc printRegionInfo(wi: WaveInfo) =
  let sampleRate = wi.format.sampleRate

  echo "\nRegions and labels:\n"

  for id, r in wi.regions.pairs:
    let startTime = framesToMillis(r.startFrame, sampleRate)
    let rtype = if r.length > 0: "region" else: "label"

    echo fmt"  ID:        {id}"
    echo fmt"  Type:      {rtype}"

    if r.length == 0:
      echo fmt"  Position:  {toTimeString(startTime)} (frame {r.startFrame})"
    else:
      let length = framesToMillis(r.length, sampleRate)
      let endFrame = r.startFrame + r.length
      let endTime = framesToMillis(endFrame, sampleRate)
      echo fmt"  Start:     {toTimeString(startTime)} (frame {r.startFrame})"
      echo fmt"  End:       {toTimeString(endTime)} (frame {endFrame})"
      echo fmt"  Duration:  {toTimeString(length)}"

    echo ""


proc main() =
  if os.paramCount() == 0:
    quit "Usage: readtest WAVEFILE"

  var fname = os.paramStr(1)
  let wi: WaveInfo = openWaveFile(fname, readRegions=true)


  wi.reader.cursor = wi.dataCursor
  let dataChunk = wi.reader.currentChunk

  echo dataChunk

  printWaveInfo(wi, dataChunk)
  printRegionInfo(wi)


main()

