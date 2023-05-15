# Copyright 2023 Geoffrey Picron.
# SPDX-License-Identifier: (MIT or Apache-2.0)

import std/logging


template wrapSideEffects(debug: bool, body: untyped) {.inject.} =
  when debug:
    {.noSideEffect.}:
      when defined(nimHasWarnBareExcept):
        {.push warning[BareExcept]:off.}
      try: body
      except Exception:
        log(lvlError, getCurrentExceptionMsg())
      when defined(nimHasWarnBareExcept):
        {.pop.}
  else:
    body

template trace*(args: varargs[string, `$`]) =
  when defined(release) or defined(warning):
    discard
  else:
    wrapSideEffects(true):
      log(lvlDebug, args)
