# Package

version       = "0.1.0"
author        = "Geoffrey Picron"
description   = "Command line tools to manipulate bipf related data"
license       = "(MIT or Apache-2.0)"
srcDir        = "src"
bin           = @["bipf_dump"]


# Dependencies

requires "nim >= 1.6.12"
requires "https://github.com/BundleFeed/nim_bipf#head"

import std/os

## list dirs in nimbledeps/pkgs2

proc listDepsDir() : seq[string] =  
  for dir in walkDir("nimbledeps/pkgs2"):
    if dir[0] == pcDir:
      result.add dir[1]

task release, "compile artifacts":
  let targetAndOuputs = @[
    ("windows-amd64", "release/bipf_dump_win64.exe"),
    ("windows-arm64", "release/bipf_dump_win_arm64.exe"),
    ("windows-i386", "release/bipf_dump_win32.exe"),
    
    ("macosx-arm64", "release/bipf_dump_macosx_arm64"),
    ("macosx-amd64", "release/bipf_dump_macosx_amd64"),
    
    ("linux-amd64", "release/bipf_dump_linux_amd64"),
    ("linux-i386", "release/bipf_dump_linux_i386"),

    
  ]


  for (target, path) in targetAndOuputs:
    echo "Compiling for " & target
    var cmd = newSeq[string]()
    cmd.add "nimxc"
    cmd.add "c"
    cmd.add "--app:console"
    cmd.add "--noNimblePath"
    for dep in listDepsDir():
      cmd.add "--path:" & dep
    cmd.add "--target"
    cmd.add target
    cmd.add "-o:" & path
    cmd.add "-d:NimblePkgVersion=" & version
    cmd.add "-d:release"
    cmd.add "src/bipf_dump.nim"

    exec cmd.join(" ")

  exec "tar -czvf bipf_dump_" & version & ".tar.gz release/*"