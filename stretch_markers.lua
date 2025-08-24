--[[
@description REAPER Project Engine - Stretch Markers Module (DEBUG ENHANCED)
@version 1.1
@about Handles stretch markers per take with comprehensive debugging
--]]

local StretchMarkers = {}

local Log = require("log")

local config = require("config")
local STRETCH_WRITE = config.stretch_markers


function StretchMarkers.parse(proj)
  local data = {}
  data.stretch_markers = {}
  
  local track_count = reaper.CountTracks(proj)
  local total_takes_checked = 0
  local takes_with_markers = 0
  local total_individual_markers = 0
  
  for track_idx = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, track_idx)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    local item_count = reaper.CountTrackMediaItems(track)
    
    for item_idx = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, item_idx)
      local take_count = reaper.CountTakes(item)
      
      for take_idx = 0, take_count - 1 do
        local take = reaper.GetTake(item, take_idx)
        total_takes_checked = total_takes_checked + 1
        
        if take then
          local take_name = reaper.GetTakeName(take)
          
          -- Count → GetTakeNumStretchMarkers(tk)
          local marker_count = reaper.GetTakeNumStretchMarkers(take)
          
          if marker_count > 0 then
            takes_with_markers = takes_with_markers + 1
            total_individual_markers = total_individual_markers + marker_count
            
            local stretch_data = {
              track_index = track_idx,
              item_index = item_idx,
              take_index = take_idx,
              take_name = take_name,
              count = marker_count,
              markers = {}
            }
            
            for marker_idx = 0, marker_count - 1 do
              -- Per marker → GetTakeStretchMarker(tk, idx, &pos, &srcpos)
              local retval, pos, srcpos = reaper.GetTakeStretchMarker(take, marker_idx)
              
              if retval >= 0 then
                -- Also get slope → GetTakeStretchMarkerSlope(tk, idx)
                local slope = reaper.GetTakeStretchMarkerSlope(take, marker_idx)
                
                stretch_data.markers[marker_idx] = {
                  position = pos,
                  source_position = srcpos or pos,
                  slope = slope,
                  index = retval
                }
                
              end
            end
            
            table.insert(data.stretch_markers, stretch_data)
          end
        end
      end
    end
  end
  
  return data
end

function StretchMarkers.write(dest_proj, data, opts)
  if not data or not data.stretch_markers then 
    return false 
  end

  Log.module("StretchMarkers", "📝 Starting stretch marker write phase")
  
  local total_markers_written = 0
  local track_mapping = opts and opts.track_mapping or {}
  
  for group_idx, stretch_data in ipairs(data.stretch_markers) do
    
    -- Track mapping logic
    local dest_track
    local item_idx = stretch_data.item_index
    local original_idx = stretch_data.track_index
    local mapped_idx = opts and opts.track_mapping and opts.track_mapping[original_idx] or original_idx
    dest_track = reaper.GetTrack(dest_proj, mapped_idx)
    
    if not dest_track then 
      Log.module("StretchMarkers", string.format("⛔ Skipping: dest_track/item/take not found for original track %d, item %d, take %d", original_idx, item_idx, stretch_data.take_index or -1))
      goto continue 
    end
    
    local key = string.format("%d_%d", original_idx, item_idx)
    local dest_item = (type(opts.item_mapping) == "table" and opts.item_mapping[key]) or reaper.GetTrackMediaItem(dest_track, item_idx)
    if not dest_item then 
      Log.module("StretchMarkers", string.format("⛔ Skipping: dest_track/item/take not found for original track %d, item %d, take %d", original_idx, item_idx, stretch_data.take_index or -1))
      goto continue 
    end
    
    local take_idx = stretch_data.take_index
    local dest_take = reaper.GetTake(dest_item, take_idx)
    if not dest_take then 
      Log.module("StretchMarkers", string.format("⛔ Skipping: dest_track/item/take not found for original track %d, item %d, take %d", original_idx, item_idx, stretch_data.take_index or -1))
      goto continue 
    end
    
    local dest_take_name = reaper.GetTakeName(dest_take)
    
    -- Clear existing stretch markers first (optional)
    if STRETCH_WRITE.clear_existing then
      local existing_markers = reaper.GetTakeNumStretchMarkers(dest_take)
      if existing_markers > 0 then
        for i = existing_markers - 1, 0, -1 do
          reaper.DeleteTakeStretchMarkers(dest_take, i, 1)
        end
      end
    end
    
    -- Set stretch markers
    
    -- Sort markers by position before writing to avoid conflicts
    local sorted_markers = {}
    for marker_idx, marker in pairs(stretch_data.markers) do
      table.insert(sorted_markers, {idx = marker_idx, data = marker})
    end
    table.sort(sorted_markers, function(a, b) return a.data.position < b.data.position end)
    
    
    -- PASS 1: Create all markers first (positions only)
    local created_markers = {}
    if STRETCH_WRITE.markers then
      for i, sorted_marker in ipairs(sorted_markers) do
        local marker_idx = sorted_marker.idx
        local marker = sorted_marker.data
        local result = reaper.SetTakeStretchMarker(dest_take, -1, marker.position, marker.source_position)
        if result >= 0 then
          created_markers[result] = {original_idx = marker_idx, slope = marker.slope}
          total_markers_written = total_markers_written + 1
        end
      end
    end
    
    -- Small delay to let REAPER process the markers
    reaper.defer(function() end)
    
    -- PASS 2: Set slopes on all created markers (optional)
    if STRETCH_WRITE.slopes then
      for result_idx, marker_info in pairs(created_markers) do
        reaper.SetTakeStretchMarkerSlope(dest_take, result_idx, marker_info.slope)
      end
    end
    
    -- Verify markers were added
    local final_marker_count = reaper.GetTakeNumStretchMarkers(dest_take)

    Log.module("StretchMarkers", string.format("🎯 Wrote %d markers to take %d on track %d", stretch_data.count, stretch_data.take_index, mapped_idx))
    
    ::continue::
  end

  Log.module("StretchMarkers", string.format("✅ Finished writing %d total markers", total_markers_written))
  
  return true
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function StretchMarkers.get_markers_for_take(data, track_index, item_index, take_index)
  if not data or not data.stretch_markers then return nil end
  
  for _, stretch_data in ipairs(data.stretch_markers) do
    if stretch_data.track_index == track_index and 
       stretch_data.item_index == item_index and 
       stretch_data.take_index == take_index then
      return stretch_data
    end
  end
  return nil
end

function StretchMarkers.get_statistics(data)
  if not data or not data.stretch_markers then 
    return {
      takes_with_stretch_markers = 0,
      total_stretch_markers = 0
    }
  end
  
  local stats = {
    takes_with_stretch_markers = #data.stretch_markers,
    total_stretch_markers = 0,
    tracks_with_stretch_markers = {},
    avg_markers_per_take = 0
  }
  
  for _, stretch_data in ipairs(data.stretch_markers) do
    stats.total_stretch_markers = stats.total_stretch_markers + (stretch_data.count or 0)
    stats.tracks_with_stretch_markers[stretch_data.track_index] = true
  end
  
  if #data.stretch_markers > 0 then
    stats.avg_markers_per_take = stats.total_stretch_markers / #data.stretch_markers
  end
  
  -- Count unique tracks
  local track_count = 0
  for _ in pairs(stats.tracks_with_stretch_markers) do
    track_count = track_count + 1
  end
  stats.tracks_with_stretch_markers_count = track_count
  
  return stats
end

function StretchMarkers.clear_all_markers(take)
  -- Remove all existing stretch markers from a take
  local marker_count = reaper.GetTakeNumStretchMarkers(take)
  for i = marker_count - 1, 0, -1 do
    reaper.DeleteTakeStretchMarkers(take, i, 1)
  end
  return marker_count
end

return StretchMarkers