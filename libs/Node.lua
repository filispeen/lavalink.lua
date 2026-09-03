local json    = require("json")
local uv      = require("uv")
local coroWs  = require("coro-websocket")
local RestHandler = require("./RestHandler")
local Emitter = require("./Emitter")

local Node = setmetatable({}, { __index = Emitter })
Node.__index = Node

local function parseUrl(url)
  local scheme, host, port = tostring(url):match("^(https?)://([^:/]+):?(%d*)/?")
  if not scheme then
    error("[Node] url must be an http:// or https:// Lavalink URL")
  end
  return host, tonumber(port) or (scheme == "https" and 443 or 80), scheme == "https"
end

function Node.new(manager, options)
  local urlHost, urlPort, urlSecure
  if options.url then
    urlHost, urlPort, urlSecure = parseUrl(options.url)
  end
  local host = options.host or urlHost or "localhost"
  local port = options.port or urlPort or 2333
  local apiVersion = tonumber(options.apiVersion or manager.options.apiVersion or 4)
  assert(apiVersion == 3 or apiVersion == 4,
    "[Node] apiVersion must be 3 or 4")
  local self = setmetatable(Emitter.new(), Node)

  self.manager = manager
  self.options = {
    host           = host,
    port           = port,
    authorization  = options.authorization or options.password or "youshallnotpass",
    secure         = options.secure == true or urlSecure == true,
    id             = options.id or (host .. ":" .. tostring(port)),
    sessionId      = options.sessionId or nil,
    resuming       = options.resuming ~= false,
    resumeTimeout  = options.resumeTimeout or 60,
    reconnectTries = options.reconnectTries or 5,
    reconnectDelay = options.reconnectDelay or 5000,
    regions        = options.regions or {},
    apiVersion     = apiVersion,
  }

  self.sessionId          = options.sessionId or nil
  self.connected          = false
  self.ready              = false
  self._reconnectAttempts = 0
  self._wsRead            = nil
  self._wsWrite           = nil
  self._reconnectTimer    = nil
  self._manualDisconnect  = false
  self.stats = {
    players = 0, playingPlayers = 0, uptime = 0,
    memory = {}, cpu = {}, frameStats = nil,
  }
  self.info = nil
  self.isNodeLink = false
  self._voiceReceivers = {}
  self.rest = RestHandler.new(self)

  return self
end

function Node:connect()
  self:_clearReconnectTimer()
  self._manualDisconnect = false

  coroutine.wrap(function()
    local wsOptions = {
      host     = self.options.host,
      port     = self.options.port,
      tls      = self.options.secure,
      pathname = "/v" .. self.options.apiVersion .. "/websocket",
      headers  = {
        { "Authorization", self.options.authorization },
        { "Num-Shards",    tostring(self.manager.options.shards or 1) },
        { "User-Id",       tostring(self.manager.options.clientId) },
        { "Client-Name",   self.manager.options.clientName or "lavalink-lua/1.0" },
      },
    }

    if self.options.sessionId and self.options.resuming then
      table.insert(wsOptions.headers, { "Session-Id", self.options.sessionId })
    end

    local ok, res, read, write = pcall(coroWs.connect, wsOptions)

    if not ok then
      self:_onError("WS connect pcall failed: " .. tostring(res))
      self:_scheduleReconnect()
      return
    end

    if not res then
      self:_onError("WS connect failed — node unreachable at " ..
        self.options.host .. ":" .. self.options.port)
      self:_scheduleReconnect()
      return
    end

    self._wsRead            = read
    self._wsWrite           = write
    self.connected          = true
    self._reconnectAttempts = 0

    self.manager:emit("nodeConnect", self)

    local readOk, readErr = pcall(function()
      for msg in read do
        if msg and msg.payload then
          self:_handleMessage(msg.payload)
        end
      end
    end)

    self.connected = false
    self.ready     = false
    self._wsRead   = nil
    self._wsWrite  = nil

    if not readOk then
      self:_onError("WS read loop error: " .. tostring(readErr))
    end

    self.manager:emit("nodeDisconnect", self)
    if not self._manualDisconnect then
      self:_scheduleReconnect()
    end
  end)()
end

function Node:_handleMessage(raw)
  local data, err = json.decode(raw)
  if not data then
    self:_onError("JSON decode error: " .. tostring(err))
    return
  end

  local op = data.op

  if op == "ready" then
    self.sessionId          = data.sessionId
    self.ready              = true
    self.options.sessionId  = data.sessionId

    if self.options.resuming then
      local ok, e = pcall(self.rest.updateSession, self.rest,
        true, self.options.resumeTimeout)
      if not ok then self:_onError("updateSession failed: " .. tostring(e)) end
    end

    self.manager:emit("nodeReady", self, data.resumed, data.sessionId)

    -- /info is part of Lavalink v4, and NodeLink identifies itself with an
    -- isNodelink flag.  Detection is best-effort so a server with a restricted
    -- info endpoint remains usable as a normal Lavalink node.
    coroutine.wrap(function()
      local ok, info = pcall(self.refreshInfo, self)
      if not ok then self.manager:emit("nodeInfoError", self, info) end
    end)()

  elseif op == "playerUpdate" then
    local player = self.manager.players[data.guildId]
    if player then player:_handlePlayerUpdate(data.state) end

  elseif op == "stats" then
    self.stats = {
      players        = data.players,
      playingPlayers = data.playingPlayers,
      uptime         = data.uptime,
      memory         = data.memory,
      cpu            = data.cpu,
      frameStats     = data.frameStats,
    }
    self.manager:emit("nodeStats", self, self.stats)

  elseif op == "event" then
    self:_handleEvent(data)

  else
    self.manager:emit("nodeUnknownMessage", self, data)
  end
end

function Node:_handleEvent(data)
  -- Lavalink 3.7+ sends encodedTrack instead of the v4 Track object in
  -- websocket events.  Keep the public event shape stable for callers.
  if not data.track and data.encodedTrack then
    data.track = { encoded = data.encodedTrack }
  elseif type(data.track) == "string" then
    data.track = { encoded = data.track }
  end
  local t = data.type
  if t == "WorkerFailedEvent" then
    self.manager:emit("nodeLinkWorkerFailed", self, data.affectedGuilds or {}, data.message, data)
    return
  end

  local player = self.manager.players[data.guildId]
  if not player then
    self.manager:emit("nodeLinkEvent", self, nil, data)
    return
  end

  -- v3 events contain only the encoded track.  Retain metadata resolved by
  -- loadtracks when it is the same currently queued track.
  if data.track and not data.track.info and player.queue and player.queue.current
    and player.queue.current.encoded == data.track.encoded then
    data.track = player.queue.current
  end

  if t == "TrackStartEvent" then
    player:_handleTrackStart(data.track)
  elseif t == "TrackEndEvent" then
    player:_handleTrackEnd(data.track, data.reason)
  elseif t == "TrackExceptionEvent" then
    player:_handleTrackException(data.track, data.exception)
  elseif t == "TrackStuckEvent" then
    player:_handleTrackStuck(data.track, data.thresholdMs)
  elseif t == "WebSocketClosedEvent" then
    player:_handleWebSocketClosed(data.code, data.reason, data.byRemote)
  elseif t == "SponsorBlockSegmentsLoadedEvent" then
    self.manager:emit("sponsorBlockSegmentsLoaded", player, data.segments or {}, data)
  elseif t == "SponsorBlockSegmentSkippedEvent" then
    self.manager:emit("sponsorBlockSegmentSkipped", player, data.segment, data)
  elseif t == "MixStartedEvent" then
    self.manager:emit("mixStart", player, data)
  elseif t == "MixEndedEvent" then
    self.manager:emit("mixEnd", player, data)
  elseif t == "LyricsFoundEvent" then
    self.manager:emit("lyricsFound", player, data.lyrics, data)
  elseif t == "LyricsLineEvent" then
    self.manager:emit("lyricsLine", player, data.lineIndex, data)
  elseif t == "StreamMetadataEvent" then
    self.manager:emit("streamMetadata", player, data.stream, data)
  else
    -- Preserve every future NodeLink event even if this version does not yet
    -- expose a convenience event name for it.
    self.manager:emit("nodeLinkEvent", self, player, data)
  end
end

function Node:send(payload)
  if not self._wsWrite then
    error("[Node:" .. self.options.id .. "] Cannot send — not connected")
  end
  local ok, err = pcall(self._wsWrite, { payload = json.encode(payload) })
  if not ok then self:_onError("WS send failed: " .. tostring(err)) end
end

function Node:disconnect(reason)
  self._manualDisconnect = true
  self.connected = false
  self.ready     = false
  self:_clearReconnectTimer()
  for guildId in pairs(self._voiceReceivers) do
    self:stopVoiceReceive(guildId)
  end
  if self._wsWrite then
    pcall(self._wsWrite, false)
    self._wsWrite = nil
    self._wsRead  = nil
  end
  self.manager:emit("nodeDisconnect", self, reason)
end

function Node:_scheduleReconnect()
  if self._reconnectAttempts >= self.options.reconnectTries then
    self.manager:emit("nodeError", self,
      "[Node:" .. self.options.id .. "] Max reconnect attempts reached")
    return
  end
  self._reconnectAttempts = self._reconnectAttempts + 1
  local delay = math.min(
    self.options.reconnectDelay * (2 ^ (self._reconnectAttempts - 1)),
    60000
  )
  self.manager:emit("nodeReconnecting", self, self._reconnectAttempts, delay)

  local timer = uv.new_timer()
  self._reconnectTimer = timer
  uv.timer_start(timer, delay, 0, function()
    uv.timer_stop(timer)
    uv.close(timer)
    self._reconnectTimer = nil
    self:connect()
  end)
end

function Node:_clearReconnectTimer()
  if self._reconnectTimer then
    if not uv.is_closing(self._reconnectTimer) then
      uv.timer_stop(self._reconnectTimer)
      uv.close(self._reconnectTimer)
    end
    self._reconnectTimer = nil
  end
end

function Node:_onError(msg)
  self.manager:emit("nodeError", self, msg)
end

function Node:isUsable()
  return self.connected and self.ready
end

function Node:getPlayersCount()
  return self.stats.players or 0
end

function Node:getCpuLoad()
  local cpu = self.stats.cpu or {}
  return cpu.lavalinkLoad or cpu.processLoad or 0
end

function Node:refreshInfo()
  local info = self.rest:getInfo()
  self.info = info
  self.isNodeLink = self.options.apiVersion == 4
    and info and info.isNodelink == true or false
  self.manager:emit("nodeInfo", self, info)
  if self.isNodeLink then self.manager:emit("nodeLinkReady", self, info) end
  return info
end

function Node:_voiceReceiverHeaders()
  return {
    { "Authorization", self.options.authorization },
    { "User-Id", tostring(self.manager.options.clientId) },
    { "Client-Name", self.manager.options.clientName or "lavalink-lua/1.0" },
  }
end

-- Opens NodeLink's experimental receive-only voice stream.  Frames are passed
-- through unchanged: depending on the NodeLink configuration they are Opus or
-- PCM S16LE binary payloads.
function Node:startVoiceReceive(guildId, onFrame)
  assert(self.options.apiVersion == 4,
    "[Node] voice receive is a NodeLink v4 API feature")
  assert(guildId, "[Node] guildId required for voice receive")
  assert(type(onFrame) == "function", "[Node] onFrame callback required")
  self:stopVoiceReceive(guildId)

  local receiver = { guildId = tostring(guildId), write = nil, active = true }
  self._voiceReceivers[receiver.guildId] = receiver

  coroutine.wrap(function()
    local wsOptions = {
      host = self.options.host,
      port = self.options.port,
      tls = self.options.secure,
      pathname = "/v4/websocket/voice/" .. receiver.guildId,
      headers = self:_voiceReceiverHeaders(),
    }
    local ok, res, read, write = pcall(coroWs.connect, wsOptions)
    if not ok or not res then
      receiver.active = false
      self._voiceReceivers[receiver.guildId] = nil
      self.manager:emit("voiceReceiveError", self, receiver.guildId,
        ok and "WS connect failed" or tostring(res))
      return
    end

    receiver.write = write
    self.manager:emit("voiceReceiveConnect", self, receiver.guildId)
    local readOk, readErr = pcall(function()
      for msg in read do
        if receiver.active and msg and msg.payload then
          onFrame(receiver.guildId, msg.payload, msg)
          self.manager:emit("voiceReceiveFrame", self, receiver.guildId, msg.payload, msg)
        end
      end
    end)
    receiver.active = false
    if self._voiceReceivers[receiver.guildId] == receiver then
      self._voiceReceivers[receiver.guildId] = nil
    end
    if not readOk then
      self.manager:emit("voiceReceiveError", self, receiver.guildId, tostring(readErr))
    end
    self.manager:emit("voiceReceiveDisconnect", self, receiver.guildId)
  end)()

  return receiver
end

function Node:stopVoiceReceive(guildId)
  local key = tostring(guildId)
  local receiver = self._voiceReceivers[key]
  if not receiver then return false end
  receiver.active = false
  self._voiceReceivers[key] = nil
  if receiver.write then pcall(receiver.write, false) end
  return true
end

return Node
