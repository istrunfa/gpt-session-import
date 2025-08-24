--[[
@description REAPER Project Engine - Match Module
@version 1.0
@about Provides track/take matching between source and destination projects
--]]

local Match = {}

local config = require("config")
local Log = require("log")
local MATCH_CFG   = (config and config.matching) or {}
local MATCH_TRK   = MATCH_CFG.tracks or { exact_name = true, index_fallback = true }
local MATCH_TAKE  = MATCH_CFG.takes  or { exact_name = true, index_fallback = true }

-- ============================================================================
-- TRACK MATCHING
-- ============================================================================

-- Strategy: exact name match, fallback to index, otherwise mark "unmatched"
function Match.match_tracks(src_data, dest_data)
  local matches = {}
  local used_dest_indices = {}

  for src_idx, src_track in pairs(src_data.tracks or {}) do
    local match_idx = nil

    -- Try exact name match (configurable)
    if MATCH_TRK.exact_name and src_track.name and src_track.name ~= "" then
      for dest_idx, dest_track in pairs(dest_data.tracks or {}) do
        if dest_track.name == src_track.name and not used_dest_indices[dest_idx] then
          match_idx = dest_idx
          break
        end
      end
    end

    -- Fallback: same index (configurable)
    if (not match_idx) and MATCH_TRK.index_fallback and dest_data.tracks[src_idx] and not used_dest_indices[src_idx] then
      match_idx = src_idx
    end

    if match_idx then
      matches[src_idx] = match_idx
      used_dest_indices[match_idx] = true
    else
      matches[src_idx] = nil -- no match, new track should be created
    end
  end
  for src_idx, match_idx in pairs(matches) do
    local src_name = src_data.tracks[src_idx] and src_data.tracks[src_idx].name or "(unnamed)"
    if match_idx then
      local dest_name = dest_data.tracks[match_idx] and dest_data.tracks[match_idx].name or "(unnamed)"
      Log.module("Match", string.format("✅ Matched '%s' → '%s'", src_name, dest_name))
    else
      Log.module("Match", string.format("➕ No match for '%s' — marked for creation", src_name))
    end
  end
  return matches
end

-- ============================================================================
-- TAKE MATCHING (per item index)
-- ============================================================================

function Match.match_takes(src_takes, dest_takes)
  local matches = {}
  local used_dest = {}

  for _, src_take in ipairs(src_takes or {}) do
    local matched = nil
    -- Try by name (configurable)
    if MATCH_TAKE.exact_name and src_take.name and src_take.name ~= "" then
      for _, dest_take in ipairs(dest_takes or {}) do
        if dest_take.name == src_take.name and not used_dest[dest_take.take_index] then
          matched = dest_take.take_index
          used_dest[dest_take.take_index] = true
          break
        end
      end
    end
    -- Fallback: same index (configurable)
    if (not matched) and MATCH_TAKE.index_fallback then
      local candidate = src_take.take_index
      if dest_takes[candidate+1] and not used_dest[candidate] then
        matched = candidate
        used_dest[candidate] = true
      end
    end

    matches[src_take.take_index] = matched -- nil means "new take"
  end

  return matches
end

-- ============================================================================
-- BUILD PLAN (mappings + to_create) using current config flags
-- ============================================================================
function Match.build_plan(dest_proj, source_tracks_data, match_cfg)
  -- Allow overriding matching config per-call; default to module config
  local cfg = match_cfg or MATCH_CFG

  -- Build a lightweight dest_data with names only (index -> {name})
  local dest_data = { tracks = {}, count = reaper.CountTracks(dest_proj) or 0 }
  for di = 0, dest_data.count - 1 do
    local tr = reaper.GetTrack(dest_proj, di)
    local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    dest_data.tracks[di] = { name = nm or "" }
  end
  
  
  

  -- Temporarily adopt per-call track matching toggles if provided
  local prev_trk = MATCH_TRK
  if cfg and cfg.tracks then MATCH_TRK = cfg.tracks end

  local matches = Match.match_tracks(source_tracks_data or {tracks = {}, count = 0}, dest_data)

  -- Restore previous matching toggles
  MATCH_TRK = prev_trk

  -- Construct plan
  local plan = { mappings = {}, to_create = {} }

  local src_count = (source_tracks_data and source_tracks_data.count) or 0
  for si = 0, src_count - 1 do
    local m = matches[si]
    if m ~= nil then
      plan.mappings[si] = m
    else
      if (cfg and cfg.fallback_create) ~= false then
        table.insert(plan.to_create, si)
      end
    end
  end

  -- In case source table isn't strictly indexed 0..count-1, include any extras
  if source_tracks_data and source_tracks_data.tracks then
    for si, _ in pairs(source_tracks_data.tracks) do
      if type(si) == "number" and (si < 0 or si >= src_count) then
        local m = matches[si]
        if m ~= nil then
          plan.mappings[si] = m
        else
          if (cfg and cfg.fallback_create) ~= false then
            table.insert(plan.to_create, si)
          end
        end
      end
    end
  end

  -- Assign destination indices for created tracks (after existing ones)
  local offset = dest_data.count
  for i, src_idx in ipairs(plan.to_create) do
    plan.mappings[src_idx] = offset + (i - 1)
  end

  return plan
end

return Match