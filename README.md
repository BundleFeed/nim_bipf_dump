# Nim BIPF dump

Simple command line tool to dump SSB messages form Manyverse database (ssb-db2).
It simply dumps the messages in the BIPF format from the log file (log.bipf).

## Install

### from source

First, you need Nim to be installed on your system. Then, you can install the tool with Nimble:

```bash
nimble install
```

### from binary

You can also download a binary from the github release page. The binary is statically linked and should work on most Linux, Windows and OSX version.

You can simply the appropriate binary in the archive, rename it to `nim_bipf_dump` and put it in your path.

## Usage

```bash
nim_bipf_dump [path to log.bipf]
```

The tool will dump the messages in JSON-line format to the standard output. So you can pipe it to another tool like `less` to browse the messages.

Example:

```bash
nim_bipf_dump | less
```


If the path is not provided, it will try to find the log.bipf file in the appropriate location for your system at the default location used by Manyverse.

## License

This repository is licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. This file may not be copied, modified, or distributed except according to those terms.
