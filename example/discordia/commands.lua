local commands = {}
local DEBUG    = false

local function setDebug(val)
  DEBUG = val
end

local function dbg(fmt, ...)
  if DEBUG then
    local ts = os.date("%H:%M:%S")
    print(string.format("%s [DEBUG] [CMD  ] %s", ts, string.format(fmt, ...)))
  end
end

local function log(level, fmt, ...)
  local prefix = {
    INFO  = "[INFO ]",
    WARN  = "[WARN ]",
    ERROR = "[ERROR]",
    PLAY  = "[PLAY ]",
    CMD   = "[CMD  ]",
  }
  local tag = prefix[level] or ("[" .. level .. "]")
  local ts  = os.date("%H:%M:%S")
  print(string.format("%s %s [CMD  ] %s", ts, tag, string.format(fmt, ...)))
end

local function register(name, fn)
  commands[name] = fn
end

local function handle(message, lavalink)
  local prefix  = "!"
  local content = message.content
  if content:sub(1, #prefix) ~= prefix then return end

  local withoutPrefix = content:sub(#prefix + 1)
  local args = {}
  for word in withoutPrefix:gmatch("%S+") do
    table.insert(args, word)
  end

  if #args == 0 then return end

  local cmdName = table.remove(args, 1):lower()
  local cmd     = commands[cmdName]

  if not cmd then
    dbg("Unknown command '%s' by %s#%s in guild %s",
      cmdName,
      message.author.username, message.author.discriminator,
      message.guild.id)
    return
  end

  dbg("'%s' invoked by %s#%s | guild=%s | args=[%s]",
    cmdName,
    message.author.username, message.author.discriminator,
    message.guild.id,
    table.concat(args, ", "))

  local ok, err = pcall(cmd, message, args, lavalink)
  if not ok then
    log("ERROR", "Command '%s' failed: %s", cmdName, tostring(err))
    message:reply("Error: " .. tostring(err))
  end
end

local function reply(message, text)
  message:reply(text)
end

local function getVoiceChannelId(message)
  local member = message.member
  if not member then return nil end
  local vc = member.voiceChannel
  if not vc then return nil end
  return vc.id
end

local function formatDuration(ms)
  if not ms then return "LIVE" end
  local secs  = math.floor(ms / 1000)
  local mins  = math.floor(secs / 60)
  local hours = math.floor(mins / 60)
  secs = secs % 60
  mins = mins % 60
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, mins, secs)
  end
  return string.format("%d:%02d", mins, secs)
end

register("play", function(message, args, lavalink)
  if #args == 0 then
    reply(message, "Usage: `!play <url or search query>`")
    return
  end

  local voiceChannelId = getVoiceChannelId(message)
  if not voiceChannelId then
    dbg("play: %s#%s has no voice channel in guild %s",
      message.author.username, message.author.discriminator, message.guild.id)
    reply(message, "You must be in a voice channel.")
    return
  end

  local guildId = message.guild.id
  local query   = table.concat(args, " ")

  dbg("play: query='%s' guild=%s voiceChannel=%s", query, guildId, voiceChannelId)

  local player, created = lavalink:createPlayer({
    guildId        = guildId,
    voiceChannelId = voiceChannelId,
    textChannelId  = message.channel.id,
    selfDeaf       = true,
  })

  if created then
    dbg("play: new player created for guild=%s, connecting...", guildId)
    player:connect()
  elseif player.voiceChannelId ~= voiceChannelId then
    dbg("play: player channel changed %s -> %s, reconnecting...",
      tostring(player.voiceChannelId), voiceChannelId)
    player.voiceChannelId = voiceChannelId
    player:connect()
  else
    dbg("play: reusing existing player for guild=%s", guildId)
  end

  dbg("play: searching '%s'...", query)
  local result = lavalink:search(query)

  if not result then
    dbg("play: search returned nil for '%s'", query)
    reply(message, "No results found for: `" .. query .. "`")
    return
  end

  dbg("play: loadType=%s", tostring(result.loadType))

  if result.loadType == "empty" or result.loadType == "error" then
    local errMsg = result.data and result.data.message or "unknown error"
    dbg("play: load failed — %s", errMsg)
    reply(message, "No results found for: `" .. query .. "`")
    return
  end

  local tracks = {}
  if result.loadType == "track" then
    tracks = { result.data }
    dbg("play: single track loaded — %s", result.data.info and result.data.info.title or "?")
  elseif result.loadType == "playlist" then
    tracks = result.data.tracks or {}
    local name = result.data.info and result.data.info.name or "Unknown"
    dbg("play: playlist '%s' loaded — %d tracks", name, #tracks)
    reply(message, string.format("Queued playlist **%s** — %d tracks", name, #tracks))
  elseif result.loadType == "search" then
    tracks = { result.data[1] }
    dbg("play: search result selected — %s",
      result.data[1] and result.data[1].info and result.data[1].info.title or "?")
  end

  if #tracks == 0 then
    dbg("play: no tracks to add after load")
    reply(message, "Could not load any tracks.")
    return
  end

  for _, track in ipairs(tracks) do
    player.queue:add(track)
  end

  dbg("play: added %d track(s) to queue (total=%d)", #tracks, player.queue:size())

  if not player.playing then
    dbg("play: player idle — starting playback")
    player:play()
  elseif result.loadType ~= "playlist" and #tracks == 1 then
    local info = tracks[1].info
    dbg("play: player busy — track queued at position %d", player.queue:size())
    reply(message, string.format("Added to queue: **%s** by %s [%s]",
      info.title, info.author, formatDuration(info.length)))
  end
end)

register("skip", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player or not player.playing then
    reply(message, "Nothing is playing.")
    return
  end
  local skipTo  = tonumber(args[1])
  dbg("skip: guild=%s skipTo=%s", message.guild.id, tostring(skipTo))
  local skipped = player:skip(skipTo, false)
  if skipped and skipped.info then
    dbg("skip: skipped '%s'", skipped.info.title)
    reply(message, "Skipped: **" .. skipped.info.title .. "**")
  else
    dbg("skip: queue ended after skip")
    reply(message, "Queue ended.")
  end
end)

register("stop", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player then
    reply(message, "No player found.")
    return
  end
  dbg("stop: guild=%s", message.guild.id)
  player:stopPlaying(true)
  reply(message, "Stopped and cleared the queue.")
end)

register("pause", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player or not player.playing then
    reply(message, "Nothing is playing.")
    return
  end
  player:pause()
  dbg("pause: guild=%s paused=%s", message.guild.id, tostring(player.paused))
  reply(message, player.paused and "Paused." or "Resumed.")
end)

register("resume", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player then reply(message, "No player.") return end
  dbg("resume: guild=%s", message.guild.id)
  player:resume()
  reply(message, "Resumed.")
end)

register("queue", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player then reply(message, "No player.") return end

  dbg("queue: guild=%s current=%s upcoming=%d",
    message.guild.id,
    player.queue.current and player.queue.current.info and player.queue.current.info.title or "none",
    player.queue:size())

  local lines = {}
  if player.queue.current then
    local info = player.queue.current.info
    table.insert(lines, string.format("**Now Playing:** %s — %s [%s]",
      info.title, info.author, formatDuration(info.length)))
  else
    table.insert(lines, "*Nothing playing.*")
  end

  local tracks = player.queue.tracks
  if #tracks == 0 then
    table.insert(lines, "*Queue is empty.*")
  else
    local shown = math.min(#tracks, 10)
    for i = 1, shown do
      local info = tracks[i].info
      table.insert(lines, string.format("%d. %s — %s [%s]",
        i, info.title, info.author, formatDuration(info.length)))
    end
    if #tracks > 10 then
      table.insert(lines, string.format("*...and %d more*", #tracks - 10))
    end
  end

  reply(message, table.concat(lines, "\n"))
end)

register("nowplaying", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player or not player.queue.current then
    reply(message, "Nothing is playing.")
    return
  end
  local info = player.queue.current.info
  local pos  = formatDuration(player:getPosition())
  local dur  = formatDuration(info.length)
  dbg("nowplaying: guild=%s '%s' pos=%s/%s", message.guild.id, info.title, pos, dur)
  reply(message, string.format(
    "**Now Playing:** %s\nby **%s**\n`[%s / %s]`\n<%s>",
    info.title, info.author, pos, dur, info.uri or ""))
end)

register("volume", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player then reply(message, "No player.") return end

  local vol = tonumber(args[1])
  if not vol then
    dbg("volume: guild=%s current=%d", message.guild.id, player.volume)
    reply(message, "Current volume: **" .. player.volume .. "**")
    return
  end
  dbg("volume: guild=%s set %d -> %d", message.guild.id, player.volume, vol)
  player:setVolume(vol)
  reply(message, "Volume set to **" .. player.volume .. "**")
end)

register("repeat", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player then reply(message, "No player.") return end

  local mode = (args[1] or ""):lower()
  if mode ~= "off" and mode ~= "track" and mode ~= "queue" then
    reply(message, "Usage: `!repeat <off|track|queue>`")
    return
  end
  dbg("repeat: guild=%s mode=%s", message.guild.id, mode)
  player:setRepeatMode(mode)
  reply(message, "Repeat mode set to **" .. mode .. "**")
end)

register("shuffle", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player or player.queue:isEmpty() then
    reply(message, "The queue is empty.")
    return
  end
  dbg("shuffle: guild=%s shuffling %d tracks", message.guild.id, player.queue:size())
  player.queue:shuffle()
  reply(message, "Queue shuffled!")
end)

register("seek", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player or not player.playing then
    reply(message, "Nothing is playing.")
    return
  end
  local secs = tonumber(args[1])
  if not secs then reply(message, "Usage: `!seek <seconds>`") return end
  dbg("seek: guild=%s -> %ds (%dms)", message.guild.id, secs, secs * 1000)
  player:seek(secs * 1000)
  reply(message, "Seeked to " .. formatDuration(secs * 1000))
end)

register("dc", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player then reply(message, "No player.") return end
  dbg("dc: destroying player for guild=%s", message.guild.id)
  player:disconnect(true)
  reply(message, "Disconnected and destroyed player.")
end)

register("nodes", function(message, args, lavalink)
  local nodes = lavalink:getAllNodes()
  dbg("nodes: listing %d node(s)", #nodes)
  local lines = { "**Lavalink Nodes:**" }
  for _, node in ipairs(nodes) do
    local status = node:isUsable() and "READY"
      or (node.connected and "CONNECTED" or "OFFLINE")
    table.insert(lines, string.format("• `%s` — %s | Players: %d | CPU: %.1f%%",
      node.options.id, status,
      node:getPlayersCount(),
      node:getCpuLoad() * 100))
  end
  reply(message, table.concat(lines, "\n"))
end)

register("filter", function(message, args, lavalink)
  local player = lavalink:getPlayer(message.guild.id)
  if not player then reply(message, "No player.") return end

  local name = (args[1] or ""):lower()
  dbg("filter: guild=%s filter='%s'", message.guild.id, name)

  if name == "nightcore" then
    player.filters:setTimescale({ speed = 1.3, pitch = 1.3, rate = 1.0 })
    reply(message, "Nightcore filter enabled.")
  elseif name == "vaporwave" then
    player.filters:setTimescale({ speed = 0.85, pitch = 0.85, rate = 1.0 })
    reply(message, "Vaporwave filter enabled.")
  elseif name == "8d" then
    player.filters:setRotation({ rotationHz = 0.2 })
    reply(message, "8D audio filter enabled.")
  elseif name == "bassboost" then
    local bands = {}
    for i = 0, 4 do
      table.insert(bands, { band = i, gain = 0.35 })
    end
    player.filters:setEqualizer(bands)
    reply(message, "Bass boost filter enabled.")
  elseif name == "reset" then
    player.filters:resetFilters()
    dbg("filter: guild=%s all filters reset", message.guild.id)
    reply(message, "All filters reset.")
  else
    reply(message, "Available filters: `nightcore`, `vaporwave`, `8d`, `bassboost`, `reset`")
  end
end)

return {
  register = register,
  handle   = handle,
  setDebug = setDebug,
}
