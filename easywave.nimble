# Package

version       = "0.2.0"
author        = "John Novak <john@johnnovak.net>"
description   = "Easy WAVE file handling in Nim"
license       = "WTFPL"

skipDirs = @["doc", "examples"]

# Dependencies

requires "nim >= 1.6.0", "riff"

# Tasks

task examples, "Compiles the examples":
  exec "nim c -d:release examples/readtest.nim"
  exec "nim c -d:release examples/writetest.nim"

task examplesDebug, "Compiles the examples (debug mode)":
  exec "nim c examples/readtest.nim"
  exec "nim c examples/writetest.nim"

task docgen, "Generate HTML documentation":
  exec "nim doc -o:doc/easywave.html easywave"
