local json          = require("json")
local LavalinkManager = require("../libs/LavalinkManager")

local function snowflakeShift22(id)
  local digits = { 0 }
  for i = 1, #id do
    local carry = tonumber(id:sub(i, i))
    for j = 1, #digits do
      local val = digits[j] * 10 + carry
      digits[j] = val % (2^22)
      carry = math.floor(val / (2^22))
    end
    while carry > 0 do
      digits[#digits + 1] = carry % (2^22)
      carry = math.floor(carry / (2^22))
    end
  end
  local result = 0
  for j = #digits, 1, -1 do
    result = result * (2^22) + digits[j]
  end
  return math.floor(result / (2^22))
end

local function createDiscordiaIntegration(client, lavalinkOptions)
  assert(client,         "[discordia] client required")
  assert(lavalinkOptions,"[discordia] lavalinkOptions required")

  lavalinkOptions.clientId = lavalinkOptions.clientId
    or (client.user and client.user.id)
    or error("[discordia] clientId required")

  lavalinkOptions.sendPayload = lavalinkOptions.sendPayload or function(guildId, payload)
    local shards = client._shards
    if not shards then
      error("[discordia] client._shards not found")
    end

    local numShards = 0
    for _ in pairs(shards) do numShards = numShards + 1 end

    local shardId = numShards > 1
      and (snowflakeShift22(tostring(guildId)) % numShards)
      or  0

    local shard = shards[shardId]
    if not shard then
      error("[discordia] shard " .. shardId .. " not found")
    end

    local d = payload.d or {}
    shard:_send(payload.op, {
      guild_id   = d.guild_id,
      channel_id = d.channel_id ~= nil and d.channel_id or json.null,
      self_mute  = d.self_mute  or false,
      self_deaf  = d.self_deaf  or false,
    })
  end

  local manager = LavalinkManager.new(lavalinkOptions)

  client:on("raw", function(str)
    local ok, packet = pcall(json.decode, str)
    if not ok or not packet then return end

    local t = packet.t
    if t ~= "VOICE_STATE_UPDATE" and t ~= "VOICE_SERVER_UPDATE" then return end

    manager:handleVoiceUpdate({ t = t, d = packet.d })
  end)

  return manager
end

return createDiscordiaIntegration
