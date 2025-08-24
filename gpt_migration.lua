-- Runner: calls the integrator once, nothing else.
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\|/])")
package.path = script_path .. "?.lua;" .. package.path

local Engine = dofile(script_path .. "gpt_integrator.lua")
local Config     = require("config")

local source_proj = reaper.EnumProjects(0, "")   -- first project tab
local dest_proj   = reaper.EnumProjects(1, "")   -- second project tab

if not source_proj then
  reaper.ShowMessageBox("❌ No source project found. Please open two project tabs.", "Error", 0)
  return
end

reaper.ShowConsoleMsg("🚀 Starting migration...\n")

local success, project_data = Engine.Integrator.migrate_project(source_proj, dest_proj, {
  clear_destination = false
})

if success then
  reaper.ShowConsoleMsg("✅ Migration completed!\n")
  reaper.ShowConsoleMsg("Tracks: " .. tostring(project_data.stats.tracks or 0) .. "\n")
else
  reaper.ShowMessageBox("❌ Migration failed.", "Error", 0)
end