local M = {}

function M.manager(ctx)
  return ctx.bot and ctx.bot.lavalink
end

function M.author_voice_channel(ctx)
  if not (ctx.guild and ctx.author) then return nil end
  return ctx.bot:get_voice_channel_id(ctx.guild.id, ctx.author.id)
end

function M.player(ctx)
  local manager = M.manager(ctx)
  if not manager then return nil, "Lavalink is still connecting. Try again in a moment." end
  local player = manager:getPlayer(ctx.guild.id)
  if not player then return nil, "I am not in a voice channel." end
  return player
end

function M.join(ctx)
  local manager = M.manager(ctx)
  if not manager then return nil, "Lavalink is still connecting. Try again in a moment." end
  local channel_id = M.author_voice_channel(ctx)
  if not channel_id then return nil, "Join a voice channel first." end
  local player = manager:getPlayer(ctx.guild.id)
  if player then return player, false end
  player = manager:createPlayer({
    guildId = ctx.guild.id,
    voiceChannelId = channel_id,
    textChannelId = ctx.channel and ctx.channel.id,
    selfDeaf = true,
  })
  player:connect()
  return player, true
end

return M
