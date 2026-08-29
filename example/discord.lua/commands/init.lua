local modules = {
  require("./join"),
  require("./play"),
  require("./playback"),
}

local M = {}

function M.register(bot, discord)
  for _, register in ipairs(modules) do register(bot, discord) end
end

return M
