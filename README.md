# REAPER Modular Project Engine

A modular Lua engine for REAPER that can **parse and recreate full project data** using only the official API.  
Each feature is implemented as a separate module with a consistent `parse` / `write` API.  
A central `integrator` orchestrates complete project migration, merging, and templating.

---

## ✅ Current Implementation Status

- ✅ **Project Info** → Sample rate and project-level settings
- ✅ **Tempo & Time Signatures** → Full tempo map with markers
- ✅ **Markers & Regions** → Complete support with GUIDs
- ✅ **Tracks** → Properties, fixed lanes, names, envelopes, FX, routing
- ✅ **Media Items** → Properties, fades, notes, crossfades
- ✅ **Takes** → Properties, sources (audio/MIDI), FX, envelopes, active take state
- ✅ **Stretch Markers** → Full per-take stretch marker parsing/writing
- ✅ **Take Markers** → Per-take marker parsing/writing
- ✅ **Track FX & Routing** → FX chain (with parameters), sends/receives
- ✅ **Matching Module** → Exact-name track matching & merging
- ✅ **Central Config** → Toggles for all modules + matching strategies
- 🧹 **Logging** → All internal logs removed (silent operation)

---

## 📁 File Structure

```
reaper_modular_engine/
├── integrator.lua          # Orchestrates everything
├── config.lua              # Central config (toggles + matching)
├── matching.lua            # Track matching & merge logic
├── project_info.lua        # Project settings
├── tempo.lua               # Tempo & time signatures
├── markers.lua             # Markers & regions
├── tracks.lua              # Tracks (props, lanes, FX, routing, envelopes)
├── items.lua               # Media items (fades, notes, crossfades)
├── takes.lua               # Takes (sources, FX, envelopes)
├── stretch_markers.lua     # Per‑take stretch markers
├── take_markers.lua        # Per‑take markers
└── usage_examples.lua      # Example usage patterns
```

---

## ⚙️ Central Config (`config.lua`)

All writing is toggle-based. Parsing is always **ON**.

Example (tracks section):

```lua
tracks = {
  clear_existing_tracks   = true,   -- remove all tracks before writing
  name                    = true,   -- track names
  properties              = true,   -- volume, pan, mute, etc.
  envelopes               = true,   -- track envelopes + automation items
  fx                      = true,   -- FX chain with parameters
  routing_parent_send     = true,   -- parent send flag
  routing_sends           = true,   -- track sends
}
```

### Matching Config

```lua
matching = {
  exact_name = true,   -- match source/dest tracks by exact name
  fuzzy_name = false,  -- (future) fuzzy/partial matching
}
```

---

## 🚀 Usage Examples

### Complete Migration
```lua
local Engine = dofile("path/to/integrator.lua")
local src = Engine.Integrator.find_project_by_path("/path/to/source.RPP")

-- migrate everything into current project
Engine.Integrator.migrate_project(src, 0, {
  clear_destination = true,
})
```

### Selective Copy
```lua
local tempo = Engine.Tempo.parse(src)
Engine.Tempo.write(0, tempo)

local markers = Engine.Markers.parse(src)
Engine.Markers.write(0, markers)
```

### Merge with Matching
```lua
local tracks_data = Engine.Tracks.parse(src)
local plan = Engine.Match.build_plan(0, tracks_data, Engine.Config.matching)

Engine.Tracks.write_with_match_plan(0, tracks_data, plan, {}, Engine.Config.tracks)
```

---

## 🎯 Use Cases

1. **Full migration** → move everything between tabs
2. **Template creation** → preserve structure, strip media
3. **Selective copy** → tempo only, markers only, etc.
4. **Merge projects** → integrate production into mix templates
5. **Automation migration** → preserve envelopes & automation items
6. **Track FX migration** → including 3rd party plugin parameters

---

## ⚠️ Known Limitations

1. **Multi‑take write** – parsing is complete, but writing currently prioritizes active take (expansion planned).  
2. **Matching** – only exact name match implemented (fuzzy/regex to come).  
3. **Some 3rd‑party FX** – presets/parameters may need plugin‑specific patches.  

---

## 📝 Development Notes

- **Modules are standalone** → each can be tested independently.  
- **Integrator is logic‑light** → only coordinates modules.  
- **Config‑driven** → writing behavior controlled centrally.  
- **Silent by default** → debug prints removed.  

---

**Status:** Production‑ready for project migration, templating, and track merging.  
Future work: multi‑take writing, advanced matching strategies, plugin‑specific FX patches.