return {
  name = "filispeen/lavalink.lua",
  version = "0.2.6",
  description = "Feature-rich Lavalink v4 client for Luvit (Lua)",
  tags = { "lavalink", "discord", "music", "audio", "luvit" },
  license = "MIT",
  author = { name = "filispeen" },
  homepage = "https://github.com/filispeen/lavalink.lua",
  dependencies = {
    "luvit/coro-http@3.2.3",
    "luvit/coro-websocket@3.1.1",
    "luvit/json@2.5.2",
  },
  files = {
    "init.lua",
    "libs/**.lua",
    "integrations/**.lua",
    "README.md",
    "package.lua",
  },
}
