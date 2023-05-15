# This is just an example to get you started. A typical hybrid package
# uses this file as the main entry point of the application.

import strutils
import std/[os]

proc findNimStdLib(): string =
  ## Tries to find a path to a valid "system.nim" file.
  ## Returns "" on failure.
  let nimexe = os.findExe("nim")
  if nimexe.len == 0: 
    raise newException(OSError, "nim not found")
  result = nimexe.splitPath()[0] /../ "lib"
  
  if not fileExists(result / "system.nim"):
    let choosenim = os.getHomeDir() / ".choosenim"
    if not dirExists(choosenim):
      raise newException(OSError, "choosenim not found")
    let nimToolchain = readFile(choosenim / "current")
    result = nimToolchain / "lib"

  echo "Found Nim stdlib at: ", result




proc init(name, version, description, author, licence : string) =
  ## Initialize/update the npm required files
  
  let packageJson = """
  {
    "name": "$1",
    "version": "$2",
    "description": "$3",
    "main": "index.js",
    "keywords": [],
    "author": "$4",
    "license": "$5",
    "dependencies": {
      "bindings": "^1.5.0"
    },
    "devDependencies": {
      "cmake-js": "^7.1.1"
    }
  }
  """ % [name, version, description, author, licence]
  #writeFile("package.json", packageJson)

  let CMakeLists = """
  cmake_minimum_required(VERSION 3.15)
  cmake_policy(SET CMP0091 NEW)
  cmake_policy(SET CMP0042 NEW)

  project ($1)

  add_definitions(-DNAPI_VERSION=4)

  include_directories($${CMAKE_JS_INC})
  include_directories($2)

  file(GLOB SOURCE_FILES "dist/src/*.c")

  add_library($${PROJECT_NAME} SHARED $${SOURCE_FILES} $${CMAKE_JS_SRC})
  set_target_properties($${PROJECT_NAME} PROPERTIES PREFIX "" SUFFIX ".node" INTERPROCEDURAL_OPTIMIZATION TRUE)
  target_link_libraries($${PROJECT_NAME} $${CMAKE_JS_LIB})

  if(MSVC AND CMAKE_JS_NODELIB_DEF AND CMAKE_JS_NODELIB_TARGET)
    # Generate node.lib
    execute_process(COMMAND $${CMAKE_AR} /def:$${CMAKE_JS_NODELIB_DEF} /out:$${CMAKE_JS_NODELIB_TARGET} $${CMAKE_STATIC_LINKER_FLAGS})
  endif()
  """ % [name, findNimStdLib()]

  writeFile("CMakeLists.txt", CMakeLists)  

when isMainModule:
  import cligen; 
  dispatchMulti([init])

  
else:
  import node_binding/napi

  export napi



