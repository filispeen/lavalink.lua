local lavalinklua = require("lavalink.lua")
local splitSearchResult = lavalinklua.utils.splitSearchResult

local M = {}

local DEBUG = false

function M.setDebug(value)
  DEBUG = value
end

local function dbg(fmt, ...)
  if DEBUG then
    print(string.format("[%s] [DEBUG] [CMD  ] %s", os.date("%H:%M:%S"), string.format(fmt, ...)))
  end
end

function M.notify(bot, channelId, content)
  if not channelId then return end
  local ok, err = pcall(function()
    bot.client.rest:send_message(channelId, { content = content })
  end)
  if not ok then
    dbg("notify failed | channel=%s err=%s", channelId, tostring(err))
  end
end

local function reply(bot, message, content)
  local ok = pcall(function()
    message:reply(content)
  end)
  if not ok then
    M.notify(bot, message.channel_id, content)
  end
end

local function argsFrom(message)
  return message.content:match("^%S+%s+(.*)$") or ""
end

local function getPlayer(bot, guildId)
  return bot.lavalink and bot.lavalink:getPlayer(guildId)
end

local function requireVoice(bot, message)
  local channelId = bot:get_author_voice_channel_id(message)
  if not channelId then
    reply(bot, message, "You need to be in a voice channel first.")
    return nil
  end
  return channelId
end

local function formatDuration(ms)
  if not ms or ms <= 0 then return "0:00" end
  local totalSeconds = math.floor(ms / 1000)
  local minutes = math.floor(totalSeconds / 60)
  local seconds = totalSeconds % 60
  return string.format("%d:%02d", minutes, seconds)
end

function M.register(bot)
  bot:command("play", function(message)
    local query = argsFrom(message)
    if query == "" then
      reply(bot, message, "Usage: !play <query or url>")
      return
    end

    local voiceChannelId = requireVoice(bot, message)
    if not voiceChannelId then return end

    dbg("play requested | guild=%s query=%s", message.guild_id, query)

    local player = getPlayer(bot, message.guild_id)
    if not player then
      player = bot.lavalink:createPlayer({
        guildId = message.guild_id,
        voiceChannelId = voiceChannelId,
        textChannelId = message.channel_id,
        selfDeaf = true,
      })
      player:connect()
    end

    local ok, result = pcall(function()
      return bot.lavalink:search(query)
    end)

    if not ok then
      reply(bot, message, "Search failed: " .. tostring(result))
      return
    end

    if result.loadType == "error" then
      local msg = result.data and result.data.message or "unknown error"
      reply(bot, message, "Load error: " .. msg)
      return
    end

    if result.loadType == "empty" then
      reply(bot, message, "No results found.")
      return
    end

    local tracks = splitSearchResult(result.loadType, result)
    if not tracks or #tracks == 0 then
      reply(bot, message, "No results found.")
      return
    end

    player.queue:add(tracks)

    if result.loadType == "playlist" then
      local name = result.data and result.data.info and result.data.info.name or "unknown"
      reply(bot, message, string.format("Queued playlist **%s** (%d tracks).", name, #tracks))
    else
      local track = tracks[1]
      reply(bot, message, string.format("Queued: **%s** by %s [%s]",
        track.info.title, track.info.author, formatDuration(track.info.length)))
    end

    if not player.playing and not player.paused then
      player:play()
    end
  end, "Play a track or add it to the queue")

  bot:command("skip", function(message)
    local player = getPlayer(bot, message.guild_id)
    if not player then
      reply(bot, message, "Nothing is playing.")
      return
    end
    local ok, err = pcall(function()
      player:skip()
    end)
    if ok then
      reply(bot, message, "Skipped.")
    else
      reply(bot, message, "Could not skip: " .. tostring(err))
    end
  end, "Skip the current track")

  bot:command("pause", function(message)
    local player = getPlayer(bot, message.guild_id)
    if not player then
      reply(bot, message, "Nothing is playing.")
      return
    end
    player:pause(true)
    reply(bot, message, "Paused.")
  end, "Pause playback")

  bot:command("resume", function(message)
    local player = getPlayer(bot, message.guild_id)
    if not player then
      reply(bot, message, "Nothing is playing.")
      return
    end
    player:resume()
    reply(bot, message, "Resumed.")
  end, "Resume playback")

  bot:command("stop", function(message)
    local player = getPlayer(bot, message.guild_id)
    if not player then
      reply(bot, message, "Nothing is playing.")
      return
    end
    player:stopPlaying(true)
    reply(bot, message, "Stopped and cleared the queue.")
  end, "Stop playback and clear the queue")

  bot:command("leave", function(message)
    local player = getPlayer(bot, message.guild_id)
    if not player then
      reply(bot, message, "I'm not connected to voice.")
      return
    end
    player:destroy("user requested")
    reply(bot, message, "Disconnected.")
  end, "Leave the voice channel")

  bot:command("volume", function(message)
    local arg = argsFrom(message)
    local vol = tonumber(arg)
    local player = getPlayer(bot, message.guild_id)
    if not player then
      reply(bot, message, "Nothing is playing.")
      return
    end
    if not vol then
      reply(bot, message, string.format("Current volume: %d", player.volume or 100))
      return
    end
    local ok, err = pcall(function()
      player:setVolume(vol)
    end)
    if ok then
      reply(bot, message, string.format("Volume set to %d.", vol))
    else
      reply(bot, message, "Could not set volume: " .. tostring(err))
    end
  end, "Get or set player volume")

  bot:command("seek", function(message)
    local seconds = tonumber(argsFrom(message))
    if not seconds then
      reply(bot, message, "Usage: !seek <seconds>")
      return
    end
    local player = getPlayer(bot, message.guild_id)
    if not player then
      reply(bot, message, "Nothing is playing.")
      return
    end
    local ok, err = pcall(function()
      player:seek(seconds * 1000)
    end)
    if ok then
      reply(bot, message, string.format("Seeked to %ds.", seconds))
    else
      reply(bot, message, "Could not seek: " .. tostring(err))
    end
  end, "Seek to a position in seconds")

  bot:command("repeat", function(message)
    local arg = argsFrom(message):lower()
    if arg ~= "off" and arg ~= "track" and arg ~= "queue" then
      reply(bot, message, "Usage: !repeat <off|track|queue>")
      return
    end
    local player = getPlayer(bot, message.guild_id)
    if not player then
      reply(bot, message, "Nothing is playing.")
      return
    end
    player:setRepeatMode(arg)
    reply(bot, message, "Repeat mode set to " .. arg .. ".")
  end, "Set repeat mode: off, track, or queue")

  bot:command("queue", function(message)
    local player = getPlayer(bot, message.guild_id)
    if not player or not player.queue or #player.queue.tracks == 0 then
      reply(bot, message, "The queue is empty.")
      return
    end
    local lines = {}
    for i, track in ipairs(player.queue.tracks) do
      if i > 10 then
        table.insert(lines, string.format("...and %d more", #player.queue.tracks - 10))
        break
      end
      table.insert(lines, string.format("%d. %s - %s", i, track.info.title, track.info.author))
    end
    reply(bot, message, table.concat(lines, "\n"))
  end, "Show the current queue")

  bot:command("nowplaying", function(message)
    local player = getPlayer(bot, message.guild_id)
    if not player or not player.queue or not player.queue.current then
      reply(bot, message, "Nothing is playing.")
      return
    end
    local track = player.queue.current
    reply(bot, message, string.format("Now playing: **%s** by %s [%s / %s]",
      track.info.title, track.info.author,
      formatDuration(player:getPosition()), formatDuration(track.info.length)))
  end, "Show the currently playing track")

  bot:command("nodes", function(message)
    if not bot.lavalink then
      reply(bot, message, "Lavalink is not initialized.")
      return
    end
    local nodes = bot.lavalink:getAllNodes()
    if #nodes == 0 then
      reply(bot, message, "No nodes configured.")
      return
    end
    local lines = {}
    for _, node in ipairs(nodes) do
      table.insert(lines, string.format("%s | connected=%s players=%d cpu=%.1f%%",
        node.options.id,
        tostring(node.connected),
        node:getPlayersCount(),
        node:getCpuLoad() * 100))
    end
    reply(bot, message, table.concat(lines, "\n"))
  end, "Show connected Lavalink nodes")

  bot:command("filter", function(message)
    local arg = argsFrom(message):lower()
    local player = getPlayer(bot, message.guild_id)
    if not player then
      reply(bot, message, "Nothing is playing.")
      return
    end

    if arg == "reset" then
      player.filters:resetFilters()
      reply(bot, message, "Filters reset.")
    elseif arg == "nightcore" then
      player.filters:setTimescale({ speed = 1.2, pitch = 1.2, rate = 1.0 })
      reply(bot, message, "Nightcore filter applied.")
    elseif arg == "vaporwave" then
      player.filters:setTimescale({ speed = 0.8, pitch = 0.8, rate = 1.0 })
      reply(bot, message, "Vaporwave filter applied.")
    elseif arg == "8d" then
      player.filters:setRotation({ rotationHz = 0.2 })
      reply(bot, message, "8D filter applied.")
    else
      reply(bot, message, "Usage: !filter <nightcore|vaporwave|8d|reset>")
    end
  end, "Apply an audio filter")

  bot:command("help", function(message)
    local lines = {
      "!play <query|url> - play a track or add to queue",
      "!skip - skip current track",
      "!pause / !resume - pause or resume playback",
      "!stop - stop and clear queue",
      "!leave - disconnect from voice",
      "!volume [0-1000] - get or set volume",
      "!seek <seconds> - seek to position",
      "!repeat <off|track|queue> - set repeat mode",
      "!queue - show queue",
      "!nowplaying - show current track",
      "!filter <nightcore|vaporwave|8d|reset> - apply audio filter",
      "!nodes - show connected Lavalink nodes",
    }
    reply(bot, message, table.concat(lines, "\n"))
  end, "Show this help message")
end

return M
