local json    = require("json")
local uv      = require("uv")
local coroWs  = require("coro-websocket")
local RestHandler = require("./RestHandler")
local Emitter = require("./Emitter")

local Node = setmetatable({}, { __index = Emitter })
Node.__index = Node

function Node.new(manager, options)
  local self = setmetatable(Emitter.new(), Node)

  self.manager = manager
  self.options = {
    host           = options.host or "localhost",
    port           = options.port or 2333,
    authorization  = options.authorization or "youshallnotpass",
    secure         = options.secure or false,
    id             = options.id or (options.host .. ":" .. tostring(options.port or 2333)),
    sessionId      = options.sessionId or nil,
    resuming       = options.resuming ~= false,
    resumeTimeout  = options.resumeTimeout or 60,
    reconnectTries = options.reconnectTries or 5,
    reconnectDelay = options.reconnectDelay or 5000,
    regions        = options.regions or {},
  }

  self.sessionId          = nil
  self.connected          = false
  self.ready              = false
  self._reconnectAttempts = 0
  self._wsRead            = nil
  self._wsWrite           = nil
  self._reconnectTimer    = nil
  self.stats = {
    players = 0, playingPlayers = 0, uptime = 0,
    memory = {}, cpu = {}, frameStats = nil,
  }
  self.info = nil
  self.rest = RestHandler.new(self)

  return self
end

function Node:connect()
  self:_clearReconnectTimer()

  coroutine.wrap(function()
    local wsOptions = {
      host     = self.options.host,
      port     = self.options.port,
      tls      = self.options.secure,
      pathname = "/v4/websocket",
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
    self:_scheduleReconnect()
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
  local player = self.manager.players[data.guildId]
  if not player then return end

  local t = data.type
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
  self.connected = false
  self.ready     = false
  self:_clearReconnectTimer()
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
  local delay = self.options.reconnectDelay
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
  return self.stats.cpu and self.stats.cpu.lavalinkLoad or 0
end

return Node
