-- Lavalink 3.7+ transport and response-normalization test.
-- Run: luvit tests/lavalink_v3_transport_test.lua

local requests = {}

package.loaded["json"] = {
  encode = function() return "{}" end,
  decode = function(raw)
    if raw == "V3_TRACK" then
      return {
        loadType = "TRACK_LOADED",
        tracks = { { track = "encoded-v3", info = { title = "V3 track" } } },
      }
    end
    return {}
  end,
  null = {},
}
package.loaded["coro-http"] = {
  request = function(method, url, headers, body)
    requests[#requests + 1] = { method = method, url = url, headers = headers, body = body }
    return { code = 200 }, url:find("/loadtracks", 1, true) and "V3_TRACK" or "{}"
  end,
}
package.loaded["./utils"] = assert(loadfile("libs/utils.lua"))()
package.loaded["./RestHandler"] = assert(loadfile("libs/RestHandler.lua"))()

local RestHandler = package.loaded["./RestHandler"]
local rest = RestHandler.new({
  options = {
    host = "node.example", port = 2333, secure = false,
    authorization = "secret", apiVersion = 3,
  },
  sessionId = "session",
})

local result = rest:loadTracks("ytsearch:v3")
assert(requests[1].url:find("/v3/loadtracks", 1, true))
assert(result.loadType == "track")
assert(result.data.encoded == "encoded-v3")

print("Lavalink v3 transport test: OK")
