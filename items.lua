--[[
@description REAPER Project Engine - Media Items Module (ENHANCED)
@version 2.0
@about Handles items with complete fade support (fade in/out + crossfades)
--]]


local Items = {}
local config = require("config")
local ITEMS_WRITE = config.items
local Log = require("log")



-- ============================================================================
-- CROSSFADE DETECTION FUNCTIONS
-- ============================================================================

local function detect_item_overlaps_on_track(proj, track_idx)
  local overlaps = {}
  local track = reaper.GetTrack(proj, track_idx)
  if not track then return overlaps end
  
  local item_count = reaper.CountTrackMediaItems(track)
  local track_items = {}
  
  -- Collect all items on this track with their timing
  for item_idx = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, item_idx)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local lane = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE")
    
    table.insert(track_items, {
      item = item,
      item_idx = item_idx,
      position = pos,
      end_time = pos + len,
      length = len,
      lane = lane
    })
  end
  
  -- Sort items by position
  table.sort(track_items, function(a, b) return a.position < b.position end)
  
  -- Detect overlaps between consecutive items on same lane
  for i = 1, #track_items - 1 do
    local item1 = track_items[i]
    local item2 = track_items[i + 1]
    
    -- Check if items are on same lane (or both on regular track)
    if item1.lane == item2.lane then
      -- Check if item1 ends after item2 starts (overlap)
      if item1.end_time > item2.position then
        local overlap_start = item2.position
        local overlap_end = math.min(item1.end_time, item2.end_time)
        local overlap_length = overlap_end - overlap_start
        
        if overlap_length > 0 then
          local crossfade_data = {
            track_idx = track_idx,
            lane = item1.lane,
            item1_idx = item1.item_idx,
            item2_idx = item2.item_idx,
            overlap_start = overlap_start,
            overlap_end = overlap_end,
            overlap_length = overlap_length,
            -- Get crossfade shape information
            item1_fadeout_shape = reaper.GetMediaItemInfo_Value(item1.item, "C_FADEOUTSHAPE"),
            item2_fadein_shape = reaper.GetMediaItemInfo_Value(item2.item, "C_FADEINSHAPE"),
          }
          
          table.insert(overlaps, crossfade_data)
        end
      end
    end
  end
  
  return overlaps
end

-- ============================================================================
-- MAIN ITEM FUNCTIONS
-- ============================================================================

function Items.parse(proj)
  local data = {}
  data.items = {}
  data.crossfades = {}
  
  local track_count = reaper.CountTracks(proj)
  
  
  for track_idx = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, track_idx)
    
    -- Item count per track → CountTrackMediaItems(track)
    local item_count = reaper.CountTrackMediaItems(track)
    
    for item_idx = 0, item_count - 1 do
      -- Item by index → GetTrackMediaItem(tr, itemidx)
      local item = reaper.GetTrackMediaItem(track, item_idx)
      local item_data = {
        track_index = track_idx,
        item_index = item_idx,
        properties = {}
      }
      
      -- All item properties including COMPLETE fade support
      local properties = {
        -- Basic item properties
        "D_POSITION",        -- Position
        "D_LENGTH",          -- Length
        "D_SNAPOFFSET",      -- Snap offset
        "D_VOL",             -- Item gain
        "I_CURTAKE",         -- Active take index
        "F_FREEMODE_Y",      -- Free/fixed‑lane Y
        "F_FREEMODE_H",      -- Free/fixed‑lane height
        "B_FIXEDLANE_HIDDEN", -- Fixed‑lane hidden
        "I_CUSTOMCOLOR",     -- Custom color
        "B_MUTE",            -- Mute
        "B_LOOPSRC",         -- Loop source
        "B_ALLTAKESPLAY",    -- All‑takes‑play
        "I_GROUPID",         -- Group ID
        "B_UISEL",           -- UI selection
        
        -- COMPLETE FADE SUPPORT (restored)
        "D_FADEINLEN",       -- Fade‑in length in seconds
        "D_FADEOUTLEN",      -- Fade‑out length in seconds
        "D_FADEINDIR",       -- Fade‑in curvature (-1 to 1)
        "D_FADEOUTDIR",      -- Fade‑out curvature (-1 to 1)
        "D_FADEINLEN_AUTO",  -- Auto-fadein length (-1=no auto-fadein)
        "D_FADEOUTLEN_AUTO", -- Auto-fadeout length (-1=no auto-fadeout)
        "C_FADEINSHAPE",     -- Fade‑in shape (0-6: linear, fast start, etc.)
        "C_FADEOUTSHAPE",    -- Fade‑out shape (0-6)
      }
      
      for _, prop in ipairs(properties) do
        item_data.properties[prop] = reaper.GetMediaItemInfo_Value(item, prop)
      end
      
      -- Parse notes
      local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      item_data.notes = notes
      
      table.insert(data.items, item_data)
    end
    
    -- Detect crossfades on this track
    local track_crossfades = detect_item_overlaps_on_track(proj, track_idx)
    for _, crossfade in ipairs(track_crossfades) do
      table.insert(data.crossfades, crossfade)
    end
  end
  
  return data
end


function Items.write(dest_proj, data, opts)
  local track_mapping = opts and opts.track_mapping or {}
  if not data or not data.items then return false end

  -- Helper to clear all items on a track
  local function _clear_items_on_track(track)
    if not track then return end
    local cnt = reaper.CountTrackMediaItems(track)
    for i = cnt - 1, 0, -1 do
      local it = reaper.GetTrackMediaItem(track, i)
      if it then reaper.DeleteTrackMediaItem(dest_proj, track, it) end
    end
  end

  local items_by_track = {}
  local item_remap = {}  -- Maps (track_index, item_index) → dest_item

  -- Group items by mapped destination track index
  for _, item_data in ipairs(data.items) do
    local src_idx = item_data.track_index
    local mapped_idx = track_mapping[src_idx] or src_idx
    if not items_by_track[mapped_idx] then
      items_by_track[mapped_idx] = {}
    end
    table.insert(items_by_track[mapped_idx], item_data)
  end

  -- Create items per track
  for track_idx, track_items in pairs(items_by_track) do
    local mapped_idx = (opts and opts.track_mapping and opts.track_mapping[track_idx]) or track_idx
    local dest_track = reaper.GetTrack(dest_proj, mapped_idx)
    if not dest_track then goto continue end

    -- Optionally clear existing items on this destination track
    if ITEMS_WRITE.clear_existing_items then
      _clear_items_on_track(dest_track)
    end

    for item_idx, item_data in ipairs(track_items) do
      if not ITEMS_WRITE.create_items then goto skip_item_creation end
      local dest_item = reaper.AddMediaItemToTrack(dest_track)
      if dest_item then
        item_remap[string.format("%d_%d", item_data.track_index, item_data.item_index)] = dest_item
      end

      -- Set ALL properties including complete fade support
      if ITEMS_WRITE.properties then
        for prop, value in pairs(item_data.properties) do
          reaper.SetMediaItemInfo_Value(dest_item, prop, value)
        end
      end

      -- Set notes
      if ITEMS_WRITE.notes and item_data.notes then
        reaper.GetSetMediaItemInfo_String(dest_item, "P_NOTES", item_data.notes, true)
      end

      ::skip_item_creation::
    end

    ::continue::
  end

  -- Apply crossfades after all items are created (optional)
  if ITEMS_WRITE.crossfades and data.crossfades and #data.crossfades > 0 then
    Items.apply_crossfades(dest_proj, data.crossfades, item_remap, track_mapping)
  end

  return true
end

function Items.apply_crossfades(dest_proj, crossfades, item_remap, track_mapping)
  track_mapping = track_mapping or {}
  for i, crossfade in ipairs(crossfades) do
    local mapped_idx = track_mapping[crossfade.track_idx] or crossfade.track_idx
    local dest_track = reaper.GetTrack(dest_proj, mapped_idx)
    if dest_track then
      local item1 = item_remap and item_remap[string.format("%d_%d", crossfade.track_idx, crossfade.item1_idx)]
      local item2 = item_remap and item_remap[string.format("%d_%d", crossfade.track_idx, crossfade.item2_idx)]
      
      if item1 and item2 then
        
        -- Ensure items overlap correctly
        local item1_pos = reaper.GetMediaItemInfo_Value(item1, "D_POSITION")
        local item1_len = reaper.GetMediaItemInfo_Value(item1, "D_LENGTH")
        local item2_pos = reaper.GetMediaItemInfo_Value(item2, "D_POSITION")
        
        local current_overlap = (item1_pos + item1_len) - item2_pos
        
        if math.abs(current_overlap - crossfade.overlap_length) > 0.001 then
          -- Adjust item1 length to create correct overlap
          local new_item1_len = item2_pos + crossfade.overlap_length - item1_pos
          reaper.SetMediaItemLength(item1, new_item1_len, false)
        end
        
        -- Set crossfade shapes (these should already be set from properties, but ensure they're correct)
        reaper.SetMediaItemInfo_Value(item1, "C_FADEOUTSHAPE", crossfade.item1_fadeout_shape)
        reaper.SetMediaItemInfo_Value(item2, "C_FADEINSHAPE", crossfade.item2_fadein_shape)
        
        -- Apply crossfade using REAPER action
        reaper.Main_OnCommand(40297, 0)  -- Clear selection
        reaper.SetMediaItemSelected(item1, true)
        reaper.SetMediaItemSelected(item2, true)
        
        -- Create time selection over the overlap area
        reaper.GetSet_LoopTimeRange2(dest_proj, true, false, crossfade.overlap_start, crossfade.overlap_end, false)
        
        -- Apply crossfade
        reaper.Main_OnCommand(40916, 0)  -- Item: Crossfade items within time selection
        

      else

      end
    end
  end
  
  -- Clear selections and time selection
  reaper.Main_OnCommand(40297, 0)  -- Clear item selection
  reaper.GetSet_LoopTimeRange2(dest_proj, true, false, 0, 0, false)  -- Clear time selection
end

-- ============================================================================
-- UTILITY FUNCTIONS (ENHANCED)
-- ============================================================================

function Items.get_items_on_track(data, track_index)
  if not data or not data.items then return {} end
  
  local track_items = {}
  for _, item in ipairs(data.items) do
    if item.track_index == track_index then
      table.insert(track_items, item)
    end
  end
  return track_items
end

function Items.get_items_in_time_range(data, start_time, end_time)
  if not data or not data.items then return {} end
  
  local range_items = {}
  for _, item in ipairs(data.items) do
    local pos = item.properties["D_POSITION"] or 0
    local length = item.properties["D_LENGTH"] or 0
    local item_end = pos + length
    
    -- Check if item overlaps with time range
    if pos < end_time and item_end > start_time then
      table.insert(range_items, item)
    end
  end
  return range_items
end

function Items.filter_by_position(data, start_pos, end_pos)
  if not data or not data.items then return {} end
  
  local position_items = {}
  for _, item in ipairs(data.items) do
    local pos = item.properties["D_POSITION"] or 0
    if pos >= start_pos and pos <= end_pos then
      table.insert(position_items, item)
    end
  end
  return position_items
end

function Items.get_items_with_fades(data)
  if not data or not data.items then return {} end
  
  local fade_items = {}
  for _, item in ipairs(data.items) do
    local fade_in = item.properties["D_FADEINLEN"] or 0
    local fade_out = item.properties["D_FADEOUTLEN"] or 0
    local auto_fade_in = item.properties["D_FADEINLEN_AUTO"] or -1
    local auto_fade_out = item.properties["D_FADEOUTLEN_AUTO"] or -1
    
    if fade_in > 0 or fade_out > 0 or auto_fade_in > 0 or auto_fade_out > 0 then
      table.insert(fade_items, item)
    end
  end
  return fade_items
end

function Items.get_crossfades_on_track(data, track_index)
  if not data or not data.crossfades then return {} end
  
  local track_crossfades = {}
  for _, crossfade in ipairs(data.crossfades) do
    if crossfade.track_idx == track_index then
      table.insert(track_crossfades, crossfade)
    end
  end
  return track_crossfades
end

function Items.get_item_statistics(data)
  if not data or not data.items then return {} end
  
  local stats = {
    total_items = #data.items,
    items_by_track = {},
    muted_items = 0,
    items_with_fades = 0,
    items_with_manual_fades = 0,
    items_with_auto_fades = 0,
    custom_colored_items = 0,
    crossfades = data.crossfades and #data.crossfades or 0,
    fade_shapes = {},
    avg_fade_in_length = 0,
    avg_fade_out_length = 0,
    avg_crossfade_length = 0
  }
  
  local total_fade_in = 0
  local total_fade_out = 0
  local total_crossfade = 0
  local fade_in_count = 0
  local fade_out_count = 0
  
  -- Count items per track and analyze fades
  for _, item in ipairs(data.items) do
    local track_idx = item.track_index
    stats.items_by_track[track_idx] = (stats.items_by_track[track_idx] or 0) + 1
    
    -- Count muted items
    if item.properties["B_MUTE"] and item.properties["B_MUTE"] > 0 then
      stats.muted_items = stats.muted_items + 1
    end
    
    -- Analyze fades
    local fade_in = item.properties["D_FADEINLEN"] or 0
    local fade_out = item.properties["D_FADEOUTLEN"] or 0
    local auto_fade_in = item.properties["D_FADEINLEN_AUTO"] or -1
    local auto_fade_out = item.properties["D_FADEOUTLEN_AUTO"] or -1
    
    -- Count items with fades
    if fade_in > 0 or fade_out > 0 or auto_fade_in > 0 or auto_fade_out > 0 then
      stats.items_with_fades = stats.items_with_fades + 1
      
      if fade_in > 0 or fade_out > 0 then
        stats.items_with_manual_fades = stats.items_with_manual_fades + 1
      end
      
      if auto_fade_in > 0 or auto_fade_out > 0 then
        stats.items_with_auto_fades = stats.items_with_auto_fades + 1
      end
    end
    
    -- Fade length statistics
    if fade_in > 0 then
      total_fade_in = total_fade_in + fade_in
      fade_in_count = fade_in_count + 1
    end
    
    if fade_out > 0 then
      total_fade_out = total_fade_out + fade_out
      fade_out_count = fade_out_count + 1
    end
    
    -- Fade shape statistics
    local fade_in_shape = item.properties["C_FADEINSHAPE"] or 0
    local fade_out_shape = item.properties["C_FADEOUTSHAPE"] or 0
    
    if fade_in > 0 then
      local shape_name = Items.decode_fade_shape(fade_in_shape)
      stats.fade_shapes["in_" .. shape_name] = (stats.fade_shapes["in_" .. shape_name] or 0) + 1
    end
    
    if fade_out > 0 then
      local shape_name = Items.decode_fade_shape(fade_out_shape)
      stats.fade_shapes["out_" .. shape_name] = (stats.fade_shapes["out_" .. shape_name] or 0) + 1
    end
    
    -- Count custom colored items
    if item.properties["I_CUSTOMCOLOR"] and item.properties["I_CUSTOMCOLOR"] ~= 0 then
      stats.custom_colored_items = stats.custom_colored_items + 1
    end
  end
  
  -- Calculate averages
  if fade_in_count > 0 then
    stats.avg_fade_in_length = total_fade_in / fade_in_count
  end
  
  if fade_out_count > 0 then
    stats.avg_fade_out_length = total_fade_out / fade_out_count
  end
  
  -- Crossfade statistics
  if data.crossfades then
    for _, crossfade in ipairs(data.crossfades) do
      total_crossfade = total_crossfade + crossfade.overlap_length
    end
    
    if #data.crossfades > 0 then
      stats.avg_crossfade_length = total_crossfade / #data.crossfades
    end
  end
  
  return stats
end

function Items.decode_fade_shape(shape_id)
  local shapes = {
    [0] = "Linear",
    [1] = "Fast Start",
    [2] = "Fast End", 
    [3] = "Slow Start/End",
    [4] = "Sharp Curve",
    [5] = "Smooth Curve",
    [6] = "No Curve"
  }
  return shapes[shape_id] or ("Unknown_" .. tostring(shape_id))
end

-- ============================================================================
-- FADE SHAPE MANAGEMENT
-- ============================================================================

function Items.set_global_fade_shapes(fade_in_shape, fade_out_shape)
  -- Set global fade shapes for new items
  if fade_in_shape and fade_in_shape >= 0 and fade_in_shape <= 6 then
    -- Use actions to set global fade-in shape
    local fade_in_actions = {
      [0] = 41518, [1] = 41519, [2] = 41520, [3] = 41521, [4] = 41522, [5] = 41523, [6] = 41524
    }
    if fade_in_actions[fade_in_shape] then
      reaper.Main_OnCommand(fade_in_actions[fade_in_shape], 0)
    end
  end
  
  if fade_out_shape and fade_out_shape >= 0 and fade_out_shape <= 6 then
    -- Use actions to set global fade-out shape
    local fade_out_actions = {
      [0] = 41525, [1] = 41526, [2] = 41527, [3] = 41528, [4] = 41529, [5] = 41530, [6] = 41531
    }
    if fade_out_actions[fade_out_shape] then
      reaper.Main_OnCommand(fade_out_actions[fade_out_shape], 0)
    end
  end
end


-- ============================================================================
-- LANE-AWARE WRITE FUNCTION FOR INTEGRATOR
-- ============================================================================

function Items.write_with_tracks_data(dest_proj, data, track_data, opts)
  if not data or not data.items then return false end
  local track_mapping = opts and opts.track_mapping or {}
  local ITEMS_WRITE = opts and opts.items_cfg or config.items

  Log.module("Items", "📝 Starting write_with_tracks_data")

  local items_by_track = {}
  local item_remap = {}  -- Maps original (track_index, item_index) → dest_item
  local to_create = opts and opts.to_create or {}

  for _, item_data in ipairs(data.items) do
    local src_idx = item_data.track_index
    local mapped_idx = track_mapping[src_idx]

    if mapped_idx or to_create[src_idx] then
      local dest_idx = mapped_idx or src_idx
      if not items_by_track[dest_idx] then
        items_by_track[dest_idx] = {}
      end
      table.insert(items_by_track[dest_idx], item_data)
    end
  end

  for dest_idx, track_items in pairs(items_by_track) do
    Log.module("Items", string.format("🎯 Writing items to destination track index: %d", dest_idx))
    local dest_track = reaper.GetTrack(dest_proj, dest_idx)
    if not dest_track then goto continue end

    if ITEMS_WRITE.clear_existing_items then
      local cnt = reaper.CountTrackMediaItems(dest_track)
      for i = cnt - 1, 0, -1 do
        local it = reaper.GetTrackMediaItem(dest_track, i)
        if it then reaper.DeleteTrackMediaItem(dest_proj, dest_track, it) end
      end
    end

    for _, item_data in ipairs(track_items) do
      if not ITEMS_WRITE.create_items then goto skip_item_creation end
      local dest_item = reaper.AddMediaItemToTrack(dest_track)
      Log.module("Items", string.format("➕ Created item on track %d from source track %d", dest_idx, item_data.track_index))

      if dest_item then
        item_remap[string.format("%d_%d", item_data.track_index, item_data.item_index)] = dest_item
      end

      if ITEMS_WRITE.properties then
        for prop, value in pairs(item_data.properties) do
          reaper.SetMediaItemInfo_Value(dest_item, prop, value)
        end
      end

      if ITEMS_WRITE.notes and item_data.notes then
        reaper.GetSetMediaItemInfo_String(dest_item, "P_NOTES", item_data.notes, true)
      end

      ::skip_item_creation::
    end

    ::continue::
  end

  if ITEMS_WRITE.crossfades and data.crossfades and #data.crossfades > 0 then
    Items.apply_crossfades(dest_proj, data.crossfades, item_remap, track_mapping)
  end

  Log.module("Items", "✅ Finished writing items")
  return true
end

return Items