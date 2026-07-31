local discord = require("discord.lua")
local lavalinklua = require("lavalink.lua")
local commands = require("./commands")
local env = require("./env")
env.load()

local DEBUG = process.env.DEBUG == "true" or process.env.DEBUG == "1"

local TOKEN = process.env.TOKEN or error("TOKEN env var not set")
local LAVALINK_HOST = process.env.LAVALINK_HOST or "localhost"
local LAVALINK_PORT = tonumber(process.env.LAVALINK_PORT) or 2333
local LAVALINK_PASS = process.env.LAVALINK_PASS or "youshallnotpass"

local function log(level, fmt, ...)
  local prefix = {
    INFO = "[INFO ]",
    WARN = "[WARN ]",
    ERROR = "[ERROR]",
    DEBUG = "[DEBUG]",
    NODE = "[NODE ]",
    TRACK = "[TRACK]",
    VOICE = "[VOICE]",
    BOT = "[BOT  ]",
  }
  local tag = prefix[level] or ("[" .. level .. "]")
  print(string.format("%s %s %s", os.date("%H:%M:%S"), tag, string.format(fmt, ...)))
end

local function dbg(fmt, ...)
  if DEBUG then log("DEBUG", fmt, ...) end
end

-- Prefix commands below need GUILD_MESSAGES to see the message and
-- MESSAGE_CONTENT (privileged, enable it on the dev portal too) to read
-- message.content. GUILD_VOICE_STATES is needed for get_author_voice_channel_id.
local intents = discord.enums.combine_intents(
  discord.enums.INTENTS.GUILDS,
  discord.enums.INTENTS.GUILD_MESSAGES,
  discord.enums.INTENTS.MESSAGE_CONTENT,
  discord.enums.INTENTS.GUILD_VOICE_STATES
)

local bot = discord.Bot(nil, intents)

bot:on("ready", function()
  log("BOT", "Logged in as %s (id: %s)", bot.user.username, bot.user.id)
  dbg("Lavalink target: %s:%d", LAVALINK_HOST, LAVALINK_PORT)

  local lavalink = lavalinklua.discord(bot, {
    clientName = "lavalink-lua/1.0",
    nodes = {
      {
        id = "main",
        host = LAVALINK_HOST,
        port = LAVALINK_PORT,
        authorization = LAVALINK_PASS,
        secure = false,
        resuming = true,
        resumeTimeout = 60,
        reconnectTries = 5,
        reconnectDelay = 5000,
      },
    },
    playerOptions = { defaultVolume = 100 },
  })

  bot.lavalink = lavalink

  commands.setDebug(DEBUG)
  commands.register(bot)

  lavalink:on("nodeConnect", function(node)
    log("NODE", "'%s' - WebSocket connected", node.options.id)
  end)

  lavalink:on("nodeReady", function(node, resumed, sessionId)
    log("NODE", "'%s' - ready | resumed=%s | session=%s",
      node.options.id, tostring(resumed), sessionId)
  end)

  lavalink:on("nodeDisconnect", function(node, reason)
    log("NODE", "'%s' - disconnected | reason=%s", node.options.id, tostring(reason))
  end)

  lavalink:on("nodeReconnecting", function(node, attempt, delay)
    log("NODE", "'%s' - reconnecting (attempt %d / %d, delay %dms)",
      node.options.id, attempt, node.options.reconnectTries, delay)
  end)

  lavalink:on("nodeError", function(node, err)
    log("ERROR", "Node '%s' error: %s", node.options.id, tostring(err))
  end)

  lavalink:on("nodeStats", function(node, stats)
    dbg("Node '%s' stats | players=%d playing=%d uptime=%ds cpu=%.2f%%",
      node.options.id,
      stats.players or 0,
      stats.playingPlayers or 0,
      math.floor((stats.uptime or 0) / 1000),
      (stats.cpu and stats.cpu.lavalinkLoad or 0) * 100)
  end)

  lavalink:on("nodeUnknownMessage", function(node, data)
    dbg("Node '%s' unknown WS op: %s", node.options.id, tostring(data.op))
  end)

  lavalink:on("playerCreate", function(player)
    dbg("Player created | guild=%s node=%s", player.guildId, player.node.options.id)
  end)

  lavalink:on("playerDestroy", function(player, reason)
    dbg("Player destroyed | guild=%s reason=%s", player.guildId, tostring(reason))
  end)

  lavalink:on("playerUpdate", function(player, state)
    dbg("PlayerUpdate | guild=%s pos=%dms ping=%dms connected=%s",
      player.guildId, state.position or 0, state.ping or 0, tostring(state.connected))
  end)

  lavalink:on("playerPause", function(player)
    dbg("Player paused | guild=%s", player.guildId)
  end)

  lavalink:on("playerResume", function(player)
    dbg("Player resumed | guild=%s", player.guildId)
  end)

  lavalink:on("playerRepeat", function(player, mode)
    dbg("Repeat mode changed | guild=%s mode=%s", player.guildId, mode)
  end)

  lavalink:on("playerMoved", function(player, oldNode, newNode)
    dbg("Player moved | guild=%s from='%s' to='%s'",
      player.guildId, oldNode.options.id, newNode.options.id)
  end)

  lavalink:on("trackStart", function(player, track)
    local info = track and track.info
    if info then
      log("TRACK", "Start | guild=%s | %s - %s [%s]",
        player.guildId, info.title, info.author,
        info.length and string.format("%ds", math.floor(info.length / 1000)) or "LIVE")
      commands.notify(bot, player.textChannelId,
        string.format("Now playing: **%s** by %s", info.title, info.author))
    end
  end)

  lavalink:on("trackEnd", function(player, track, reason)
    local title = track and track.info and track.info.title or "?"
    dbg("Track end | guild=%s reason=%s track=%s", player.guildId, reason, title)
  end)

  lavalink:on("trackError", function(player, track, err)
    local title = track and track.info and track.info.title or "?"
    local msg   = type(err) == "table" and (err.message or "unknown") or tostring(err)
    log("ERROR", "Track error | guild=%s track='%s' err=%s", player.guildId, title, msg)
    commands.notify(bot, player.textChannelId, string.format("Track error: %s - skipping...", msg))
    player:skip(nil, false)
  end)

  lavalink:on("trackStuck", function(player, track, threshold)
    local title = track and track.info and track.info.title or "?"
    log("WARN", "Track stuck | guild=%s track='%s' threshold=%dms",
      player.guildId, title, threshold)
    commands.notify(bot, player.textChannelId,
      string.format("Track got stuck (>%dms) - skipping...", threshold))
    player:skip(nil, false)
  end)

  lavalink:on("queueEnd", function(player)
    log("TRACK", "Queue ended | guild=%s", player.guildId)
    commands.notify(bot, player.textChannelId, "Queue finished. Add more songs!")
  end)

  lavalink:on("socketClosed", function(player, code, reason, byRemote)
    log("VOICE", "WS closed | guild=%s code=%d reason=%s byRemote=%s",
      player.guildId, code, tostring(reason), tostring(byRemote))
    if code == 4006 or code == 4014 then
      dbg("Reconnecting voice for guild=%s (code %d)", player.guildId, code)
      local voiceChannelId = player.voiceChannelId
      player:disconnect(false)
      if voiceChannelId then
        player.voiceChannelId = voiceChannelId
        player:connect()
      end
    end
  end)

  lavalink:on("error", function(player, err)
    log("ERROR", "Player error | guild=%s err=%s",
      player and player.guildId or "?", tostring(err))
  end)

  lavalink:init()
  dbg("LavalinkManager initialized, connecting nodes...")
end)

bot:on("shard_ready", function(shard_id)
  dbg("Shard %s is ready", tostring(shard_id))
end)

bot:on("shard_disconnect", function(shard_id)
  log("WARN", "Shard %s disconnected", tostring(shard_id))
end)

bot:on("shard_error", function(shard_id, _shard, err)
  log("ERROR", "Shard %s errored: %s", tostring(shard_id), tostring(err))
end)

bot:run(TOKEN)
