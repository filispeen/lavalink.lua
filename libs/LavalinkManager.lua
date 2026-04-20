local json    = require("json")
local Emitter = require("./Emitter")
local Node    = require("./Node")
local Player  = require("./Player")

local NULL = json.null

local function isNull(v)
  return v == nil or v == NULL
end

local LavalinkManager = setmetatable({}, { __index = Emitter })
LavalinkManager.__index = LavalinkManager

local REGION_MAP = {
  us_central  = { "us-central", "us", "us-central1" },
  us_east     = { "us-east", "us-east1" },
  us_west     = { "us-west", "us-west1" },
  us_south    = { "us-south" },
  europe      = { "eu-west", "eu-central", "europe" },
  singapore   = { "singapore", "asia" },
  japan       = { "japan", "tokyo" },
  brazil      = { "brazil" },
  sydney      = { "sydney", "oceania" },
  hongkong    = { "hongkong", "asia" },
  russia      = { "russia" },
  southafrica = { "southafrica" },
  india       = { "india" },
}

function LavalinkManager.new(options)
  assert(options,                              "[LavalinkManager] options required")
  assert(options.nodes and #options.nodes > 0, "[LavalinkManager] at least one node required")
  assert(options.sendPayload,                  "[LavalinkManager] sendPayload(guildId, payload) required")
  assert(options.clientId,                     "[LavalinkManager] clientId required")

  local self = setmetatable(Emitter.new(), LavalinkManager)

  self.options = {
    clientId    = tostring(options.clientId),
    clientName  = options.clientName  or "lavalink-lua/1.0",
    shards      = options.shards      or 1,
    sendPayload = options.sendPayload,
    autoSkip    = options.autoSkip ~= false,
    playerOptions = options.playerOptions or { defaultVolume = 100 },
    nodeOptions   = options.nodeOptions   or {},
  }

  self.nodes   = {}
  self.players = {}

  for _, nodeOpts in ipairs(options.nodes) do
    self:addNode(nodeOpts)
  end

  return self
end

function LavalinkManager:addNode(options)
  local merged = {}
  for k, v in pairs(self.options.nodeOptions) do merged[k] = v end
  for k, v in pairs(options)                  do merged[k] = v end
  local node = Node.new(self, merged)
  self.nodes[node.options.id] = node
  return node
end

function LavalinkManager:removeNode(id)
  local node = self.nodes[id]
  if not node then return end
  node:disconnect("removed")
  self.nodes[id] = nil
end

function LavalinkManager:init()
  for _, node in pairs(self.nodes) do
    node:connect()
  end
end

function LavalinkManager:getNode(id)
  if id then
    local node = self.nodes[id]
    if not node then error("[LavalinkManager] Node '" .. id .. "' not found") end
    return node
  end
  return self:_leastLoadedNode()
end

function LavalinkManager:_leastLoadedNode(region)
  local candidates = {}

  for _, node in pairs(self.nodes) do
    if node:isUsable() then
      if region then
        for _, r in ipairs(node.options.regions or {}) do
          if r:lower():find(region:lower(), 1, true) then
            table.insert(candidates, node)
            break
          end
        end
      else
        table.insert(candidates, node)
      end
    end
  end

  if #candidates == 0 then
    if region then return self:_leastLoadedNode(nil) end
    error("[LavalinkManager] No usable nodes available")
  end

  table.sort(candidates, function(a, b)
    local loadA = a:getCpuLoad() + (a:getPlayersCount() * 0.001)
    local loadB = b:getCpuLoad() + (b:getPlayersCount() * 0.001)
    return loadA < loadB
  end)

  return candidates[1]
end

function LavalinkManager:createPlayer(options)
  assert(options.guildId, "[LavalinkManager] guildId required")

  if self.players[options.guildId] then
    return self.players[options.guildId], false
  end

  local node = options.node
    and self:getNode(options.node)
    or  self:_leastLoadedNode(options.region)

  local defaultVol = self.options.playerOptions.defaultVolume or 100
  local player = Player.new(self, {
    guildId        = options.guildId,
    voiceChannelId = options.voiceChannelId,
    textChannelId  = options.textChannelId,
    selfDeaf       = options.selfDeaf ~= false,
    selfMute       = options.selfMute or false,
    node           = node,
    volume         = options.volume or defaultVol,
  })

  self.players[options.guildId] = player
  self:emit("playerCreate", player)
  return player, true
end

function LavalinkManager:getPlayer(guildId)
  return self.players[guildId]
end

function LavalinkManager:destroyPlayer(guildId, reason)
  local player = self.players[guildId]
  if player then player:destroy(reason) end
end

function LavalinkManager:sendPayload(guildId, payload)
  self.options.sendPayload(guildId, payload)
end

function LavalinkManager:handleVoiceUpdate(packet)
  if not packet or not packet.d then return end
  local d = packet.d
  local t = packet.t

  if t == "VOICE_STATE_UPDATE" then
    if tostring(d.user_id) ~= self.options.clientId then return end

    local player = self.players[d.guild_id]
    if not player then return end

    if isNull(d.channel_id) then
      player.state      = "DISCONNECTED"
      player.voiceState = {}
      player.voiceChannelId = nil
    else
      player.voiceState.sessionId = d.session_id
      player.voiceChannelId       = d.channel_id
      player:_sendVoiceUpdate()
    end

  elseif t == "VOICE_SERVER_UPDATE" then
    local player = self.players[d.guild_id]
    if not player then return end

    player.voiceState.token    = d.token
    player.voiceState.endpoint = d.endpoint
    player:_sendVoiceUpdate()
  end
end

function LavalinkManager:search(query, options)
  options = options or {}
  local node = options.node
    and self:getNode(options.node)
    or  self:_leastLoadedNode()

  local source     = options.source or "ytsearch"
  local identifier = query:match("^https?://") and query or (source .. ":" .. query)

  local ok, result = pcall(node.rest.loadTracks, node.rest, identifier)
  if not ok then
    error("[LavalinkManager] search failed: " .. tostring(result))
  end
  return result
end

function LavalinkManager:decodeTrack(encoded, nodeId)
  local node = nodeId and self:getNode(nodeId) or self:_leastLoadedNode()
  return node.rest:decodeTrack(encoded)
end

function LavalinkManager:decodeTracks(encodedList, nodeId)
  local node = nodeId and self:getNode(nodeId) or self:_leastLoadedNode()
  return node.rest:decodeTracks(encodedList)
end

function LavalinkManager:getUsableNodes()
  local list = {}
  for _, node in pairs(self.nodes) do
    if node:isUsable() then table.insert(list, node) end
  end
  return list
end

function LavalinkManager:getAllNodes()
  local list = {}
  for _, node in pairs(self.nodes) do
    table.insert(list, node)
  end
  return list
end

return LavalinkManager
