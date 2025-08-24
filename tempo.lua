--[[
@description REAPER Project Engine - Tempo & Time Signature Module
@version 1.0
@about Handles tempo map and time signature markers
--]]


local Tempo = {}

local config = require("config")
local TEMPO_WRITE = config.tempo


function Tempo.parse(proj)
  local data = {}
  
  -- Count of tempo/time‑sig markers → CountTempoTimeSigMarkers(proj)
  local count = reaper.CountTempoTimeSigMarkers(proj)
  data.count = count
  data.markers = {}
  
  -- IMPORTANT: Even if count is 0, there's always an implicit tempo marker at time 0
  if count == 0 then
    
    -- Get effective tempo/time sig at time 0
    local tsn_current, tsd_current, tempo_current = reaper.TimeMap_GetTimeSigAtTime(proj, 0)
    
    -- Create implicit first tempo marker
    data.markers[0] = {
      time = 0.0,
      measure_idx = 0,
      beat_pos = 0.0,
      bpm = tempo_current,
      num = tsn_current,
      denom = tsd_current,
      linear = false
    }
    data.count = 1  -- We now have 1 marker (the implicit one)
  else
    -- Per‑marker details → GetTempoTimeSigMarker(proj, ptidx, …)
    for i = 0, count - 1 do
      local ok, tpos, meas, beat, bpm, tsn, tsd, linear = reaper.GetTempoTimeSigMarker(proj, i)
      
      if ok then
        data.markers[i] = {
          time = tpos,
          measure_idx = meas,
          beat_pos = beat,
          bpm = bpm,
          num = tsn,
          denom = tsd,
          linear = linear
        }
      end
    end
  end
  
  return data
end

function Tempo.write(dest_proj, data, opts)
  if not data or not data.markers then 
    return false 
  end

  -- Clear existing tempo markers (optional, keeps first marker)
  if TEMPO_WRITE.clear_existing_markers then
    local existing_count = reaper.CountTempoTimeSigMarkers(dest_proj)
    for i = existing_count - 1, 1, -1 do
      reaper.DeleteTempoTimeSigMarker(dest_proj, i)
    end
  end

  -- Write tempo markers
  if TEMPO_WRITE.markers then
    local written_count = 0
    for i, marker in pairs(data.markers) do
      local success
      if i == 0 then
        -- Update first marker
        success = reaper.SetTempoTimeSigMarker(dest_proj, 0, marker.time, marker.measure_idx,
                                    marker.beat_pos, marker.bpm, marker.num, marker.denom, marker.linear)
      else
        -- Add new marker
        success = reaper.SetTempoTimeSigMarker(dest_proj, -1, marker.time, marker.measure_idx,
                                    marker.beat_pos, marker.bpm, marker.num, marker.denom, marker.linear)
      end
      if success then
        written_count = written_count + 1
      end
    end
  end

  return true
end

-- Utility functions for tempo analysis
function Tempo.get_tempo_at_time(proj, time)
  -- TimeMap_GetTimeSigAtTime returns: ts_num, ts_den, bpm
  local tsn, tsd, bpm = reaper.TimeMap_GetTimeSigAtTime(proj, time)
  return bpm, tsn, tsd
end

function Tempo.find_marker_at_time(proj, time)
  -- Index of marker at/before time → FindTempoTimeSigMarker(proj, time)
  return reaper.FindTempoTimeSigMarker(proj, time)
end

return Tempo