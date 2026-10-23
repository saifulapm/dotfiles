-- Opens $XDG_RUNTIME_DIR/mpv-<pid>.sock, so dots theme can recolour every open player; a player started with its own socket keeps it.
local dir = os.getenv('XDG_RUNTIME_DIR')
if dir and mp.get_property('input-ipc-server', '') == '' then
  local path = dir .. '/mpv-' .. mp.get_property_native('pid') .. '.sock'
  mp.set_property('input-ipc-server', path)
  mp.register_event('shutdown', function() os.remove(path) end)
end
