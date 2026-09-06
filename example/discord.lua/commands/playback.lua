local helpers = require("./helpers")

return function(bot, discord)
  local function player_action(name, description, action, message)
    bot:slash_command(name, {
      description = description,
      callback = function(ctx)
        local player, error_message = helpers.player(ctx)
        if not player then return ctx:respond(error_message, { ephemeral = true }) end
        action(player)
        ctx:respond(message)
      end,
    })
  end

  player_action("pause", "Pause playback", function(player) player:pause(true) end, "Paused.")
  player_action("resume", "Resume playback", function(player) player:resume() end, "Resumed.")
  player_action("stop", "Stop and clear the queue", function(player) player:stopPlaying(true) end, "Stopped and cleared the queue.")
  player_action("leave", "Leave voice", function(player) player:destroy("slash leave") end, "Left voice.")

  bot:slash_command("volume", {
    description = "Set volume (0 to 1000)",
    options = {
      { name = "value", type = discord.enums.OPTION_TYPE.INTEGER, description = "New volume", required = true },
    },
    callback = function(ctx)
      local player, error_message = helpers.player(ctx)
      if not player then return ctx:respond(error_message, { ephemeral = true }) end
      player:setVolume(ctx:require_arg("value"))
      ctx:respond("Volume set to " .. tostring(player.volume) .. ".")
    end,
  })
  bot:slash_command("filter", {
    description = "Set an audio filter or reset filters",
    options = {
      { name = "name", type = discord.enums.OPTION_TYPE.STRING, description = "nightcore, vaporwave, 8d, bassboost, or reset", required = true },
    },
    callback = function(ctx)
      local player, error_message = helpers.player(ctx)
      if not player then return ctx:respond(error_message, { ephemeral = true }) end
      local name = ctx:require_arg("name"):lower()

      if name == "nightcore" then
        player.filters:setTimescale({ speed = 1.3, pitch = 1.3, rate = 1.0 })
      elseif name == "vaporwave" then
        player.filters:setTimescale({ speed = 0.85, pitch = 0.85, rate = 1.0 })
      elseif name == "8d" then
        player.filters:setRotation({ rotationHz = 0.2 })
      elseif name == "bassboost" then
        local bands = {}
        for i = 0, 4 do table.insert(bands, { band = i, gain = 0.35 }) end
        player.filters:setEqualizer(bands)
      elseif name == "reset" then
        player.filters:resetFilters()
      else
        return ctx:respond("Use: `nightcore`, `vaporwave`, `8d`, `bassboost`, or `reset`.", { ephemeral = true })
      end
      ctx:respond("Filter set to **" .. name .. "**.")
    end,
  })
end
