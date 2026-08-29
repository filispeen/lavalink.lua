-- Minimal unit test with mocked discord.lua Bot and LavalinkManager.
-- Run: luvit tests/discord_integration_test.lua

local received = {}
local FakeManager = {}

function FakeManager.new(options)
  return setmetatable({ options = options }, { __index = FakeManager })
end

function FakeManager:handleVoiceUpdate(packet)
  received[#received + 1] = packet
end

package.loaded["../libs/LavalinkManager"] = FakeManager
local integration = assert(loadfile("integrations/discord.lua"))()

local bot = { user = { id = "bot-id" }, listeners = {}, sent = {} }
function bot:on(event, callback)
  self.listeners[event] = callback
end
bot.client = {
  voice_state_update = function(_client, guild_id, channel_id, self_mute, self_deaf)
    bot.sent[#bot.sent + 1] = { guild_id, channel_id, self_mute, self_deaf }
    return true
  end,
}

local manager = integration(bot, { nodes = { { host = "localhost" } } })
assert(manager.options.clientId == "bot-id")

bot.listeners.voice_state_update({ guild_id = "guild", user_id = "bot-id", session_id = "session", channel_id = "voice" })
bot.listeners.voice_server_update({ guild_id = "guild", token = "token", endpoint = "endpoint" })
assert(#received == 2)
assert(received[1].t == "VOICE_STATE_UPDATE")
assert(received[2].t == "VOICE_SERVER_UPDATE")

manager.options.sendPayload("guild", { d = { guild_id = "guild", channel_id = "voice", self_mute = false, self_deaf = true } })
assert(#bot.sent == 1)
assert(bot.sent[1][1] == "guild" and bot.sent[1][2] == "voice" and bot.sent[1][4] == true)

print("discord integration mock test: OK")
