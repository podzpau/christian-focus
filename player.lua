-- Loaded into the backend's mpv.
local utils = require "mp.utils"

-- Recordings from Wikimedia Commons are read straight through in one request:
-- an Ogg file otherwise makes mpv jump to its end to find the length, and
-- Commons answers quick bursts of requests with "429 Too many requests". With
-- no seeking the whole file is buffered, so playback never has to reconnect.
-- Wikimedia also asks clients to say who they are.
mp.add_hook("on_load", 50, function()
  if mp.get_property("stream-open-filename", ""):find("^https://upload%.wikimedia%.org/") then
    mp.set_property("file-local-options/user-agent", "Christian-Focus/1.0 (https://github.com/podzpau/christian-focus)")
    mp.set_property("file-local-options/stream-lavf-o", "seekable=0")
    mp.set_property("file-local-options/demuxer-max-bytes", "1GiB")
  end
end)

-- Give up after five songs in a row fail to load (offline, or YouTube changed
-- and yt-dlp needs an update) instead of trying every song in the list.
local failures = 0
mp.register_event("end-file", function(event)
  failures = event.reason == "error" and failures + 1 or 0
  if failures >= 5 then mp.command("quit") end
end)

-- Stop once the plugin is removed: nothing else is left to stop this player.
local backend = mp.get_opt("christian_focus-backend")
if backend then
  local missing = 0
  mp.add_periodic_timer(60, function()
    missing = utils.file_info(backend) and 0 or missing + 1
    if missing >= 2 then mp.command("quit") end
  end)
end
