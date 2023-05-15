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