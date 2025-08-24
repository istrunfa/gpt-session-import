-- REAPER Session Import Engine - Logging Utility
-- Provides minimal, centralized logging with toggle

local Log = {}

-- Global toggle
Log.DEBUG = true

-- Simple print wrapper
function Log.log(msg)
  if Log.DEBUG then
    reaper.ShowConsoleMsg("[INFO] " .. tostring(msg) .. "\n")
  end
end

-- Warning (always shown)
function Log.warn(msg)
  reaper.ShowConsoleMsg("⚠️ [WARN] " .. tostring(msg) .. "\n")
end

-- printf-style log
function Log.logf(fmt, ...)
  if Log.DEBUG then
    Log.log(string.format(fmt, ...))
  end
end

-- Module-prefixed log
function Log.module(modname, msg)
  if Log.DEBUG then
    Log.log("[" .. modname .. "] " .. msg)
  end
end

return Log