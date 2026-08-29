local helpers = require("./helpers")

return function(bot)
  bot:slash_command("join", {
    description = "Join your voice channel",
    callback = function(ctx)
      local player, created_or_error = helpers.join(ctx)
      if not player then return ctx:respond(created_or_error, { ephemeral = true }) end
      ctx:respond(created_or_error and "Joining your voice channel." or "I am already connected.")
    end,
  })
end
