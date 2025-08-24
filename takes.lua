--[[
@description REAPER Project Engine - Takes Module
@version 1.0
@about Handles takes with FX, MIDI data, and audio sources (now with take envelope parsing/writing)
--]]

local Takes = {}

local config = require("config")
local TAKES_WRITE = config.takes
local Log = require("log")


function Takes.parse(proj)
  local data = {}
  data.takes = {}
  
  local track_count = reaper.CountTracks(proj)
  
  for track_idx = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, track_idx)
    local item_count = reaper.CountTrackMediaItems(track)
    
    for item_idx = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, item_idx)
      
      -- Take count in item → CountTakes(item)
      local take_count = reaper.CountTakes(item)
      
      -- Active take → GetActiveTake(item)
      local active_take = reaper.GetActiveTake(item)
      
      for take_idx = 0, take_count - 1 do
        -- Take by index → GetTake(item, takeidx)
        local take = reaper.GetTake(item, take_idx)
        if take then
          local take_data = {
            track_index = track_idx,
            item_index = item_idx,
            take_index = take_idx,
            is_active = (take == active_take),
            properties = {},
            fx_data = {}
          }
          
          -- Take name → GetSetMediaItemTakeInfo_String(tk, "P_NAME", buf, false)
          local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
          take_data.name = name
          
          -- All take properties
          local properties = {
            "D_STARTOFFS",       -- Source start offset
            "D_VOL",             -- Take volume
            "D_PAN",             -- Pan
            "D_PANLAW",          -- Pan law
            "D_PLAYRATE",        -- Playback rate
            "D_PITCH",           -- Pitch
            "B_PPITCH",          -- Preserve pitch
            "I_CHANMODE",        -- Channel mode
            "I_PITCHMODE",       -- Pitch‑shifter mode
            "I_STRETCHFLAGS",    -- Stretch flags
            "F_STRETCHFADESIZE", -- Stretch fade size
            "I_CUSTOMCOLOR",     -- Custom color
            "I_TAKEFX_NCH"       -- Internal FX channel count
          }
          
          for _, prop in ipairs(properties) do
            take_data.properties[prop] = reaper.GetMediaItemTakeInfo_Value(take, prop)
          end
          
          -- Parse take FX
          take_data.fx_data = Takes.parse_take_fx(take)
          
          -- Parse take envelopes
          take_data.envelopes = Takes.parse_take_envelopes(take)
          
          -- Handle source content
          if reaper.TakeIsMIDI(take) then
            take_data.type = "MIDI"
            take_data.midi_data = Takes.parse_midi_data(take)
            -- Capture the MIDI source pointer so we can set a proper MIDI source on write
            take_data.midi_source = reaper.GetMediaItemTake_Source(take)
          else
            take_data.type = "AUDIO"
            take_data.source = reaper.GetMediaItemTake_Source(take)
          end
          
          table.insert(data.takes, take_data)
        end
      end
    end
  end
  
  return data
end

function Takes.parse_take_envelopes(take)
  local envelopes = {}
  local env_count = reaper.CountTakeEnvelopes(take) or 0

  for envidx = 0, env_count - 1 do
    local env = reaper.GetTakeEnvelope(take, envidx)
    if env then
      local _, env_name = reaper.GetEnvelopeName(env)
      local points = {}

      -- Underlying envelope (-1) — automation items not handled here by design
      local pt_count = reaper.CountEnvelopePointsEx(env, -1) or 0
      for ptidx = 0, pt_count - 1 do
        local ok, time, value, shape, tension, selected = reaper.GetEnvelopePointEx(env, -1, ptidx)
        if ok then
          points[#points + 1] = {
            time = time,
            value = value,
            shape = shape,
            tension = tension,
            selected = (selected == true or selected == 1)
          }
        end
      end

      envelopes[#envelopes + 1] = {
        name = env_name or "",
        points = points
      }
    end
  end

  return {
    count = env_count,
    envelopes = envelopes
  }
end

function Takes.parse_midi_data(take)
  local midi_data = {}
  
  -- Get all MIDI events
  local ok, midi_string = reaper.MIDI_GetAllEvts(take)
  if ok and midi_string then
    midi_data.events = midi_string
    
    -- Get note count for statistics
    local note_count = reaper.MIDI_CountEvts(take)
    midi_data.note_count = note_count
  end
  
  return midi_data
end

function Takes.write(dest_proj, data, opts)
  if not data or not data.takes then return false end

  Log.module("Takes", "📝 Starting takes writing phase")

  -- Group takes by item
  local takes_by_item = {}
  for _, take_data in ipairs(data.takes) do
    local key = take_data.track_index .. "_" .. take_data.item_index
    if not takes_by_item[key] then
      takes_by_item[key] = {}
    end
    table.insert(takes_by_item[key], take_data)
  end

  -- Create takes for each item
  for item_key, item_takes in pairs(takes_by_item) do
    local original_track_idx = item_takes[1].track_index
    local item_idx = item_takes[1].item_index
    local track_mapping = opts and opts.track_mapping or {}
    local track_idx = track_mapping[original_track_idx] or original_track_idx

    local dest_track = reaper.GetTrack(dest_proj, track_idx)
    if not dest_track then goto continue end

    local dest_item = reaper.GetTrackMediaItem(dest_track, item_idx)
    if not dest_item then goto continue end

    -- Validate actual item handle if item_mapping is available and is a table
    if opts and type(opts.item_mapping) == "table" then
      local key = string.format("%d_%d", original_track_idx, item_idx)
      local actual_item = opts.item_mapping[key]
      if actual_item and actual_item ~= dest_item then
        dest_item = actual_item
        if not dest_item then goto continue end
      end
    end

    Log.module("Takes", string.format("🎯 Writing %d takes to item [%s] on track %d", #item_takes, item_key, track_idx))

    -- Clear any default takes (optional)
    if TAKES_WRITE.clear_default_takes then
      local default_count = reaper.CountTakes(dest_item)
      for i = default_count - 1, 0, -1 do
        local default_take = reaper.GetTake(dest_item, i)
        if default_take then
          reaper.DeleteTake(default_take)
        end
      end
    end

    local active_take = nil

    -- Create takes
    for _, take_data in ipairs(item_takes) do
      local dest_take = reaper.AddTakeToMediaItem(dest_item)
      Log.module("Takes", string.format("➕ Created take %d (%s)", take_data.take_index or 0, take_data.name or "unnamed"))

      -- Set name
      if TAKES_WRITE.name then
        reaper.GetSetMediaItemTakeInfo_String(dest_take, "P_NAME", take_data.name or "", true)
      end

      -- Set properties
      if TAKES_WRITE.properties then
        for prop, value in pairs(take_data.properties) do
          reaper.SetMediaItemTakeInfo_Value(dest_take, prop, value)
        end
      end

      -- Set source content
      if TAKES_WRITE.source_content then
        if take_data.type == "MIDI" and take_data.midi_data and take_data.midi_data.events then
          -- Ensure destination take is a real MIDI take by assigning a MIDI source first (when available)
          if take_data.midi_source then
            reaper.SetMediaItemTake_Source(dest_take, take_data.midi_source)
          end
          -- Now write full MIDI event stream
          reaper.MIDI_SetAllEvts(dest_take, take_data.midi_data.events)
          reaper.MIDI_Sort(dest_take)
        elseif take_data.type == "AUDIO" and take_data.source then
          reaper.SetMediaItemTake_Source(dest_take, take_data.source)
        end
      end

      -- Apply FX (exact cloning if possible, fallback to parameter/preset reconstruction)
      if TAKES_WRITE.fx then
        Takes.apply_take_fx(dest_take, take_data, {
          source_proj = opts and opts.source_proj,
          track_mapping = track_mapping,
          original_track_index = take_data.track_index
        })
      end

      -- Write take envelopes
      if TAKES_WRITE.envelopes then
        Takes.write_take_envelopes(dest_take, take_data.envelopes, {
          track_mapping = track_mapping,
          original_track_index = take_data.track_index
        })
      end

      -- Track active take
      if take_data.is_active then
        active_take = dest_take
      end
    end

    -- Set active take
    if TAKES_WRITE.set_active_take and active_take then
      reaper.SetActiveTake(active_take)
    end

    ::continue::
  end

  Log.module("Takes", "✅ Finished takes writing phase")
  return true
end

function Takes.apply_take_fx(take, take_data, opts)
  if not take_data then return false end
  Log.module("Takes", "🎛 Applying take FX")

  local fx_data = take_data.fx_data or { count = 0, fx = {} }

  -- If a source project handle is provided, clone FX directly from source take for full fidelity (3rd‑party safe)
  local src_proj = opts and opts.source_proj or nil
  if src_proj then
    local src_index = opts.original_track_index or take_data.track_index
    local track_mapping = opts and opts.track_mapping or {}
    local mapped_index = track_mapping[src_index] or src_index
    local src_track = reaper.GetTrack(src_proj, mapped_index)
    if src_track then
      local src_item = reaper.GetTrackMediaItem(src_track, take_data.item_index)
      if src_item then
        local src_take = reaper.GetTake(src_item, take_data.take_index)
        if src_take then
          -- Clear existing FX on destination take
          for i = reaper.TakeFX_GetCount(take) - 1, 0, -1 do
            reaper.TakeFX_Delete(take, i)
          end
          -- Append in order by copying instances with full state
          local src_fx_count = reaper.TakeFX_GetCount(src_take)
          for fx_idx = 0, src_fx_count - 1 do
            local dest_pos = reaper.TakeFX_GetCount(take) -- append
            reaper.TakeFX_CopyToTake(src_take, fx_idx, take, dest_pos, false) -- false = copy (not move)
          end
          Log.module("Takes", string.format("✅ Copied %d take FX from source project", src_fx_count))
          return true
        end
      end
    end
  end

  -- Fallback: recreate by name and restore preset/params/offline (works for most built‑ins)
  if not fx_data or not fx_data.fx then return false end

  local total = fx_data.count or 0
  for fx_index = 0, total - 1 do
    local fx_info = fx_data.fx[fx_index]
    if fx_info and fx_info.name and fx_info.name ~= "" then
      local new_idx = reaper.TakeFX_AddByName(take, fx_info.name, 1)
      if new_idx >= 0 then
        if fx_info.preset and reaper.TakeFX_SetPreset then
          reaper.TakeFX_SetPreset(take, new_idx, fx_info.preset)
        end
        if fx_info.params then
          for _, pv in ipairs(fx_info.params) do
            reaper.TakeFX_SetParam(take, new_idx, pv.index, pv.value)
          end
        end
        if fx_info.enabled ~= nil then
          reaper.TakeFX_SetEnabled(take, new_idx, fx_info.enabled)
        end
        if fx_info.offline ~= nil and reaper.TakeFX_SetOffline then
          reaper.TakeFX_SetOffline(take, new_idx, fx_info.offline)
        end
      end
    end
  end
  Log.module("Takes", string.format("✅ Recreated %d take FX from stored data", total))
  return true
end

function Takes.write_take_envelopes(take, env_data, opts)
  if not env_data or not env_data.envelopes then return false end

  -- Helper to find a take envelope by name
  local function find_take_envelope_by_name(tk, wanted)
    local n = reaper.CountTakeEnvelopes(tk) or 0
    for i = 0, n - 1 do
      local e = reaper.GetTakeEnvelope(tk, i)
      if e then
        local _, nm = reaper.GetEnvelopeName(e)
        if (nm or "") == (wanted or "") then
          return e
        end
      end
    end
    return nil
  end

  -- Normalize envelope names so we can match across REAPER variants
  local function norm_name(n)
    n = (n or ""):lower()
    n = n:gsub("^take%s+", "")          -- strip leading "Take "
    n = n:gsub("%s*%b()", "")           -- drop parenthetical qualifiers
    n = n:gsub("%s+", "")               -- remove spaces
    n = n:gsub("playrate", "rate")       -- unify naming
    return n
  end

  -- Map normalized names to actions that toggle the take envelope
  local ENVELOPE_TOGGLE_ACTION = {
    volume = 40693,  -- Item properties: Toggle take volume envelope
    pan    = 40694,  -- Item properties: Toggle take pan envelope
    mute   = 40695,  -- Item properties: Toggle take mute envelope
    pitch  = 40696,  -- Item properties: Toggle take pitch envelope
    rate   = 40697,  -- Item properties: Toggle take playrate envelope
  }

  local function ensure_take_envelope(tk, wanted_name)
    -- Apply remapped track index if available for correct lane/take context
    if opts and opts.track_mapping and opts.original_track_index then
      local mapped = opts.track_mapping[opts.original_track_index]
      if mapped then
        local item = reaper.GetMediaItemTake_Item(tk)
        if item then
          local track = reaper.GetMediaItem_Track(item)
          local parent_track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
          if parent_track_idx ~= mapped then
            return false -- skip writing to wrong track index
          end
        end
      end
    end
    -- Try existing first
    local existing = find_take_envelope_by_name(tk, wanted_name)
    if existing then return existing end

    -- Attempt creation via action toggle using normalized key
    local key = norm_name(wanted_name)
    local cmd = ENVELOPE_TOGGLE_ACTION[key]
    if cmd then
      -- Select owning item and set this take active so the action applies to it
      local item = reaper.GetMediaItemTake_Item(tk)
      if item then
        local was_selected = reaper.IsMediaItemSelected(item)
        reaper.SetMediaItemSelected(item, true)
        reaper.SetActiveTake(tk)
        reaper.Main_OnCommand(cmd, 0)
        if not was_selected then
          reaper.SetMediaItemSelected(item, false)
        end
      end
      -- Try to fetch again after toggle
      local created = find_take_envelope_by_name(tk, wanted_name)
      if created then return created end
      -- As a fallback, try to match by normalized name among all take envelopes
      local n = reaper.CountTakeEnvelopes(tk) or 0
      for i = 0, n - 1 do
        local e = reaper.GetTakeEnvelope(tk, i)
        if e then
          local _, nm = reaper.GetEnvelopeName(e)
          if norm_name(nm) == key then return e end
        end
      end
    end
    return nil
  end

  for _, env in ipairs(env_data.envelopes) do
    local dest_env = ensure_take_envelope(take, env.name)
    if dest_env then
      -- Clear existing underlying envelope points
      local existing = reaper.CountEnvelopePointsEx(dest_env, -1) or 0
      if existing > 0 then
        -- Delete from last to first
        for i = existing - 1, 0, -1 do
          reaper.DeleteEnvelopePointEx(dest_env, -1, i)
        end
      end

      -- Insert new points
      for _, pt in ipairs(env.points or {}) do
        reaper.InsertEnvelopePointEx(
          dest_env,     -- envelope
          -1,           -- autoitem_idx (underlying)
          pt.time or 0,
          pt.value or 0,
          pt.shape or 0,
          pt.tension or 0,
          pt.selected and true or false,
          true          -- noSortIn optional: keep order; we'll sort after
        )
      end

      -- Sort points after insertion
      reaper.Envelope_SortPointsEx(dest_env, -1)
    else
      -- If the destination take doesn't expose this envelope by name,
      -- we skip gracefully (creation of new take envelope types is not forced here).
    end
  end

  return true
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function Takes.get_takes_for_item(data, track_index, item_index)
  if not data or not data.takes then return {} end
  
  local item_takes = {}
  for _, take in ipairs(data.takes) do
    if take.track_index == track_index and take.item_index == item_index then
      table.insert(item_takes, take)
    end
  end
  return item_takes
end

function Takes.get_active_take_for_item(data, track_index, item_index)
  local item_takes = Takes.get_takes_for_item(data, track_index, item_index)
  
  for _, take in ipairs(item_takes) do
    if take.is_active then
      return take
    end
  end
  return nil
end

function Takes.filter_by_type(data, take_type)
  if not data or not data.takes then return {} end
  
  local filtered_takes = {}
  for _, take in ipairs(data.takes) do
    if take.type == take_type then
      table.insert(filtered_takes, take)
    end
  end
  return filtered_takes
end

function Takes.get_statistics(data)
  if not data or not data.takes then return {} end
  
  local stats = {
    total_takes = #data.takes,
    midi_takes = 0,
    audio_takes = 0,
    empty_takes = 0,
    active_takes = 0,
    total_fx = 0,
    total_midi_notes = 0
  }
  
  for _, take in ipairs(data.takes) do
    if take.is_active then
      stats.active_takes = stats.active_takes + 1
    end
    
    if take.type == "MIDI" then
      stats.midi_takes = stats.midi_takes + 1
      if take.midi_data and take.midi_data.note_count then
        stats.total_midi_notes = stats.total_midi_notes + take.midi_data.note_count
      end
    elseif take.type == "AUDIO" then
      stats.audio_takes = stats.audio_takes + 1
    else
      stats.empty_takes = stats.empty_takes + 1
    end
    
    if take.fx_data and take.fx_data.count then
      stats.total_fx = stats.total_fx + take.fx_data.count
    end
  end
  
  return stats
end

function Takes.parse_take_fx(take)
  local fx_data = {
    count = 0,
    fx = {}
  }

  local fx_count = reaper.TakeFX_GetCount(take)
  Log.module("Takes", string.format("🎛 Parsing %d take FX", fx_count or 0))
  fx_data.count = fx_count

  for fx_idx = 0, fx_count - 1 do
    local fx_info = {}

    -- Name
    local _, fx_name = reaper.TakeFX_GetFXName(take, fx_idx, "")
    fx_info.name = fx_name

    -- Enabled / Offline
    fx_info.enabled = reaper.TakeFX_GetEnabled(take, fx_idx)
    if reaper.TakeFX_GetOffline then
      fx_info.offline = reaper.TakeFX_GetOffline(take, fx_idx)
    end

    -- Preset (if available)
    if reaper.TakeFX_GetPreset then
      local ok, preset_name = reaper.TakeFX_GetPreset(take, fx_idx, "")
      if ok then fx_info.preset = preset_name end
    end

    -- Parameters
    fx_info.params = {}
    if reaper.TakeFX_GetNumParams and reaper.TakeFX_GetParam then
      local num_params = reaper.TakeFX_GetNumParams(take, fx_idx) or 0
      fx_info.num_params = num_params
      for p = 0, num_params - 1 do
        -- TakeFX_GetParam returns (value, min, max); we want the value
        local val = select(1, reaper.TakeFX_GetParam(take, fx_idx, p))
        table.insert(fx_info.params, { index = p, value = val or 0.0 })
      end
    end

    fx_data.fx[fx_idx] = fx_info
  end

  Log.module("Takes", string.format("✅ Parsed %d take FX", fx_data.count or 0))
  return fx_data
end

return Takes