# Package
packageName   = "nim_bipf"
version       = "0.1.2"
author        = "Geoffrey Picron"
description   = "BIPF encoding/decoding/transcoding"
license       = "(MIT or Apache-2.0)"
srcDir        = "src"



# Dependencies

requires "nim >= 1.6.10"

requires "https://github.com/gpicron/jsExport.nim >= 0.0.2"
requires "chronicles >= 0.10.3"
requires "https://github.com/disruptek/criterion"
requires "https://github.com/gpicron/nim_node_binding#68a0a6b3e8b545f442a40c716f0f8e66e520d120"
requires "https://github.com/BundleFeed/jsony#head"
requires "https://github.com/juancarlospaco/nodejs"



task compilePureJs, "Compile to pure JS":
  exec "nim js -d:release --app:lib  --rangeChecks:off  --boundChecks:off --sinkInference:on  --out:dist/nim_bipf.js --d:nodejs --mm:orc  src/nim_bipf/js/index.nim"

task compileWasm, "Compile to Wasm Module":
  exec "nim js -d:release -o:dist/nim_bipf_wasm_wrapper.js  src/nim_bipf/js/wasm/wrapper.nim"
  exec "nim c -d:danger --app:lib  --threads:off --d:node -d:emscripten --mm:orc --out:dist/nim_bipf_wasm.js src/nim_bipf/js/wasm/binding.nim"

task compilePureJsDebug, "Compile to pure JS (Debug)":
  exec "nim js --app:lib --sinkInference:on  --out:dist/nim_bipf.js --d:nodejs --mm:orc  src/nim_bipf/js/index.nim"

task testJs, "Test JS compatibility layer":
  compilePureJsDebugTask()
  exec "node tests-js/fixtures.js"
  exec "node tests-js/index.js"
  exec "node tests-js/compare.js"

task benchNim, "Benchmark Nim":
  exec "nim c -r -d:release --sinkInference:on --passC:-flto --passL:-flto --mm:orc --out:build/bench_encode tests/bench_encode.nim"

task benchJs, "Benchmark JS":
  compilePureJsTask()
  exec "node tests-js/benchmarks.js"

task genNodeJsModuleCCode, "Generate C code for NodeJS module":
  rmDir "dist/src"
  exec "nim c -c -d:danger --threads:off --sinkInference:on --passC:-ffast-math --passC:-flto --passL:-flto --mm:orc --nimcache:dist/src src/nim_bipf/js/nodejs/binding.nim"

task compileNodeJsModule, "Build for NodeJS":
  exec "$HOME/.nimble/bin/node_binding init -n " & $packageName & " -v " & version & " -d \"" & description &  "\" -a \"" & author & "\" -l \"" & license & "\""
  genNodeJsModuleCCodeTask()
  exec "npx cmake-js clean"
  exec "npx cmake-js build -l verbose "

task compileNodeJsModuleDebug, "Build for NodeJS":
  exec "$HOME/.nimble/bin/node_binding init -n " & $packageName & " -v " & version & " -d \"" & description &  "\" -a \"" & author & "\" -l \"" & license & "\""
  rmDir "dist/src"
  exec "nim c -c -d:debug --sinkInference:on --passC:-flto --passL:-flto --mm:orc --nimcache:dist/src src/nim_bipf/js/nodejs/binding.nim"
  exec "npx cmake-js clean"
  exec "npx cmake-js build --debug -l verbose"

task package, "Package for NPM":
  exec "npx cmake-js clean"
  rmFile "CMakelists.txt"
  rmDir "dist/src"
  rmDir "build"
  compilePureJsTask()