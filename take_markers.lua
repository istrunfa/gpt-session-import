--[[
@description REAPER Project Engine - Take Markers Module
@version 1.0
@about Handles take markers per take
--]]


local TakeMarkers = {}

local config = require("config")
local TAKEMARKERS_WRITE = config.take_markers
local Log = require("log")


function TakeMarkers.parse(proj)
  local data = {}
  data.take_markers = {}
  
  local track_count = reaper.CountTracks(proj)
  
  for track_idx = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, track_idx)
    local item_count = reaper.CountTrackMediaItems(track)
    
    for item_idx = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, item_idx)
      local take_count = reaper.CountTakes(item)
      
      for take_idx = 0, take_count - 1 do
        local take = reaper.GetTake(item, take_idx)
        if take then
          -- Count → GetNumTakeMarkers(tk)
          local marker_count = reaper.GetNumTakeMarkers(take)
          
          if marker_count > 0 then
            local take_marker_data = {
              track_index = track_idx,
              item_index = item_idx,
              take_index = take_idx,
              count = marker_count,
              markers = {}
            }
            
            for marker_idx = 0, marker_count - 1 do
              -- Per marker → GetTakeMarker(tk, idx, nameBuf, sz, &colorOpt)
              local pos, name, color = reaper.GetTakeMarker(take, marker_idx)
              take_marker_data.markers[marker_idx] = {
                position = pos,
                name = name,
                color = color
              }
            end
            
            table.insert(data.take_markers, take_marker_data)
          end
        end
      end
    end
  end
  
  return data
end

function TakeMarkers.write(dest_proj, data, opts)
  if not data or not data.take_markers then return false end
  Log.module("TakeMarkers", "📝 Starting take marker write phase")
  local track_mapping = opts and opts.track_mapping or nil

  for _, take_marker_data in ipairs(data.take_markers) do
    local original_idx = take_marker_data.track_index
    local mapped_idx = track_mapping and track_mapping[original_idx] or original_idx
    local dest_track = reaper.GetTrack(dest_proj, mapped_idx)
    if not dest_track then
      Log.module("TakeMarkers", string.format("⛔ No dest track for mapped index %d", mapped_idx))
      goto continue
    end

    local key = string.format("%d_%d", original_idx, take_marker_data.item_index)
    local item = (type(opts and opts.item_mapping) == "table" and opts.item_mapping[key]) or reaper.GetTrackMediaItem(dest_track, take_marker_data.item_index)
    if not item then
      Log.module("TakeMarkers", string.format("⛔ No destination item for track %d, item %d", mapped_idx, take_marker_data.item_index))
      goto continue
    end

    local take = reaper.GetTake(item, take_marker_data.take_index)
    if not take then
      Log.module("TakeMarkers", string.format("⛔ No take %d on item [%s]", take_marker_data.take_index, key))
      goto continue
    end

    -- Validate take mapping alignment
    local actual_idx = reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(item), "IP_TRACKNUMBER") - 1
    if actual_idx ~= mapped_idx then
      Log.module("TakeMarkers", string.format("⛔ Track mapping mismatch: expected %d, got %d", mapped_idx, actual_idx))
      goto continue
    end

    -- Optionally clear existing take markers first
    if TAKEMARKERS_WRITE.clear_existing then
      TakeMarkers.clear_all_markers(take)
    end

    -- Set take markers (optional)
    if TAKEMARKERS_WRITE.markers then
      Log.module("TakeMarkers", string.format("🎯 Applying %d marker(s) to take %d on item [%s]", #take_marker_data.markers, take_marker_data.take_index, key))
      for marker_idx, marker in pairs(take_marker_data.markers) do
        reaper.SetTakeMarker(take, -1, marker.name, marker.position, marker.color)
      end
    end

    ::continue::
  end

  Log.module("TakeMarkers", "✅ Finished take marker write phase")
  return true
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function TakeMarkers.get_markers_for_take(data, track_index, item_index, take_index)
  if not data or not data.take_markers then return nil end
  
  for _, take_marker_data in ipairs(data.take_markers) do
    if take_marker_data.track_index == track_index and 
       take_marker_data.item_index == item_index and 
       take_marker_data.take_index == take_index then
      return take_marker_data
    end
  end
  return nil
end

function TakeMarkers.find_marker_by_name(data, track_index, item_index, take_index, name)
  local take_markers = TakeMarkers.get_markers_for_take(data, track_index, item_index, take_index)
  if not take_markers then return nil end
  
  for _, marker in pairs(take_markers.markers) do
    if marker.name == name then
      return marker
    end
  end
  return nil
end

function TakeMarkers.get_statistics(data)
  if not data or not data.take_markers then return {} end
  
  local stats = {
    takes_with_markers = #data.take_markers,
    total_take_markers = 0
  }
  
  for _, take_marker_data in ipairs(data.take_markers) do
    stats.total_take_markers = stats.total_take_markers + (take_marker_data.count or 0)
  end
  
  return stats
end

function TakeMarkers.clear_all_markers(take)
  -- Remove all existing take markers from a take
  local marker_count = reaper.GetNumTakeMarkers(take)
  for i = marker_count - 1, 0, -1 do
    reaper.DeleteTakeMarker(take, i)
  end
end

return TakeMarkers