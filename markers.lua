--[[
@description REAPER Project Engine - Markers & Regions Module
@version 1.0
@about Handles project markers and regions
--]]

local Markers = {}

local config = require("config")
local MARKERS_WRITE = config.markers


function Markers.parse(proj)
  local data = {}
  
  -- Total counts → CountProjectMarkers(proj, &num_markers, &num_regions)
  local num_markers, num_regions = reaper.CountProjectMarkers(proj)
  data.num_markers = num_markers
  data.num_regions = num_regions
  data.items = {}
  
  local total_count = num_markers + num_regions
  
  -- Marker/Region details → EnumProjectMarkers3(proj, idx, …)
  for i = 0, total_count - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(proj, i)
    if retval > 0 then
      local item = {
        is_region = isrgn,
        position = pos,
        end_pos = rgnend,
        name = name,
        number = markrgnindexnumber,
        color = color
      }
      
      -- GUID for marker/region → GetSetProjectInfo_String(proj, "MARKER_GUID:X", "", false)
      local _, guid = reaper.GetSetProjectInfo_String(proj, "MARKER_GUID:" .. i, "", false)
      item.guid = guid
      
      data.items[i] = item
    end
  end
  
  return data
end

function Markers.write(dest_proj, data, opts)
  if not data or not data.items then return false end
  
  -- Clear existing markers (optional)
  if MARKERS_WRITE.clear_existing then
    local existing_count = reaper.CountProjectMarkers(dest_proj)
    for i = existing_count - 1, 0, -1 do
      reaper.DeleteProjectMarkerByIndex(dest_proj, i)
    end
  end
  
  -- Add markers/regions according to toggles
  for _, item in pairs(data.items) do
    if (not item.is_region and MARKERS_WRITE.markers) or (item.is_region and MARKERS_WRITE.regions) then
      reaper.AddProjectMarker2(dest_proj, item.is_region, item.position,
                               item.end_pos or 0, item.name, item.number or -1, item.color or 0)
    end
  end
  
  return true
end

-- Utility functions for marker operations
function Markers.find_marker_by_name(data, name)
  if not data or not data.items then return nil end
  
  for _, item in pairs(data.items) do
    if item.name == name then
      return item
    end
  end
  return nil
end

function Markers.filter_by_type(data, is_region)
  if not data or not data.items then return {} end
  
  local filtered = {}
  for _, item in pairs(data.items) do
    if item.is_region == is_region then
      table.insert(filtered, item)
    end
  end
  return filtered
end

return Markers