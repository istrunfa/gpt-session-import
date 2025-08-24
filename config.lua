--[[
@description REAPER Modular Project Engine - Central Config
@version 1.0
@about Centralized user configuration for write toggles and matching strategies
--]]

local config = {

  -- ==========================================================================
  -- TRACKS
  -- ==========================================================================
  tracks = {
    name = true,
    properties = true,
    fx = true,
    envelopes = true,
    lane_configuration = true,
    clear_existing_tracks = false,
    fx_clear_existing     = true,

    routing_parent_send = true,
    routing_sends = true,
    routing_clear_existing = false
  },

  -- ==========================================================================
  -- ITEMS
  -- ==========================================================================
  items = {
    clear_existing_items = false,
    create_items = true,
    properties = true,
    notes = true,
    crossfades = true
  },

  -- ==========================================================================
  -- TAKES
  -- ==========================================================================
  takes = {
    clear_default_takes = true,  -- delete default/placeholder takes in destination item before writing
    name = true,
    properties = true,
    source_content = true,
    fx = true,
    envelopes = true,
    set_active_take = true
  },

  -- ==========================================================================
  -- TEMPO / TIME SIGNATURES
  -- ==========================================================================
  tempo = {
    markers = true,
    clear_existing_markers = false
  },

  -- ==========================================================================
  -- PROJECT INFO
  -- ==========================================================================
  project_info = {
    sample_rate = true,
    sample_rate_use = true,
    title = true,
    author = true,
    notes = true
  },

  -- ==========================================================================
  -- STRETCH MARKERS
  -- ==========================================================================
  stretch_markers = {
    markers = true,
    slopes = true,
    clear_existing = false
  },

  -- ==========================================================================
  -- TAKE MARKERS
  -- ==========================================================================
  take_markers = {
    markers = true,
    clear_existing = false
  },

  -- ==========================================================================
  -- PROJECT MARKERS / REGIONS
  -- ==========================================================================
  markers = {
    markers = true,
    regions = true,
    clear_existing = false
  },

  -- ==========================================================================
  -- MATCHING (Track/Take merge / creation strategy)
  -- ==========================================================================
  matching = {
    enabled = true,
    tracks = {
      exact_name = true,        -- match tracks by exact name
      index_fallback = false,    -- if no name match, try by index
    },
    takes = {
      exact_name = true,        -- match takes by exact name
      index_fallback = false,    -- if no name match, try by index
    },
    fallback_create = true      -- if no match, create new track/take
  }
}

return config