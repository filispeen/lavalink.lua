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

function RestHandler:_apiPrefix()
  return "/v" .. tostring(self.node.options.apiVersion or 4)
end

function RestHandler:_requireV4(feature)
  if (self.node.options.apiVersion or 4) ~= 4 then
    error("[RestHandler] " .. feature .. " requires Lavalink API v4")
  end
end

function RestHandler:_headers()
  return {
    { "Authorization", self.node.options.authorization },
    { "Content-Type", "application/json" },
    { "Accept", "application/json" },
  }
end

function RestHandler:request(method, path, body, query)
  local url = self:_baseUrl() .. self:_apiPrefix() .. path .. utils.buildQuery(query)
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
  local url = self:_baseUrl() .. self:_apiPrefix() .. path .. utils.buildQuery(query)
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

local function normalizeV3Track(track)
  if type(track) ~= "table" then return track end
  if not track.encoded and track.track then track.encoded = track.track end
  return track
end

-- https://www.youtube.com/watch?v=4wxQPkzJSv8
local function normalizeV3LoadResult(result)
  if not result or not result.loadType then return result end
  if result.data ~= nil or result.loadType == "empty" or result.loadType == "error" then
    return result
  end

  local tracks = result.tracks or {}
  for _, track in ipairs(tracks) do normalizeV3Track(track) end
  if result.loadType == "TRACK_LOADED" then
    return { loadType = "track", data = tracks[1] }
  elseif result.loadType == "PLAYLIST_LOADED" then
    return { loadType = "playlist", data = {
      info = result.playlistInfo or {}, tracks = tracks,
    } }
  elseif result.loadType == "SEARCH_RESULT" then
    return { loadType = "search", data = tracks }
  elseif result.loadType == "NO_MATCHES" then
    return { loadType = "empty", data = nil }
  elseif result.loadType == "LOAD_FAILED" then
    return { loadType = "error", data = result.exception or result }
  end
  return result
end

function RestHandler:loadTracks(identifier)
  local result = self:request("GET", "/loadtracks", nil, { identifier = identifier })
  if (self.node.options.apiVersion or 4) == 3 then
    return normalizeV3LoadResult(result)
  end
  return result
end

function RestHandler:decodeTrack(encoded)
  return normalizeV3Track(self:request("GET", "/decodetrack", nil,
    { encodedTrack = encoded }))
end

function RestHandler:decodeTracks(encodedList)
  local tracks = self:request("POST", "/decodetracks", encodedList)
  if (self.node.options.apiVersion or 4) == 3 then
    for _, track in ipairs(tracks or {}) do normalizeV3Track(track) end
  end
  return tracks
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
  self:_requireV4("getConnection")
  return self:request("GET", "/connection")
end

function RestHandler:getWorkers()
  self:_requireV4("getWorkers")
  return self:request("GET", "/workers")
end

function RestHandler:patchWorker(data)
  self:_requireV4("patchWorker")
  return self:request("PATCH", "/workers", data)
end

function RestHandler:getLyrics(encodedTrack, lang)
  self:_requireV4("getLyrics")
  return self:request("GET", "/loadlyrics", nil,
    { encodedTrack = encodedTrack, lang = lang })
end

function RestHandler:getChapters(encodedTrack)
  self:_requireV4("getChapters")
  return self:request("GET", "/loadchapters", nil, { encodedTrack = encodedTrack })
end

function RestHandler:getMeaning(encodedTrack, lang)
  self:_requireV4("getMeaning")
  return self:request("GET", "/meaning", nil,
    { encodedTrack = encodedTrack, lang = lang })
end

function RestHandler:getTrackStream(encodedTrack, itag)
  self:_requireV4("getTrackStream")
  return self:request("GET", "/trackstream", nil,
    { encodedTrack = encodedTrack, itag = itag })
end

function RestHandler:getLoadStream(options)
  self:_requireV4("getLoadStream")
  assert(options and options.encodedTrack,
    "[RestHandler] getLoadStream options.encodedTrack required")
  local query = {}
  for k, v in pairs(options) do query[k] = v end
  if type(query.filters) == "table" then query.filters = json.encode(query.filters) end
  return self:requestRaw("GET", "/loadstream", nil, query)
end

function RestHandler:postLoadStream(options)
  self:_requireV4("postLoadStream")
  assert(options and options.encodedTrack,
    "[RestHandler] postLoadStream options.encodedTrack required")
  return self:requestRaw("POST", "/loadstream", options)
end

function RestHandler:getSponsorBlock(guildId)
  self:_requireV4("getSponsorBlock")
  return self:request("GET", self:_sessionPath(guildId, "/sponsorblock"))
end

function RestHandler:updateSponsorBlock(guildId, data)
  self:_requireV4("updateSponsorBlock")
  return self:request("PATCH", self:_sessionPath(guildId, "/sponsorblock"), data)
end

function RestHandler:setSponsorBlockSegments(guildId, segments)
  self:_requireV4("setSponsorBlockSegments")
  return self:request("POST", self:_sessionPath(guildId, "/sponsorblock"),
    { segments = segments })
end

function RestHandler:clearSponsorBlock(guildId)
  self:_requireV4("clearSponsorBlock")
  return self:request("DELETE", self:_sessionPath(guildId, "/sponsorblock"))
end

function RestHandler:subscribeLyrics(guildId, skipTrackSource)
  self:_requireV4("subscribeLyrics")
  local query = skipTrackSource and { skipTrackSource = "true" } or nil
  return self:request("POST", self:_sessionPath(guildId, "/lyrics/subscribe"), nil, query)
end

function RestHandler:unsubscribeLyrics(guildId)
  self:_requireV4("unsubscribeLyrics")
  return self:request("DELETE", self:_sessionPath(guildId, "/lyrics/subscribe"))
end

function RestHandler:addMix(guildId, data)
  self:_requireV4("addMix")
  return self:request("POST", self:_sessionPath(guildId, "/mix"), data)
end

function RestHandler:getMixes(guildId)
  self:_requireV4("getMixes")
  return self:request("GET", self:_sessionPath(guildId, "/mix"))
end

function RestHandler:updateMix(guildId, mixId, data)
  self:_requireV4("updateMix")
  return self:request("PATCH", self:_sessionPath(guildId, "/mix/" .. tostring(mixId)), data)
end

function RestHandler:removeMix(guildId, mixId)
  self:_requireV4("removeMix")
  return self:request("DELETE", self:_sessionPath(guildId, "/mix/" .. tostring(mixId)))
end

return RestHandler
