-- The YouTube nested checks' yt-dlp: a watch URL of a row in search.json plays a silent file as long as the row, titled as the row unless its loadfile named a title, as mpv's ytdl_hook titles it; an id written in DOTS_DEV_DIR/youtube-unavailable fails to open, as a removed video does.
local utils = require 'mp.utils'
local opts = { dir = '' }
require('mp.options').read_options(opts, 'fake_ytdl')

local rows = {}
local f = io.open(opts.dir .. '/search.json')
for _, r in ipairs(utils.parse_json(f:read('*a')).rows) do
  rows[r.id] = r
end
f:close()

local devdir = os.getenv('DOTS_DEV_DIR') or ''

local function unavailable(id)
  local f = io.open(devdir .. '/youtube-unavailable')
  if not f then
    return false
  end
  local text = f:read('*a')
  f:close()
  return text:find(id, 1, true) ~= nil
end

-- A flac of silence, made once per id, as lavfi's own streams have no duration and cannot seek.
local function silence(row)
  local path = ('%s/youtube-silence-%s.flac'):format(devdir, row.id)
  if not utils.file_info(path) then
    mp.command_native({
      name = 'subprocess',
      playback_only = false,
      args = { 'ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'anullsrc=r=8000:cl=mono', '-t', tostring(row.duration), '-c:a', 'flac', path },
    })
  end
  return path
end

mp.add_hook('on_load', 10, function()
  local id = mp.get_property('stream-open-filename', ''):match('^https://www%.youtube%.com/watch%?v=([%w_-]+)$')
  if not id then
    return
  end
  local row = rows[id]
  if not row or unavailable(id) then
    mp.set_property('stream-open-filename', devdir .. '/youtube-no-such-video')
    return
  end
  mp.set_property('stream-open-filename', silence(row))
  if not mp.get_property_native('option-info/force-media-title/set-locally') then
    mp.set_property('file-local-options/force-media-title', row.title)
  end
end)
