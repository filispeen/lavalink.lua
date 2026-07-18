local LavalinkManager = require("../libs/LavalinkManager")

local function createDiscordLuaIntegration(bot, lavalinkOptions)
  assert(bot,            "[discord.lua] bot required")
  assert(lavalinkOptions,"[discord.lua] lavalinkOptions required")

  lavalinkOptions.clientId = lavalinkOptions.clientId
    or (bot.user and bot.user.id)
    or error("[discord.lua] clientId required")

  -- discord.lua already resolves which shard owns a guild and sends
  -- opcode 4 itself (Client:voice_state_update), so sendPayload here
  -- only needs to unwrap Lavalink's {op, d} envelope.
  lavalinkOptions.sendPayload = lavalinkOptions.sendPayload or function(guildId, payload)
    if not bot.client then
      error("[discord.lua] bot has no client, call bot:connect() or bot:run() first")
    end

    local d = payload.d or {}
    bot.client:voice_state_update(
      d.guild_id or guildId,
      d.channel_id,
      d.self_mute or false,
      d.self_deaf or false
    )
  end

  local manager = LavalinkManager.new(lavalinkOptions)

  -- discord.lua dispatches these as their own structured events, no raw
  -- JSON string to decode here (unlike Discordia's "raw" event).
  bot:on("voice_state_update", function(data)
    manager:handleVoiceUpdate({ t = "VOICE_STATE_UPDATE", d = data })
  end)

  bot:on("voice_server_update", function(data)
    manager:handleVoiceUpdate({ t = "VOICE_SERVER_UPDATE", d = data })
  end)

  return manager
end

return createDiscordLuaIntegration
