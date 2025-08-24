# GPT Session Import Engine

A modular REAPER engine to automate intelligent project migration between session types — such as from a **Production** project into a **Mix Template** — preserving creative intent while keeping mix structure clean and intact.

---

## 🔍 Overview

This engine reads a source REAPER project and imports selected session data (tracks, items, lanes, markers, FX, etc.) into a destination project, with full support for:

- 🧠 Track name–based matching
- 🎚 Lane and take structure preservation
- 🎛 FX chains, take envelopes, MIDI and stretch markers
- 🕹 Configurable import behavior via `config.lua`
- 🔀 Hybrid merge + replace logic with track offset correction

---

## 📂 Project Structure

| Module              | Purpose                                                                 |
|---------------------|-------------------------------------------------------------------------|
| `gpt_integrator.lua`| Core orchestration: coordinates all phases of migration                |
| `project_info.lua`  | Parses project metadata (name, path, etc.)                              |
| `tracks.lua`        | Parses and writes track structure and metadata                          |
| `items.lua`         | Handles media items + mapping                                           |
| `takes.lua`         | Manages takes, FX, envelopes, sources (MIDI/audio)                      |
| `stretch_markers.lua`| Applies stretch markers to target takes                                |
| `take_markers.lua`  | Transfers per-take marker metadata                                       |
| `tempo.lua`         | Transfers tempo map and time signatures                                 |
| `markers.lua`       | Transfers project markers and regions                                   |
| `matching.lua`      | Provides track matching plans                                           |
| `log.lua`           | Modular logging system for better debugging                             |
| `config.lua`        | Central config for import scope and behavior                            |

---

## ✅ Supported Features

- 🎯 Precise per-track matching (name-based or full merge)
- 🧱 Full lane and take preservation
- 🎹 MIDI and audio content with stretch markers and envelopes
- 💅 Take FX cloning and preset restoration
- 📈 Configurable write strategy (replace, merge, or hybrid)
- 🧩 Modular system: easy to extend and customize

---

## 🚀 Usage

Place the engine scripts inside:
/User/…/REAPER Media/User/Scripts/BitSound/GPT Session Import/

Then call `gpt_migration.lua` or your orchestrator script.

---

## 🧠 Notes

- Existing unmatched tracks in the destination are preserved and accounted for with offset-corrected mappings.
- Source take FX and envelopes are cloned when possible.
- Advanced logging output via `log.lua` for better traceability.

---

## 🛠 Developed By

BitSound Studio — Carlos Ferreira & ChatGPT  
Open modular architecture for REAPER workflow automation.