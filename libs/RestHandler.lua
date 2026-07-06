local json = require("json")
local http = require("coro-http")
local utils = require("./utils")

local RestHandler = {}
RestHandler.__index = RestHandler

function RestHandler.new(node)
  local self = setmetatable({}, RestHandler)
  self.node = node
  return self
end

function RestHandler:_baseUrl()
  local n = self.node
  local scheme = n.options.secure and "https" or "http"
  return string.format("%s://%s:%d", scheme, n.options.host, n.options.port)
end

function RestHandler:_headers()
  return {
    { "Authorization", self.node.options.authorization },
    { "Content-Type", "application/json" },
    { "Accept", "application/json" },
  }
end

function RestHandler:request(method, path, body, query)
  local url = self:_baseUrl() .. "/v4" .. path .. utils.buildQuery(query)
  local headers = self:_headers()
  local bodyStr = body and json.encode(body) or nil

  local ok, res, data = pcall(http.request, method, url, headers, bodyStr)
  if not ok then
    error("[RestHandler] HTTP request failed for " .. url .. ": " .. tostring(res))
  end

  if res.code >= 400 then
    local decoded = data and data ~= "" and json.decode(data)
    error(string.format("[RestHandler] HTTP %d on %s %s: %s",
      res.code, method, url,
      (decoded and decoded.message) or data or "no response body"))
  end

  if res.code == 204 or not data or data == "" then
    return nil
  end

  local decoded, err = json.decode(data)
  if not decoded then
    error("[RestHandler] JSON decode error for " .. url .. ": " .. tostring(err))
  end

  return decoded
end

function RestHandler:loadTracks(identifier)
  return self:request("GET", "/loadtracks", nil, { identifier = identifier })
end

function RestHandler:decodeTrack(encoded)
  return self:request("GET", "/decodetrack", nil, { encodedTrack = encoded })
end

function RestHandler:decodeTracks(encodedList)
  return self:request("POST", "/decodetracks", encodedList)
end

function RestHandler:getPlayers()
  local sessionId = self.node.sessionId
  if not sessionId then error("[RestHandler] Node not ready: no sessionId") end
  return self:request("GET", string.format("/sessions/%s/players", sessionId))
end

function RestHandler:getPlayer(guildId)
  local sessionId = self.node.sessionId
  if not sessionId then error("[RestHandler] Node not ready: no sessionId") end
  return self:request("GET", string.format("/sessions/%s/players/%s", sessionId, guildId))
end

function RestHandler:updatePlayer(guildId, data, noReplace)
  local sessionId = self.node.sessionId
  if not sessionId then error("[RestHandler] Node not ready: no sessionId") end
  local query = noReplace and { noReplace = "true" } or nil
  return self:request("PATCH",
    string.format("/sessions/%s/players/%s", sessionId, guildId),
    data, query)
end

function RestHandler:destroyPlayer(guildId)
  local sessionId = self.node.sessionId
  if not sessionId then error("[RestHandler] Node not ready: no sessionId") end
  return self:request("DELETE",
    string.format("/sessions/%s/players/%s", sessionId, guildId))
end

function RestHandler:updateSession(resuming, timeout)
  local sessionId = self.node.sessionId
  if not sessionId then error("[RestHandler] Node not ready: no sessionId") end
  return self:request("PATCH",
    string.format("/sessions/%s", sessionId),
    { resuming = resuming, timeout = timeout })
end

function RestHandler:getInfo()
  return self:request("GET", "/info")
end

function RestHandler:getStats()
  return self:request("GET", "/stats")
end

function RestHandler:getVersion()
  local url = self:_baseUrl() .. "/version"
  local headers = self:_headers()
  local ok, res, data = pcall(http.request, "GET", url, headers)
  if not ok or res.code ~= 200 then
    return nil
  end
  return data
end

function RestHandler:getRoutePlannerStatus()
  return self:request("GET", "/routeplanner/status")
end

function RestHandler:freeRoutePlannerAddress(address)
  return self:request("POST", "/routeplanner/free/address", { address = address })
end

function RestHandler:freeAllRoutePlannerAddresses()
  return self:request("POST", "/routeplanner/free/all")
end

return RestHandler
