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

-- Same transport as request(), but preserves a non-JSON response.  NodeLink
-- uses this for its optional PCM streaming endpoint.
function RestHandler:requestRaw(method, path, body, query)
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
  return data, res
end

function RestHandler:_sessionPath(guildId, suffix)
  local sessionId = self.node.sessionId
  if not sessionId then error("[RestHandler] Node not ready: no sessionId") end
  local path = string.format("/sessions/%s/players/%s", sessionId, guildId)
  return path .. (suffix or "")
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

-- NodeLink extensions.  They deliberately live alongside the Lavalink v4
-- API: applications can opt into them only after checking node.isNodeLink.
function RestHandler:getConnection()
  return self:request("GET", "/connection")
end

function RestHandler:getWorkers()
  return self:request("GET", "/workers")
end

function RestHandler:patchWorker(data)
  return self:request("PATCH", "/workers", data)
end

function RestHandler:getLyrics(encodedTrack, lang)
  return self:request("GET", "/loadlyrics", nil,
    { encodedTrack = encodedTrack, lang = lang })
end

function RestHandler:getChapters(encodedTrack)
  return self:request("GET", "/loadchapters", nil, { encodedTrack = encodedTrack })
end

function RestHandler:getMeaning(encodedTrack, lang)
  return self:request("GET", "/meaning", nil,
    { encodedTrack = encodedTrack, lang = lang })
end

function RestHandler:getTrackStream(encodedTrack, itag)
  return self:request("GET", "/trackstream", nil,
    { encodedTrack = encodedTrack, itag = itag })
end

function RestHandler:getLoadStream(options)
  assert(options and options.encodedTrack,
    "[RestHandler] getLoadStream options.encodedTrack required")
  local query = {}
  for k, v in pairs(options) do query[k] = v end
  if type(query.filters) == "table" then query.filters = json.encode(query.filters) end
  return self:requestRaw("GET", "/loadstream", nil, query)
end

function RestHandler:postLoadStream(options)
  assert(options and options.encodedTrack,
    "[RestHandler] postLoadStream options.encodedTrack required")
  return self:requestRaw("POST", "/loadstream", options)
end

function RestHandler:getSponsorBlock(guildId)
  return self:request("GET", self:_sessionPath(guildId, "/sponsorblock"))
end

function RestHandler:updateSponsorBlock(guildId, data)
  return self:request("PATCH", self:_sessionPath(guildId, "/sponsorblock"), data)
end

function RestHandler:setSponsorBlockSegments(guildId, segments)
  return self:request("POST", self:_sessionPath(guildId, "/sponsorblock"),
    { segments = segments })
end

function RestHandler:clearSponsorBlock(guildId)
  return self:request("DELETE", self:_sessionPath(guildId, "/sponsorblock"))
end

function RestHandler:subscribeLyrics(guildId, skipTrackSource)
  local query = skipTrackSource and { skipTrackSource = "true" } or nil
  return self:request("POST", self:_sessionPath(guildId, "/lyrics/subscribe"), nil, query)
end

function RestHandler:unsubscribeLyrics(guildId)
  return self:request("DELETE", self:_sessionPath(guildId, "/lyrics/subscribe"))
end

function RestHandler:addMix(guildId, data)
  return self:request("POST", self:_sessionPath(guildId, "/mix"), data)
end

function RestHandler:getMixes(guildId)
  return self:request("GET", self:_sessionPath(guildId, "/mix"))
end

function RestHandler:updateMix(guildId, mixId, data)
  return self:request("PATCH", self:_sessionPath(guildId, "/mix/" .. tostring(mixId)), data)
end

function RestHandler:removeMix(guildId, mixId)
  return self:request("DELETE", self:_sessionPath(guildId, "/mix/" .. tostring(mixId)))
end

return RestHandler
