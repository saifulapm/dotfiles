-- Reports what tests/mpv/run.sh checks, as JSON in the file named by script-opt probe-out.
local utils = require("mp.utils")
local opts = { out = "", mode = "drops", shot = "", ["quit-at"] = 10 }
require("mp.options").read_options(opts, "probe")

local seen = {}
-- mpv drops its properties before shutdown, so the counters are cached on every time-pos change.
local function cache()
  seen.frame_drops = mp.get_property_number("frame-drop-count", seen.frame_drops)
  seen.decoder_drops = mp.get_property_number("decoder-frame-drop-count", seen.decoder_drops)
  seen.delayed = mp.get_property_number("vo-delayed-frame-count", seen.delayed)
  seen.hwdec = mp.get_property("hwdec-current", seen.hwdec)
end

mp.observe_property("time-pos", "number", function(_, pos)
  if not pos then return end
  cache()
  seen.pos = pos
  if opts.mode == "quit-at" and pos >= opts["quit-at"] then mp.command("quit") end
end)

local restarted = false
mp.register_event("playback-restart", function()
  if restarted then return end
  restarted = true
  cache()
  if opts.mode == "shot" then
    mp.commandv("screenshot-to-file", opts.shot, "video")
    mp.command("quit")
  elseif opts.mode == "read-pos" then
    seen.start = mp.get_property_number("time-pos")
    mp.command("quit")
  end
end)

local function write()
  local f = io.open(opts.out, "w")
  f:write(utils.format_json(seen))
  f:close()
end
mp.register_event("end-file", write)
mp.register_event("shutdown", write)
