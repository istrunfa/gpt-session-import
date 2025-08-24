--[[
@description REAPER Project Engine - Tracks Module (PATCHED)
@version 1.1
@about Handles tracks and ALL fixed lane logic including playing states
--]]



local Tracks = {}
local Log = require("log")

-- ============================================================================
-- USER CONFIG: WRITING TOGGLES (parsing is always ON)
-- Set to true/false to control what this module WRITES into destination projects.
-- ============================================================================
local TRACKS_WRITE = {
  clear_existing_tracks   = true,  -- delete all tracks in destination before writing new ones
  name                    = true,  -- write track names
  properties              = true,  -- write track properties (volume, pan, mute, etc.)
  envelopes               = true,  -- write track envelopes (incl. automation items)
  lane_configuration      = true,  -- apply fixed-lane structure + names + playing states
  fx                      = true,  -- write track FX chains
  fx_clear_existing       = true,  -- clear destination track FX chain before writing
}


-- ============================================================================
-- FIXED LANE HELPER FUNCTIONS (CORRECTED API CALLS)
-- ============================================================================

local function get_lane_name(track, lane_idx)
  -- Validate track parameter
  if not track then
    return nil
  end
  
  -- ✅ CORRECTED API CALL
  local retval, name = reaper.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. lane_idx, "", false)
  return retval and name or nil
end

local function set_lane_name(track, lane_idx, name)
  -- Validate track parameter
  if not track then
    return false
  end
  
  -- ✅ CORRECTED API CALL  
  return reaper.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. lane_idx, name or "", true)
end

local function is_fixed_lane_track(track)
  -- Validate track parameter
  if not track then
    return false
  end
  
  -- ✅ CORRECTED - Check if P_LANENAME:0 returns true (exists)
  local retval, _ = reaper.GetSetMediaTrackInfo_String(track, "P_LANENAME:0", "", false)
  return retval
end

local function detect_lane_count(track)
  -- Validate track parameter
  if not track then
    return 0
  end
  
  if not is_fixed_lane_track(track) then 
    return 0 
  end
  
  local count = 0
  for i = 0, 31 do
    local retval, _ = reaper.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. i, "", false)
    if retval then
      count = i + 1
    else
      break
    end
  end
  return count
end


-- ============================================================================
-- TRACK FX (PARSE/WRITE)
-- ============================================================================

function Tracks.parse_track_fx(track)
  local fx_data = { count = 0, fx = {} }
  if not track then return fx_data end

  local fx_count = reaper.TrackFX_GetCount(track)
  fx_data.count = fx_count

  for fx_idx = 0, fx_count - 1 do
    local fx_info = {}

    -- FX name
    local _, fx_name = reaper.TrackFX_GetFXName(track, fx_idx, "")
    fx_info.name = fx_name

    -- Enabled / Offline
    fx_info.enabled = reaper.TrackFX_GetEnabled(track, fx_idx)
    if reaper.TrackFX_GetOffline then
      fx_info.offline = reaper.TrackFX_GetOffline(track, fx_idx)
    end

    -- Preset (if available)
    if reaper.TrackFX_GetPreset then
      local ok, preset_name = reaper.TrackFX_GetPreset(track, fx_idx, "")
      if ok then fx_info.preset = preset_name end
    end

    -- Parameters
    fx_info.params = {}
    if reaper.TrackFX_GetNumParams and reaper.TrackFX_GetParam then
      local num_params = reaper.TrackFX_GetNumParams(track, fx_idx) or 0
      fx_info.num_params = num_params
      for p = 0, num_params - 1 do
        -- TrackFX_GetParam returns (value, min, max); we want the value
        local val = select(1, reaper.TrackFX_GetParam(track, fx_idx, p))
        table.insert(fx_info.params, { index = p, value = val or 0.0 })
      end
    end

    fx_data.fx[fx_idx] = fx_info
  end

  return fx_data
end

function Tracks.write_track_fx(dest_proj, dest_track, track_idx, fx_data, opts)
  if not dest_track or not fx_data or not fx_data.fx then return false end

  -- Optionally clear existing FX on destination
  if TRACKS_WRITE.fx_clear_existing then
    for i = reaper.TrackFX_GetCount(dest_track) - 1, 0, -1 do
      reaper.TrackFX_Delete(dest_track, i)
    end
  end

  -- Prefer exact cloning from source project if provided (best for 3rd-party FX)
  local src_proj = opts and opts.source_proj or nil
  if src_proj then
    local src_track = reaper.GetTrack(src_proj, track_idx)
    if src_track then
      local src_fx_count = reaper.TrackFX_GetCount(src_track)
      for fx_idx = 0, src_fx_count - 1 do
        local dest_pos = reaper.TrackFX_GetCount(dest_track) -- append
        reaper.TrackFX_CopyToTrack(src_track, fx_idx, dest_track, dest_pos, false) -- copy (not move)
      end
      return true
    end
  end

  -- Fallback: recreate by name then restore preset/params/offline
  local total = fx_data.count or 0
  for fx_index = 0, total - 1 do
    local fx_info = fx_data.fx[fx_index]
    if fx_info and fx_info.name and fx_info.name ~= "" then
      local new_idx = reaper.TrackFX_AddByName(dest_track, fx_info.name, 1) -- instantiate & append
      if new_idx >= 0 then
        -- Preset first
        if fx_info.preset and reaper.TrackFX_SetPreset then
          reaper.TrackFX_SetPreset(dest_track, new_idx, fx_info.preset)
        end
        -- Params
        if fx_info.params then
          for _, pv in ipairs(fx_info.params) do
            reaper.TrackFX_SetParam(dest_track, new_idx, pv.index, pv.value)
          end
        end
        -- Enabled / Offline
        if fx_info.enabled ~= nil then
          reaper.TrackFX_SetEnabled(dest_track, new_idx, fx_info.enabled)
        end
        if fx_info.offline ~= nil and reaper.TrackFX_SetOffline then
          reaper.TrackFX_SetOffline(dest_track, new_idx, fx_info.offline)
        end
      end
    end
  end

  return true
end

-- ============================================================================
-- TRACK ENVELOPES (PARSE/WRITE)
-- ============================================================================

function Tracks.parse_track_envelopes(track)
  local data = { envelopes = {}, count = 0 }
  if not track then return data end

  local env_count = reaper.CountTrackEnvelopes(track) or 0
  data.count = env_count

  for envidx = 0, env_count - 1 do
    local env = reaper.GetTrackEnvelope(track, envidx)
    if env then
      local _, env_name = reaper.GetEnvelopeName(env)
      local points = {}
      local pt_count = reaper.CountEnvelopePointsEx(env, -1) or 0
      for ptidx = 0, pt_count - 1 do
        local ok, time, value, shape, tension, selected = reaper.GetEnvelopePointEx(env, -1, ptidx)
        if ok then
          points[#points+1] = {
            time = time,
            value = value,
            shape = shape,
            tension = tension,
            selected = (selected == true or selected == 1)
          }
        end
      end
      -- Capture automation items for this envelope
      local ai_list = {}
      local ai_count = reaper.CountAutomationItems(env) or 0
      for ai = 0, ai_count - 1 do
        local ai_data = {}
        -- Basic AI properties
        ai_data.position   = reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
        ai_data.length     = reaper.GetSetAutomationItemInfo(env, ai, "D_LENGTH", 0, false)
        ai_data.startoffs  = reaper.GetSetAutomationItemInfo(env, ai, "D_STARTOFFS", 0, false)
        ai_data.baseline   = reaper.GetSetAutomationItemInfo(env, ai, "D_BASELINE", 0, false)
        ai_data.amplitude  = reaper.GetSetAutomationItemInfo(env, ai, "D_AMPLITUDE", 0, false)
        ai_data.loop_src   = reaper.GetSetAutomationItemInfo(env, ai, "D_LOOPSRC", 0, false)
        ai_data.pool_id    = reaper.GetSetAutomationItemInfo(env, ai, "D_POOL_ID", 0, false)

        -- Points within this automation item
        local ai_points = {}
        local ai_pt_cnt = reaper.CountEnvelopePointsEx(env, ai) or 0
        for p = 0, ai_pt_cnt - 1 do
          local ok, t, v, sh, ten, sel = reaper.GetEnvelopePointEx(env, ai, p)
          if ok then
            ai_points[#ai_points+1] = {
              time = t,
              value = v,
              shape = sh,
              tension = ten,
              selected = (sel == true or sel == 1)
            }
          end
        end
        ai_data.points = ai_points
        ai_list[#ai_list+1] = ai_data
      end
      data.envelopes[#data.envelopes+1] = {
        name = env_name or "",
        points = points,
        automation_items = ai_list
      }
    end
  end

  return data
end

local function find_track_envelope_by_name(track, wanted)
  if not track or not wanted then return nil end
  -- Prefer a direct name lookup if available
  if reaper.GetTrackEnvelopeByName then
    local env = reaper.GetTrackEnvelopeByName(track, wanted)
    if env then return env end
  end
  -- Fallback: iterate and match by GetEnvelopeName()
  local env_count = reaper.CountTrackEnvelopes(track) or 0
  for i = 0, env_count - 1 do
    local e = reaper.GetTrackEnvelope(track, i)
    if e then
      local _, nm = reaper.GetEnvelopeName(e)
      if (nm or "") == (wanted or "") then
        return e
      end
    end
  end
  return nil
end

-- Envelope name normalization and auto-creation helpers
local function _norm_track_env_name(n)
  n = (n or ""):lower()
  n = n:gsub("track%s+", "")
  n = n:gsub("%s*%b()", function(s)
    return s:find("pre%-fx") and " (pre-fx)" or ""
  end)
  n = n:gsub("%s+", " ")
  n = n:gsub("^%s+", ""):gsub("%s+$", "")
  return n
end

-- Action IDs for creating/showing standard track envelopes
-- (Volume/Pan + their Pre-FX variants)
local _TRACK_ENV_ACTION = {
  ["volume"]        = 40406, -- Track: Toggle track volume envelope visible
  ["volume (pre-fx)"] = 40408, -- Track: Toggle track pre-FX volume envelope visible
  ["pan"]           = 40407, -- Track: Toggle track pan envelope visible
  ["pan (pre-fx)"]    = 40409, -- Track: Toggle track pre-FX pan envelope visible
}

local function _ensure_track_envelope(track, wanted_name)
  -- Try exact by name first
  local env = find_track_envelope_by_name(track, wanted_name)
  if env then return env end

  -- Try normalized mapping via actions
  local key = _norm_track_env_name(wanted_name)
  local cmd = _TRACK_ENV_ACTION[key]
  if cmd then
    -- Temporarily select only this track so the action applies here
    local was_sel = reaper.IsTrackSelected(track)
    reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
    reaper.SetTrackSelected(track, true)
    reaper.Main_OnCommand(cmd, 0)   -- Toggle envelope visible (creates if missing)
    -- Restore selection state
    reaper.SetTrackSelected(track, was_sel)

    -- Try again, first by exact name, then by normalized match
    env = find_track_envelope_by_name(track, wanted_name)
    if env then return env end

    local env_count = reaper.CountTrackEnvelopes(track) or 0
    for i = 0, env_count - 1 do
      local e = reaper.GetTrackEnvelope(track, i)
      if e then
        local _, nm = reaper.GetEnvelopeName(e)
        if _norm_track_env_name(nm) == key then
          return e
        end
      end
    end
  end

  return nil
end

function Tracks.write_track_envelopes(track, env_data, opts)
  if not track or not env_data or not env_data.envelopes then return false end

  local track_mapping = opts and opts.track_mapping or {}
  local expected_idx = opts and opts.original_track_index and track_mapping[opts.original_track_index]
  if expected_idx ~= nil then
    local actual_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    if actual_idx ~= expected_idx then
      return false
    end
  end

  for _, env in ipairs(env_data.envelopes) do
    local dest_env = _ensure_track_envelope(track, env.name)
    if dest_env then
      -- Remove existing automation items on this envelope
      local existing_ai = reaper.CountAutomationItems(dest_env) or 0
      for ai = existing_ai - 1, 0, -1 do
        reaper.DeleteAutomationItem(dest_env, ai)
      end
      -- Clear existing underlying points
      local existing = reaper.CountEnvelopePointsEx(dest_env, -1) or 0
      for i = existing - 1, 0, -1 do
        reaper.DeleteEnvelopePointEx(dest_env, -1, i)
      end
      -- Insert new points
      for _, pt in ipairs(env.points or {}) do
        reaper.InsertEnvelopePointEx(
          dest_env,
          -1,                 -- underlying envelope
          pt.time or 0,
          pt.value or 0,
          pt.shape or 0,
          pt.tension or 0,
          pt.selected and true or false,
          true                -- noSortIn (sort later)
        )
      end
      reaper.Envelope_SortPointsEx(dest_env, -1)

      -- Recreate automation items (if any)
      if env.automation_items then
        for _, ai in ipairs(env.automation_items) do
          -- Insert a new (non-pooled) AI; use pool_id if you prefer pooling semantics
          local new_idx = reaper.InsertAutomationItem(dest_env, -1, ai.position or 0, ai.length or 0)
          if new_idx >= 0 then
            -- Restore AI properties
            if ai.startoffs ~= nil then reaper.GetSetAutomationItemInfo(dest_env, new_idx, "D_STARTOFFS", ai.startoffs, true) end
            if ai.baseline  ~= nil then reaper.GetSetAutomationItemInfo(dest_env, new_idx, "D_BASELINE",  ai.baseline,  true) end
            if ai.amplitude ~= nil then reaper.GetSetAutomationItemInfo(dest_env, new_idx, "D_AMPLITUDE", ai.amplitude, true) end
            if ai.loop_src  ~= nil then reaper.GetSetAutomationItemInfo(dest_env, new_idx, "D_LOOPSRC",  ai.loop_src,  true) end
            -- If you want to retain pooling, uncomment below to set pool id if supported in your REAPER version
            -- if ai.pool_id   ~= nil then reaper.GetSetAutomationItemInfo(dest_env, new_idx, "D_POOL_ID",  ai.pool_id,  true) end

            -- Insert points into this AI
            for _, pt in ipairs(ai.points or {}) do
              reaper.InsertEnvelopePointEx(
                dest_env,
                new_idx,
                pt.time or 0,
                pt.value or 0,
                pt.shape or 0,
                pt.tension or 0,
                pt.selected and true or false,
                true
              )
            end
            -- Sort AI points
            reaper.Envelope_SortPointsEx(dest_env, new_idx)
          end
        end
      end
    else
      -- If a matching envelope is not present on the destination track,
      -- we skip gracefully.
    end
  end

  return true
end

-- ============================================================================
-- LANE PLAYING STATE ANALYSIS
-- ============================================================================

local function analyze_active_lanes_from_items(proj, track_idx)
  -- Analyze which lanes should be active based on items in source project
  local track = reaper.GetTrack(proj, track_idx)
  if not track then return {} end
  
  local active_lanes = {}
  local item_count = reaper.CountTrackMediaItems(track)
  
  for item_idx = 0, item_count - 1 do
    local item = reaper.GetTrackMediaItem(track, item_idx)
    local lane_plays = reaper.GetMediaItemInfo_Value(item, "C_LANEPLAYS")
    local fixed_lane = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE")
    
    -- If item was playing (lane_plays == 1 or 2), mark this lane as active
    if lane_plays == 1 or lane_plays == 2 then
      active_lanes[fixed_lane] = true
    end
  end
  
  return active_lanes
end

-- ============================================================================
-- MAIN TRACK FUNCTIONS
-- ============================================================================

function Tracks.parse(proj)
  local data = {}
  
  -- Track count → CountTracks(proj)
  local track_count = reaper.CountTracks(proj)
  data.count = track_count
  data.tracks = {}
  
  
  
  for track_idx = 0, track_count - 1 do
    -- Track handle by index → GetTrack(proj, trackidx)
    local track = reaper.GetTrack(proj, track_idx)
    local track_data = {
      index = track_idx,
      properties = {},
      lane_info = {}
    }
    
    -- Name → GetSetMediaTrackInfo_String(tr, "P_NAME", buf, false)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    track_data.name = name

    -- Parse track FX (name/preset/params/enabled/offline)
    track_data.fx = Tracks.parse_track_fx(track)
    
    -- Parse track envelopes (underlying)
    track_data.envelopes = Tracks.parse_track_envelopes(track)
    
    -- Parse lane information FIRST (before properties)
    local is_fixed_lane = is_fixed_lane_track(track)
    local lane_count = detect_lane_count(track)
    
    track_data.lane_info = {
      is_fixed_lane = is_fixed_lane,
      lane_count = lane_count,
      lane_names = {},
      active_lanes = {}  -- NEW: Store which lanes should be active
    }
    
    
    if is_fixed_lane then
      -- Get lane names
      for lane_idx = 0, lane_count - 1 do
        local lane_name = get_lane_name(track, lane_idx)
        track_data.lane_info.lane_names[lane_idx] = lane_name or ""
      end
      
      -- NEW: Analyze which lanes should be active
      local active_lanes = analyze_active_lanes_from_items(proj, track_idx)
      track_data.lane_info.active_lanes = active_lanes
      
    end
    
    -- All track properties via GetMediaTrackInfo_Value
    local properties = {
      "I_CUSTOMCOLOR",     -- Custom color
      "I_NCHAN",           -- Channel count
      "D_VOL",             -- Volume
      "D_PAN",             -- Pan
      "D_WIDTH",           -- Width
      "D_DUALPANL",        -- Dual‑pan L
      "D_DUALPANR",        -- Dual‑pan R
      "I_PANMODE",         -- Pan mode: 0=classic 3.x, 3=new balance, 5=stereo pan, 6=dual pan
      "D_PANLAW",          -- Pan law
      "I_PANLAW_FLAGS",    -- Pan law flags
      "I_FOLDERDEPTH",     -- Folder depth
      "I_FOLDERCOMPACT",   -- Folder compact
      "B_MUTE",            -- Mute
      "I_SOLO",            -- Solo
      "I_RECARM",          -- Rec‑arm
      "I_RECINPUT",        -- Rec input
      "B_PHASE",           -- Phase invert
      "I_PERFFLAGS",       -- Performance flags
      "B_HEIGHTLOCK"       -- Height lock
    }
    
    for _, prop in ipairs(properties) do
      track_data.properties[prop] = reaper.GetMediaTrackInfo_Value(track, prop)
    end
    
    data.tracks[track_idx] = track_data
  end
  
  
  
  return data
end

function Tracks.write(dest_proj, data, opts)
  if not data or not data.tracks then return false end

  local CFG = opts and opts.tracks_cfg or TRACKS_WRITE

  -- Clear existing tracks (optional)
  if CFG.clear_existing_tracks then
    local existing_count = reaper.CountTracks(dest_proj)
    for i = existing_count - 1, 0, -1 do
      local track = reaper.GetTrack(dest_proj, i)
      if track then
        reaper.DeleteTrack(track)
      end
    end
  end

  -- Create tracks in order
  for track_idx = 0, (data.count or 0) - 1 do
    local track_data = data.tracks[track_idx]
    if track_data then

      -- Insert track at specific index
      reaper.InsertTrackAtIndex(track_idx, false)
      local dest_track = reaper.GetTrack(dest_proj, track_idx)

      -- Validate track creation
      if not dest_track then
        goto continue
      end

      -- Set name
      if CFG.name then
        reaper.GetSetMediaTrackInfo_String(dest_track, "P_NAME", track_data.name or "", true)
      end

      -- Set properties
      if CFG.properties and track_data.properties then
        for prop, value in pairs(track_data.properties) do
          reaper.SetMediaTrackInfo_Value(dest_track, prop, value)
        end
      end

      -- Write track FX before envelopes (so any FX parameter envelopes can bind)
      if CFG.fx and track_data.fx then
        Tracks.write_track_fx(dest_proj, dest_track, track_idx, track_data.fx, opts)
      end

      -- Write track envelopes for this track
      if CFG.envelopes and track_data.envelopes then
        Tracks.write_track_envelopes(dest_track, track_data.envelopes, {
          source_proj = opts and opts.source_proj,
          track_mapping = opts and opts.track_mapping,
          original_track_index = track_idx
        })
      end
    end

    ::continue::
  end

  -- PHASE 2: Apply ALL lane configurations (structure + names + playing states)
  for track_idx = 0, (data.count or 0) - 1 do
    local track_data = data.tracks[track_idx]
    if track_data and track_data.lane_info then
      local dest_track = reaper.GetTrack(dest_proj, track_idx)
      if dest_track then
        -- Apply complete lane configuration
        if CFG.lane_configuration then
          Tracks.apply_complete_lane_configuration(dest_track, track_data.lane_info)
        end
      end
    end
  end

  -- FINAL VERIFICATION: Check all tracks after everything is done
  local final_track_count = reaper.CountTracks(dest_proj)
  for i = 0, final_track_count - 1 do
    local track = reaper.GetTrack(dest_proj, i)
    if track then
      local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
      local is_fixed = is_fixed_lane_track(track)
      local lane_count = detect_lane_count(track)
    end
  end

  -- Clear selection
  reaper.Main_OnCommand(40297, 0)

  return true
end

function Tracks.apply_complete_lane_configuration(track, lane_info)
  -- Validate track parameter
  if not track then
    return false
  end
  
  if not lane_info.is_fixed_lane then
    return true
  end
  
  
  local current_lanes = detect_lane_count(track)
  
  -- Step 1: Convert to fixed-lane mode if needed
  if current_lanes == 0 then
    reaper.Main_OnCommand(40297, 0)         -- Clear selection
    reaper.SetTrackSelected(track, true)    -- Select ONLY this track
    reaper.Main_OnCommand(42661, 0)         -- Set fixed lanes
    -- Verify conversion
    current_lanes = detect_lane_count(track)
  end
  
  -- Step 2: Ensure we have enough lanes
  local target_lanes = lane_info.lane_count or 0
  local lanes_needed = target_lanes - current_lanes
  
  if lanes_needed > 0 then
    for i = 1, lanes_needed do
      reaper.SetTrackSelected(track, true)
      reaper.Main_OnCommand(42647, 0)       -- Add empty lane
    end
  end
  
  -- Step 3: Set lane names
  if lane_info.lane_names then
    for lane_idx, name in pairs(lane_info.lane_names) do
      if type(lane_idx) == "number" and name ~= "" then
        local success = set_lane_name(track, lane_idx, name)
      end
    end
  end
  
  -- Step 4: Prepare lane playing states (items will be handled later)
  if lane_info.active_lanes then
    local active_count = 0
    for lane, _ in pairs(lane_info.active_lanes) do
      active_count = active_count + 1
    end
  end
  
  -- Final verification
  local final_lanes = detect_lane_count(track)
  local is_fixed_final = is_fixed_lane_track(track)
  return true
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- ============================================================================
-- LANE PLAYING STATES APPLICATION (NEW FUNCTION)
-- ============================================================================

function Tracks.apply_lane_playing_states(dest_proj, tracks_data)
  -- Apply lane playing states to all items after they've been created
  local track_mapping = tracks_data.track_mapping or {}

  for track_idx, track_data in pairs(tracks_data.tracks or {}) do
    if track_data.lane_info and track_data.lane_info.is_fixed_lane then
      local mapped_idx = track_mapping[track_idx] or track_idx
      local dest_track = reaper.GetTrack(dest_proj, mapped_idx)
      if dest_track then
        local active_lanes = track_data.lane_info.active_lanes or {}

        -- Get all items on this track
        local item_count = reaper.CountTrackMediaItems(dest_track)

        for item_idx = 0, item_count - 1 do
          local item = reaper.GetTrackMediaItem(dest_track, item_idx)
          local lane = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE")

          -- Set lane playing state based on active lanes analysis
          if active_lanes[lane] then
            -- This lane should be active
            reaper.SetMediaItemInfo_Value(item, "C_LANEPLAYS", 1)  -- plays exclusively
          else
            -- This lane should not play
            reaper.SetMediaItemInfo_Value(item, "C_LANEPLAYS", 0)  -- does not play
          end
        end
      end
    end
  end

  return true
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Export helper functions for use by other modules
Tracks.is_fixed_lane_track = is_fixed_lane_track
Tracks.detect_lane_count = detect_lane_count
Tracks.get_lane_name = get_lane_name
Tracks.set_lane_name = set_lane_name
Tracks.analyze_active_lanes_from_items = analyze_active_lanes_from_items

function Tracks.get_track_by_name(data, name)
  if not data or not data.tracks then return nil end
  
  for _, track in pairs(data.tracks) do
    if track.name == name then
      return track
    end
  end
  return nil
end

function Tracks.filter_fixed_lane_tracks(data)
  if not data or not data.tracks then return {} end
  
  local fixed_lane_tracks = {}
  for _, track in pairs(data.tracks) do
    if track.lane_info and track.lane_info.is_fixed_lane then
      table.insert(fixed_lane_tracks, track)
    end
  end
  return fixed_lane_tracks
end

-- NEW: Get active lanes for a track
function Tracks.get_active_lanes_for_track(data, track_idx)
  if not data or not data.tracks then return {} end
  
  local track_data = data.tracks[track_idx]
  if track_data and track_data.lane_info then
    return track_data.lane_info.active_lanes or {}
  end
  
  return {}
end

function Tracks.decode_pan_mode(pan_mode)
  local pan_modes = {
    [0] = "Classic 3.x",
    [3] = "New Balance", 
    [5] = "Stereo Pan",
    [6] = "Dual Pan"
  }
  return pan_modes[pan_mode] or ("Unknown (" .. tostring(pan_mode) .. ")")
end

function Tracks.get_track_statistics(data)
  if not data or not data.tracks then return {} end
  
  local stats = {
    total_tracks = data.count or 0,
    fixed_lane_tracks = 0,
    folder_tracks = 0,
    muted_tracks = 0,
    soloed_tracks = 0,
    rec_armed_tracks = 0,
    pan_modes = {},
    total_active_lanes = 0
  }
  
  for _, track in pairs(data.tracks) do
    -- Count fixed lane tracks
    if track.lane_info and track.lane_info.is_fixed_lane then
      stats.fixed_lane_tracks = stats.fixed_lane_tracks + 1
      
      -- Count active lanes
      if track.lane_info.active_lanes then
        for _ in pairs(track.lane_info.active_lanes) do
          stats.total_active_lanes = stats.total_active_lanes + 1
        end
      end
    end
    
    -- Count folder tracks
    if track.properties and track.properties["I_FOLDERDEPTH"] then
      local depth = track.properties["I_FOLDERDEPTH"]
      if depth > 0 then
        stats.folder_tracks = stats.folder_tracks + 1
      end
    end
    
    -- Count muted tracks
    if track.properties and track.properties["B_MUTE"] and track.properties["B_MUTE"] > 0 then
      stats.muted_tracks = stats.muted_tracks + 1
    end
    
    -- Count soloed tracks  
    if track.properties and track.properties["I_SOLO"] and track.properties["I_SOLO"] > 0 then
      stats.soloed_tracks = stats.soloed_tracks + 1
    end
    
    -- Count rec-armed tracks
    if track.properties and track.properties["I_RECARM"] and track.properties["I_RECARM"] > 0 then
      stats.rec_armed_tracks = stats.rec_armed_tracks + 1
    end
    
    -- Count pan modes
    if track.properties and track.properties["I_PANMODE"] then
      local pan_mode = track.properties["I_PANMODE"]
      local mode_name = Tracks.decode_pan_mode(pan_mode)
      stats.pan_modes[mode_name] = (stats.pan_modes[mode_name] or 0) + 1
    end
  end
  
  return stats
end


-- ============================================================================
-- WRITE WITH MATCH PLAN (merge into existing or create new)
-- ============================================================================
function Tracks.write_with_match_plan(dest_proj, tracks_data, plan, opts, tracks_cfg)
  if not dest_proj or not tracks_data or not tracks_data.tracks or not plan then return false end

  local opts_cfg = opts and opts.tracks_cfg or {}
  local CFG = setmetatable({}, { __index = function(_, k)
    if opts_cfg[k] ~= nil then return opts_cfg[k] end
    if tracks_cfg and tracks_cfg[k] ~= nil then return tracks_cfg[k] end
    return TRACKS_WRITE[k]
  end })

  Log.module("Tracks", "write_with_match_plan | clear_existing_tracks: " .. tostring(CFG.clear_existing_tracks))

  if CFG.clear_existing_tracks then
    local existing_count = reaper.CountTracks(dest_proj)
    for i = existing_count - 1, 0, -1 do
      local track = reaper.GetTrack(dest_proj, i)
      if track then
        reaper.DeleteTrack(track)
      end
    end
  end

  -- Cache destination track handles before inserting new tracks
  local dest_track_ptrs = {}
  local existing_count = reaper.CountTracks(dest_proj)
  for i = 0, existing_count - 1 do
    dest_track_ptrs[i] = reaper.GetTrack(dest_proj, i)
  end

  -- 1) Merge mapped pairs into existing destination tracks
  for src_idx, dest_idx in pairs(plan.mappings or {}) do
    Log.module("Tracks", string.format("🔁 Merging Track[%d] → Dest[%d]", src_idx, dest_idx))
    local td = tracks_data.tracks[src_idx]
    local dest_track = dest_track_ptrs[dest_idx]
    if td and dest_track then
      -- Name
      if CFG.name and td.name then
        reaper.GetSetMediaTrackInfo_String(dest_track, "P_NAME", td.name or "", true)
      end
      -- Properties
      if CFG.properties and td.properties then
        for prop, value in pairs(td.properties) do
          reaper.SetMediaTrackInfo_Value(dest_track, prop, value)
        end
      end
      -- FX (write before envelopes)
      if CFG.fx and td.fx then
        Tracks.write_track_fx(dest_proj, dest_track, dest_idx, td.fx, opts)
      end
      -- Envelopes
      if CFG.envelopes and td.envelopes then
        Tracks.write_track_envelopes(dest_track, td.envelopes, {
          source_proj = opts and opts.source_proj,
          track_mapping = plan.mappings,
          original_track_index = src_idx
        })
      end
      -- Lane configuration
      if CFG.lane_configuration and td.lane_info then
        Log.module("Tracks", string.format("⚙️ Applying lane config for Dest[%d]", dest_idx))
        Tracks.apply_complete_lane_configuration(dest_track, td.lane_info)
      end
    end
  end

  -- 2) Create new tracks at end for all sources that require creation
  -- (MUST be after merges, to avoid shifting destination indices)
  local insert_base = reaper.CountTracks(dest_proj)
  for idx, src_idx in ipairs(plan.to_create or {}) do
    local td = tracks_data.tracks[src_idx]
    if td then
      local insert_idx = insert_base + (idx - 1)
      Log.module("Tracks", string.format("➕ Creating new track at index %d (from source %d)", insert_idx, src_idx))
      reaper.InsertTrackAtIndex(insert_idx, false)
      local dest_track = reaper.GetTrack(dest_proj, insert_idx)
      if dest_track then
        -- Name
        if CFG.name and td.name then
          reaper.GetSetMediaTrackInfo_String(dest_track, "P_NAME", td.name or "", true)
        end
        -- Properties
        if CFG.properties and td.properties then
          for prop, value in pairs(td.properties) do
            reaper.SetMediaTrackInfo_Value(dest_track, prop, value)
          end
        end
        -- FX (write before envelopes)
        if CFG.fx and td.fx then
          Tracks.write_track_fx(dest_proj, dest_track, insert_idx, td.fx, opts)
        end
        -- Envelopes
        if CFG.envelopes and td.envelopes then
          Tracks.write_track_envelopes(dest_track, td.envelopes, {
            source_proj = opts and opts.source_proj,
            track_mapping = plan.mappings,
            original_track_index = src_idx
          })
        end
        -- Lane configuration
        if CFG.lane_configuration and td.lane_info then
          Log.module("Tracks", string.format("⚙️ Applying lane config for new track at index %d", insert_idx))
          Tracks.apply_complete_lane_configuration(dest_track, td.lane_info)
        end
      end
    end
  end

  -- Attach track mapping to tracks_data for downstream lane state application
  tracks_data.track_mapping = plan.mappings

  return true
end

return Tracks