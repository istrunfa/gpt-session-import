--[[
@description REAPER Project Engine - Project Info Module
@version 1.0
@about Handles project-level settings and metadata
--]]

local ProjectInfo = {}

function ProjectInfo.parse(proj)
  local data = {}
  
  -- Project sample rate → GetSetProjectInfo(…, "PROJECT_SRATE", 0, false)
  data.sample_rate = reaper.GetSetProjectInfo(proj, "PROJECT_SRATE", 0, false)
  
  -- Project‑specific sample rate enabled → GetSetProjectInfo(…, "PROJECT_SRATE_USE", 0, false)
  data.sample_rate_use = reaper.GetSetProjectInfo(proj, "PROJECT_SRATE_USE", 0, false)
  
  -- Additional project info
  local _, title = reaper.GetSetProjectInfo_String(proj, "PROJECT_TITLE", "", false)
  local _, author = reaper.GetSetProjectInfo_String(proj, "PROJECT_AUTHOR", "", false)
  local _, notes = reaper.GetSetProjectInfo_String(proj, "PROJECT_NOTES", "", false)
  
  data.title = title
  data.author = author
  data.notes = notes
  
  return data
end

function ProjectInfo.write(dest_proj, data, opts)
  if not data then return false end
  
  reaper.GetSetProjectInfo(dest_proj, "PROJECT_SRATE", data.sample_rate or 44100, true)
  reaper.GetSetProjectInfo(dest_proj, "PROJECT_SRATE_USE", data.sample_rate_use or 0, true)
  
  if data.title then
    reaper.GetSetProjectInfo_String(dest_proj, "PROJECT_TITLE", data.title, true)
  end
  if data.author then
    reaper.GetSetProjectInfo_String(dest_proj, "PROJECT_AUTHOR", data.author, true)
  end
  if data.notes then
    reaper.GetSetProjectInfo_String(dest_proj, "PROJECT_NOTES", data.notes, true)
  end
  
  return true
end

return ProjectInfo