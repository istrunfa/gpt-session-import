--[[
@description REAPER Modular Project Engine - Main Integrator (PATCHED)
@version 1.1
@about Central orchestrator with improved Tracks/Items coordination
--]]

-- ============================================================================
-- MODULE LOADING
-- ============================================================================

-- Get script path for module loading
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\|/])")
package.path = script_path .. "?.lua;" .. package.path

-- Load all engine modules
local ProjectInfo = dofile(script_path .. "project_info.lua")
local Tempo = dofile(script_path .. "tempo.lua")
local Markers = dofile(script_path .. "markers.lua")
local Tracks = dofile(script_path .. "tracks.lua")
local Items = dofile(script_path .. "items.lua")
local Takes = dofile(script_path .. "takes.lua")
local StretchMarkers = dofile(script_path .. "stretch_markers.lua")
local TakeMarkers = dofile(script_path .. "take_markers.lua")
local Match = dofile(script_path .. "matching.lua")
local Config = require("config")

-- ============================================================================
-- INTEGRATOR ENGINE
-- ============================================================================

local Integrator = {}


function Integrator.parse_project(proj)
  local project_data = {}

  -- Parse all modules in dependency order
  project_data.project_info = ProjectInfo.parse(proj)
  project_data.tempo = Tempo.parse(proj)
  project_data.markers = Markers.parse(proj)
  project_data.tracks = Tracks.parse(proj)
  project_data.items = Items.parse(proj)
  project_data.takes = Takes.parse(proj)
  project_data.stretch_markers = StretchMarkers.parse(proj)
  project_data.take_markers = TakeMarkers.parse(proj)

  -- Generate comprehensive statistics
  project_data.stats = Integrator.generate_statistics(project_data)

  -- Integrator.log_statistics(project_data.stats)
  return project_data
end

function Integrator.write_project(dest_proj, project_data, opts)
  opts = opts or {}

  reaper.Undo_BeginBlock()

  local cfg = Config or {}

  -- Write all modules in dependency order
  ProjectInfo.write(dest_proj, project_data.project_info, opts)
  Tempo.write(dest_proj, project_data.tempo, opts)
  Markers.write(dest_proj, project_data.markers, opts)
  local tracks_plan = nil
  if cfg.matching and cfg.matching.enabled then
    tracks_plan = Match.build_plan(dest_proj, project_data.tracks, cfg.matching)
  end

  if tracks_plan then
    Tracks.write_with_match_plan(dest_proj, project_data.tracks, tracks_plan, opts, cfg.tracks)
  elseif cfg.tracks and cfg.tracks.clear_existing_tracks ~= false then
    Tracks.write(dest_proj, project_data.tracks, opts)
  end

  -- Items must be written with access to track data for proper lane alignment
  local item_mapping = Items.write_with_tracks_data(dest_proj, project_data.items, project_data.tracks, {
    source_proj = opts.source_proj,
    track_mapping = tracks_plan and tracks_plan.mappings or nil,
    clear_existing_items = cfg.items and cfg.items.clear_existing_items,
    create_items = cfg.items and cfg.items.create_items,
    properties = cfg.items and cfg.items.properties,
    notes = cfg.items and cfg.items.notes,
    crossfades = cfg.items and cfg.items.crossfades
  })

  -- Apply lane playing states after items are created
  if type(Tracks.apply_lane_playing_states) == "function" then
    Tracks.apply_lane_playing_states(dest_proj, project_data.tracks)
  end

  Takes.write(dest_proj, project_data.takes, {
    source_proj = opts.source_proj,
    track_mapping = tracks_plan and tracks_plan.mappings or nil,
    item_mapping = item_mapping
  })

  StretchMarkers.write(dest_proj, project_data.stretch_markers, {
    track_mapping = tracks_plan and tracks_plan.mappings or nil,
    item_mapping = item_mapping
  })

  TakeMarkers.write(dest_proj, project_data.take_markers, {
    track_mapping = tracks_plan and tracks_plan.mappings or nil,
    item_mapping = item_mapping
  })

  -- Clear selections and update display
  reaper.Main_OnCommand(40297, 0)  -- Clear selection

  reaper.Undo_EndBlock("Modular Project Engine - Complete Transfer", -1)
  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(false)

  -- Integrator.log_statistics(project_data.stats, "WROTE")
  return true
end

function Integrator.migrate_project(source_proj, dest_proj, opts)
  -- Parse source
  local project_data = Integrator.parse_project(source_proj)

  -- Merge opts and forward source project handle for modules that can leverage it (e.g., FX cloning)
  local wopts = {}
  if type(opts) == "table" then
    for k, v in pairs(opts) do wopts[k] = v end
  end
  wopts.source_proj = source_proj

  local success = Integrator.write_project(dest_proj or 0, project_data, wopts)
  return success, project_data
end

-- ============================================================================
-- UTILITY FUNCTIONS (ENHANCED)
-- ============================================================================

function Integrator.find_project_by_path(path)
  for i = 0, 40 do
    local proj, proj_path = reaper.EnumProjects(i)
    if proj and proj_path == path then
      return proj
    end
  end
  return nil
end

function Integrator.generate_statistics(project_data)
  local stats = {
    tracks = project_data.tracks and project_data.tracks.count or 0,
    fixed_lane_tracks = 0,
    total_active_lanes = 0,
    items = project_data.items and #(project_data.items.items or {}) or 0,
    takes = project_data.takes and #(project_data.takes.takes or {}) or 0,
    midi_takes = 0,
    audio_takes = 0,
    tempo_markers = project_data.tempo and #(project_data.tempo.markers or {}) or 0,
    markers = project_data.markers and #(project_data.markers.markers or {}) or 0,
    stretch_markers = project_data.stretch_markers and #(project_data.stretch_markers.stretch_markers or {}) or 0,
    take_markers = project_data.take_markers and #(project_data.take_markers.take_markers or {}) or 0,
    total_midi_notes = 0,
    fx_count = 0,
    pan_modes = {}
  }
  
  -- Enhanced track statistics with lane info
  if project_data.tracks and project_data.tracks.tracks then
    local track_stats = Tracks.get_track_statistics(project_data.tracks)
    stats.fixed_lane_tracks = track_stats.fixed_lane_tracks or 0
    stats.total_active_lanes = track_stats.total_active_lanes or 0
    stats.pan_modes = track_stats.pan_modes or {}
    stats.muted_tracks = track_stats.muted_tracks or 0
    stats.soloed_tracks = track_stats.soloed_tracks or 0
    stats.rec_armed_tracks = track_stats.rec_armed_tracks or 0
  end
  
  -- Take statistics
  if project_data.takes and project_data.takes.takes then
    local take_stats = Takes.get_statistics(project_data.takes)
    stats.midi_takes = take_stats.midi_takes or 0
    stats.audio_takes = take_stats.audio_takes or 0
    stats.total_midi_notes = take_stats.total_midi_notes or 0
    stats.fx_count = take_stats.fx_count or 0
  end
  
  return stats
end

function Integrator.log_statistics(stats, action)
  -- Logging disabled
end

-- ============================================================================
-- SELECTIVE OPERATION EXAMPLES
-- ============================================================================

function Integrator.copy_template_only(source_proj, dest_proj)
  -- Parse full project
  local project_data = Integrator.parse_project(source_proj)

  -- Clear media content but keep structure
  project_data.items = { items = {} }
  project_data.takes = { takes = {} }
  project_data.stretch_markers = { stretch_markers = {} }
  project_data.take_markers = { take_markers = {} }

  -- Write template
  local success = Integrator.write_project(dest_proj, project_data, { clear_destination = true })
  return success
end

function Integrator.copy_tempo_and_markers_only(source_proj, dest_proj)
  -- Parse only specific modules
  local tempo_data = Tempo.parse(source_proj)
  local marker_data = Markers.parse(source_proj)

  -- Write only these modules
  Tempo.write(dest_proj, tempo_data)
  Markers.write(dest_proj, marker_data)

  return true
end

-- ============================================================================
-- DEBUGGING AND VALIDATION
-- ============================================================================

function Integrator.validate_modules()
  local modules = {
    { name = "ProjectInfo", module = ProjectInfo },
    { name = "Tempo", module = Tempo },
    { name = "Markers", module = Markers },
    { name = "Tracks", module = Tracks },
    { name = "Items", module = Items },
    { name = "Takes", module = Takes },
    { name = "StretchMarkers", module = StretchMarkers },
    { name = "TakeMarkers", module = TakeMarkers }
  }

  local all_valid = true

  for _, mod in ipairs(modules) do
    local valid = true
    if type(mod.module.parse) ~= "function" then
      valid = false
    end
    if type(mod.module.write) ~= "function" then
      valid = false
    end
    -- No logging
    if valid then
      -- ok
    else
      all_valid = false
    end
  end

  return all_valid
end

function Integrator.test_roundtrip(proj)
  -- Parse project
  local original_data = Integrator.parse_project(proj)

  -- Create temporary project and write data
  reaper.Main_OnCommand(40023, 0)  -- New project
  local temp_proj = 0

  local success = Integrator.write_project(temp_proj, original_data)

  if success then
    -- Parse the written project to compare
    local roundtrip_data = Integrator.parse_project(temp_proj)

    -- Basic comparison
    local tracks_match = (original_data.tracks.count == roundtrip_data.tracks.count)
    local items_match = (#original_data.items.items == #roundtrip_data.items.items)

    if tracks_match and items_match then
      return true
    else
      return false
    end
  else
    return false
  end
end

-- ============================================================================
-- MAIN EXECUTION FUNCTIONS
-- ============================================================================

function main()
  -- Optional: run a quick module validation; no automatic execution.
  local _ = Integrator.validate_modules()
end

-- ============================================================================
-- EXPORT THE INTEGRATOR
-- ============================================================================

-- Export all modules and integrator
local ProjectEngine = {
  Integrator = Integrator,
  ProjectInfo = ProjectInfo,
  Tempo = Tempo,
  Markers = Markers,
  Tracks = Tracks,
  Items = Items,
  Takes = Takes,
  StretchMarkers = StretchMarkers,
  TakeMarkers = TakeMarkers
}

-- Make individual modules accessible
ProjectEngine.modules = {
  project_info = ProjectInfo,
  tempo = Tempo,
  markers = Markers,
  tracks = Tracks,
  items = Items,
  takes = Takes,
  stretch_markers = StretchMarkers,
  take_markers = TakeMarkers
}

-- ============================================================================
-- EXECUTION
-- ============================================================================

-- Uncomment to run validation
-- Integrator.validate_modules()

-- Uncomment to run main migration
-- main()

-- Return the engine for use as a library
return ProjectEngine