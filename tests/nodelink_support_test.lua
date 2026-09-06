-- NodeLink extension transport test with mocked HTTP and WebSocket modules.
-- Run: luvit tests/nodelink_support_test.lua

local requests, events = {}, {}

package.loaded["json"] = {
  encode = function() return "{}" end,
  decode = function() return {} end,
  null = {},
}
package.loaded["coro-http"] = {
  request = function(method, url, headers, body)
    requests[#requests + 1] = { method = method, url = url, headers = headers, body = body }
    return { code = 200 }, "{}"
  end,
}
package.loaded["coro-websocket"] = { connect = function() error("offline") end }
package.loaded["uv"] = {
  new_timer = function() return {} end,
  timer_start = function() end,
  timer_stop = function() end,
  close = function() end,
  is_closing = function() return false end,
}
package.loaded["./utils"] = assert(loadfile("libs/utils.lua"))()
package.loaded["./Emitter"] = assert(loadfile("libs/Emitter.lua"))()
package.loaded["./RestHandler"] = assert(loadfile("libs/RestHandler.lua"))()

local RestHandler = package.loaded["./RestHandler"]
local rest = RestHandler.new({
  options = { host = "node.example", port = 2333, secure = false, authorization = "secret" },
  sessionId = "session",
})

rest:getLyrics("track", "uk")
rest:getChapters("track")
rest:subscribeLyrics("guild", true)
rest:getSponsorBlock("guild")
rest:updateSponsorBlock("guild", { enabled = true })
rest:setSponsorBlockSegments("guild", {})
rest:clearSponsorBlock("guild")
rest:addMix("guild", { track = { encoded = "track" } })
rest:getMixes("guild")
rest:updateMix("guild", "mix", { volume = 0.5 })
rest:removeMix("guild", "mix")

local paths = {}
for _, request in ipairs(requests) do paths[#paths + 1] = request.url end
local joined = table.concat(paths, "\n")
assert(joined:find("/v4/loadlyrics"))
assert(joined:find("/v4/loadchapters"))
assert(joined:find("/v4/sessions/session/players/guild/lyrics/subscribe"))
assert(joined:find("/v4/sessions/session/players/guild/sponsorblock"))
assert(joined:find("/v4/sessions/session/players/guild/mix"))
assert(joined:find("/v4/sessions/session/players/guild/mix/mix"))

local Node = assert(loadfile("libs/Node.lua"))()
local manager = {
  options = { clientId = "123456789012345678", clientName = "test" },
  players = { guild = {} },
  emit = function(_, name, ...) events[#events + 1] = { name, ... } end,
}
local node = Node.new(manager, { host = "localhost" })
node.stats = { cpu = { processLoad = 0.42 } }
assert(node:getCpuLoad() == 0.42)
node:_handleEvent({ type = "SponsorBlockSegmentSkippedEvent", guildId = "guild", segment = {} })
node:_handleEvent({ type = "WorkerFailedEvent", affectedGuilds = { "guild" }, message = "worker died" })
assert(events[1][1] == "sponsorBlockSegmentSkipped")
assert(events[2][1] == "nodeLinkWorkerFailed")

package.loaded["./Queue"] = assert(loadfile("libs/Queue.lua"))()
package.loaded["./FilterManager"] = assert(loadfile("libs/FilterManager.lua"))()
local Player = assert(loadfile("libs/Player.lua"))()
local playerRequest
local player = Player.new({
  emit = function() end,
  players = {},
}, {
  guildId = "guild",
  node = { sessionId = "session", rest = {
    updatePlayer = function(_, _, payload) playerRequest = payload end,
  } },
})
player.queue.current = { encoded = "track" }
player:play({ audioTrackId = "en.4", nextTrack = "next" })
assert(playerRequest.track.audioTrackId == "en.4")
assert(playerRequest.nextTrack.encoded == "next")
player.filters:setEcho({ delay = 500 })
player.filters:setChorus({ rate = 1 })
player.filters:setCompressor({ ratio = 2 })
player.filters:setHighPass({ smoothing = 2 })
player.filters:setPhaser({ stages = 4 })
player.filters:setSpatial({ width = 0.5 })
assert(player.filters.data.echo.delay == 500)
assert(player.filters.data.spatial.width == 0.5)

player.filters:resetFilters()
assert(playerRequest.filters.echo == package.loaded["json"].null)
assert(playerRequest.filters.timescale == package.loaded["json"].null)
player.filters:setTimescale({ speed = 1.2 })
player.filters:resetFilter("timescale")
assert(playerRequest.filters.timescale == package.loaded["json"].null)

package.loaded["./Node"] = {}
package.loaded["./Player"] = {}
local LavalinkManager = assert(loadfile("libs/LavalinkManager.lua"))()
local identifier
local searchManager = setmetatable({
  nodes = { main = { rest = { loadTracks = function(_, value) identifier = value end } } },
}, { __index = LavalinkManager })
searchManager:search("lofi hip-hop", { node = "main" })
assert(identifier == "ytsearch:lofi hip-hop")

print("NodeLink extension transport test: OK")
