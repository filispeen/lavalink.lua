local json          = require("json")
local uv            = require("uv")
local Queue         = require("./Queue")
local FilterManager = require("./FilterManager")

local NULL = json.null

local function isNull(v)
  return v == nil or v == NULL
end

local Player = {}
Player.__index = Player

function Player.new(manager, options)
  local self = setmetatable({}, Player)

  self.manager        = manager
  self.guildId        = options.guildId
  self.voiceChannelId = options.voiceChannelId
  self.textChannelId  = options.textChannelId
  self.selfDeaf       = options.selfDeaf ~= false
  self.selfMute       = options.selfMute or false

  self.node       = options.node
  self.queue      = Queue.new()
  self.filters    = FilterManager.new(self)

  self.paused             = false
  self.playing            = false
  self.volume             = options.volume or 100
  self.position           = 0
  self.lastPositionChange = 0
  self.ping               = { lavalink = 0, discord = 0 }
  self.state              = "DISCONNECTED"
  self.repeatMode         = "off"
  self.voiceState         = {}

  return self
end

function Player:connect()
  if not self.voiceChannelId then
    error("[Player:" .. self.guildId .. "] voiceChannelId not set")
  end
  self.manager:sendPayload(self.guildId, {
    op = 4,
    d  = {
      guild_id   = self.guildId,
      channel_id = self.voiceChannelId,
      self_mute  = self.selfMute,
      self_deaf  = self.selfDeaf,
    },
  })
  self.state = "CONNECTING"
  return self
end

function Player:disconnect(destroyPlayer)
  self.manager:sendPayload(self.guildId, {
    op = 4,
    d  = {
      guild_id   = self.guildId,
      channel_id = NULL,
      self_mute  = false,
      self_deaf  = false,
    },
  })
  self.voiceChannelId = nil
  self.voiceState     = {}
  self.state          = "DISCONNECTED"
  if destroyPlayer then self:destroy("disconnected") end
  return self
end

function Player:destroy(reason)
  if self.node and self.node.sessionId then
    pcall(self.node.rest.destroyPlayer, self.node.rest, self.guildId)
  end
  self.manager.players[self.guildId] = nil
  self.manager:emit("playerDestroy", self, reason or "unknown")
end

function Player:play(options)
  options = options or {}

  if options.track then
    self.queue.current = options.track
  end

  if not self.queue.current then
    local nextTrack = self.queue:advance()
    if not nextTrack then
      self.playing = false
      self.manager:emit("queueEnd", self)
      return self
    end
  end

  local payload = {
    track  = { encoded = self.queue.current.encoded },
    volume = options.volume or self.volume,
    paused = false,
  }

  if options.startTime then payload.position = options.startTime end
  if options.endTime   then payload.endTime   = options.endTime  end
  if options.volume    then self.volume = options.volume         end
  if options.audioTrackId then payload.track.audioTrackId = options.audioTrackId end
  if options.userData then payload.track.userData = options.userData end
  if options.nextTrack then
    payload.nextTrack = type(options.nextTrack) == "string"
      and { encoded = options.nextTrack }
      or options.nextTrack
  end

  if next(self.filters.data) ~= nil then
    payload.filters = self.filters.data
  end

  self.playing = true
  self.paused  = false

  local ok, err = pcall(self.node.rest.updatePlayer, self.node.rest, self.guildId, payload)
  if not ok then self.manager:emit("error", self, err) end

  return self
end

function Player:pause(state)
  if state == nil then state = not self.paused end
  self.paused = state
  local ok, err = pcall(self.node.rest.updatePlayer, self.node.rest,
    self.guildId, { paused = state })
  if not ok then self.manager:emit("error", self, err) end
  self.manager:emit(state and "playerPause" or "playerResume", self)
  return self
end

function Player:resume()
  return self:pause(false)
end

function Player:stop()
  self.playing = false
  local ok, err = pcall(self.node.rest.updatePlayer, self.node.rest,
    self.guildId, { track = { encoded = NULL } })
  if not ok then self.manager:emit("error", self, err) end
  return self
end

function Player:stopPlaying(clearQueue)
  if clearQueue ~= false then self.queue:clear() end
  self.queue.current = nil
  return self:stop()
end

function Player:skip(skipTo, throwError)
  if throwError == nil then throwError = true end
  local skipped = self.queue.current

  if self.repeatMode == "track" then
    self.repeatMode = "off"
  end

  if skipTo and skipTo > 1 then
    self.queue:remove(1, math.min(skipTo - 1, self.queue:size()))
  end

  local nextTrack = self.queue:advance()

  if not nextTrack then
    if throwError then
      error("[Player:" .. self.guildId .. "] No more tracks in queue")
    end
    self.playing       = false
    self.queue.current = nil
    self:stop()
    self.manager:emit("queueEnd", self)
    return skipped
  end

  self:play()
  return skipped
end

function Player:seek(position)
  assert(type(position) == "number" and position >= 0,
    "[Player] seek position must be a non-negative number (ms)")
  local ok, err = pcall(self.node.rest.updatePlayer, self.node.rest,
    self.guildId, { position = math.floor(position) })
  if not ok then self.manager:emit("error", self, err) end
  self.position = position
  return self
end

function Player:setVolume(vol)
  vol = math.max(0, math.min(1000, math.floor(vol)))
  self.volume = vol
  local ok, err = pcall(self.node.rest.updatePlayer, self.node.rest,
    self.guildId, { volume = vol })
  if not ok then self.manager:emit("error", self, err) end
  return self
end

function Player:setRepeatMode(mode)
  assert(mode == "off" or mode == "track" or mode == "queue",
    "[Player] repeatMode must be 'off', 'track', or 'queue'")
  self.repeatMode = mode
  self.manager:emit("playerRepeat", self, mode)
  return self
end

function Player:moveToNode(nodeId)
  local newNode = self.manager:getNode(nodeId)
  if not newNode or not newNode:isUsable() then
    error("[Player] Target node '" .. nodeId .. "' is not usable")
  end
  local oldNode = self.node
  self.node = newNode
  if oldNode and oldNode.sessionId then
    pcall(oldNode.rest.destroyPlayer, oldNode.rest, self.guildId)
  end
  if self.voiceState.token and self.voiceState.endpoint and self.voiceState.sessionId then
    self:_sendVoiceUpdate()
  end
  if self.playing and self.queue.current then
    self:play({ startTime = self.position })
  end
  self.manager:emit("playerMoved", self, oldNode, newNode)
  return self
end

function Player:getPosition()
  if not self.playing then return self.position end
  local elapsed = uv.now() - self.lastPositionChange
  return math.floor(self.position + elapsed)
end

function Player:_sendVoiceUpdate()
  local vs = self.voiceState
  if not vs.sessionId or not vs.token or not vs.endpoint then return end
  if not self.node or not self.node.sessionId then return end
  if not self.voiceChannelId then return end

  local ok, err = pcall(self.node.rest.updatePlayer, self.node.rest, self.guildId, {
    voice = {
      token     = vs.token,
      endpoint  = vs.endpoint,
      sessionId = vs.sessionId,
      channelId = self.voiceChannelId,
    }
  })
  if ok then
    self.state = "CONNECTED"
  else
    self.manager:emit("error", self, err)
  end
end

function Player:_handleTrackStart(track)
  self.playing       = true
  self.paused        = false
  self.queue.current = track
  self.manager:emit("trackStart", self, track)
end

function Player:_handleTrackEnd(track, reason)
  self.manager:emit("trackEnd", self, track, reason)
  if reason == "replaced" or reason == "cleanup" then return end
  if reason == "loadFailed" then
    self.manager:emit("trackError", self, track, "loadFailed")
  end
  if self.repeatMode == "track" and reason ~= "replaced" then
    self:play()
    return
  end
  if self.repeatMode == "queue" and reason ~= "replaced" then
    self.queue:addPrevious(track)
    self.queue:add(track)
  else
    self.queue:addPrevious(track)
  end
  local nextTrack = self.queue:advance()
  if nextTrack then
    self:play()
  else
    self.playing       = false
    self.queue.current = nil
    self.manager:emit("queueEnd", self)
  end
end

function Player:_handleTrackException(track, exception)
  self.manager:emit("trackError", self, track, exception)
end

function Player:_handleTrackStuck(track, threshold)
  self.manager:emit("trackStuck", self, track, threshold)
end

function Player:_handlePlayerUpdate(state)
  if state.position then
    self.position           = state.position
    self.lastPositionChange = uv.now()
  end
  self.ping.lavalink = state.ping or self.ping.lavalink
  self.state         = state.connected and "CONNECTED" or "DISCONNECTED"
  self.manager:emit("playerUpdate", self, state)
end

function Player:_handleWebSocketClosed(code, reason, byRemote)
  self.manager:emit("socketClosed", self, code, reason, byRemote)
end

local function encodedTrack(player)
  local track = player.queue.current
  if not track or not track.encoded then
    error("[Player:" .. player.guildId .. "] no encoded current track")
  end
  return track.encoded
end

-- NodeLink convenience API.  These methods only issue standard HTTP requests;
-- callers may guard them with player.node.isNodeLink when using mixed nodes.
function Player:getLyrics(lang)
  return self.node.rest:getLyrics(encodedTrack(self), lang)
end

function Player:getChapters()
  return self.node.rest:getChapters(encodedTrack(self))
end

function Player:getMeaning(lang)
  return self.node.rest:getMeaning(encodedTrack(self), lang)
end

function Player:subscribeLyrics(skipTrackSource)
  return self.node.rest:subscribeLyrics(self.guildId, skipTrackSource)
end

function Player:unsubscribeLyrics()
  return self.node.rest:unsubscribeLyrics(self.guildId)
end

function Player:getSponsorBlock()
  return self.node.rest:getSponsorBlock(self.guildId)
end

function Player:updateSponsorBlock(data)
  return self.node.rest:updateSponsorBlock(self.guildId, data)
end

function Player:setSponsorBlockSegments(segments)
  return self.node.rest:setSponsorBlockSegments(self.guildId, segments)
end

function Player:clearSponsorBlock()
  return self.node.rest:clearSponsorBlock(self.guildId)
end

function Player:addMix(track, volume, userData)
  local encoded = type(track) == "table" and track.encoded or track
  assert(encoded, "[Player] addMix requires an encoded track or track object")
  return self.node.rest:addMix(self.guildId, {
    track = { encoded = encoded, userData = userData },
    volume = volume,
  })
end

function Player:getMixes()
  return self.node.rest:getMixes(self.guildId)
end

function Player:updateMix(mixId, volume)
  return self.node.rest:updateMix(self.guildId, mixId, { volume = volume })
end

function Player:removeMix(mixId)
  return self.node.rest:removeMix(self.guildId, mixId)
end

function Player:startVoiceReceive(onFrame)
  return self.node:startVoiceReceive(self.guildId, onFrame)
end

function Player:stopVoiceReceive()
  return self.node:stopVoiceReceive(self.guildId)
end

return Player
