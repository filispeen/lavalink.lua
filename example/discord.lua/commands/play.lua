local lavalinklua = require("lavalink.lua")
local helpers = require("./helpers")

return function(bot, discord)
  bot:slash_command("play", {
    description = "Play a search query or an HTTP(S) audio URL",
    options = {
      { name = "source", type = discord.enums.OPTION_TYPE.STRING, description = "Search words or URL", required = true },
    },
    callback = function(ctx)
      local player, error_message = helpers.join(ctx)
      if not player then return ctx:respond(error_message, { ephemeral = true }) end
      local ok, result = pcall(player.manager.search, player.manager, ctx:require_arg("source"))
      if not ok then return ctx:respond("Lavalink could not load that source: " .. tostring(result), { ephemeral = true }) end
      local tracks = lavalinklua.utils.splitSearchResult(result.loadType, result)
      if #tracks == 0 then return ctx:respond("No tracks found.", { ephemeral = true }) end
      player.queue:add(tracks)
      if not player.playing and not player.paused then player:play() end
      ctx:respond("Queued: **" .. (tracks[1].info.title or "track") .. "**")
    end,
  })
  bot:slash_command("search", {
    description = "Show the first five search results",
    options = {
      { name = "query", type = discord.enums.OPTION_TYPE.STRING, description = "Search words", required = true },
    },
    callback = function(ctx)
      local manager = helpers.manager(ctx)
      if not manager then return ctx:respond("Lavalink is still connecting. Try again in a moment.", { ephemeral = true }) end
      local ok, result = pcall(manager.search, manager, ctx:require_arg("query"))
      if not ok then return ctx:respond("Lavalink could not search: " .. tostring(result), { ephemeral = true }) end
      local tracks = lavalinklua.utils.splitSearchResult(result.loadType, result)
      if #tracks == 0 then return ctx:respond("No tracks found.", { ephemeral = true }) end

      local lines = { "**Search results:**" }
      for i = 1, math.min(#tracks, 5) do
        local info = tracks[i].info or {}
        table.insert(lines, string.format("%d. **%s** — %s", i, info.title or "Unknown", info.author or "Unknown"))
      end
      ctx:respond(table.concat(lines, "\n"), { ephemeral = true })
    end,
  })
end
