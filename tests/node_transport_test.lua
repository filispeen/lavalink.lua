-- Node option/transport unit test with mocked HTTP, WebSocket and libuv.
-- Run: luvit tests/node_transport_test.lua

local events, requests, timers = {}, {}, {}

package.loaded["json"] = {
  encode = function() return "{}" end,
  decode = function(raw)
    if raw == "{\"loadType\":\"empty\",\"data\":{}}" then return { loadType = "empty", data = {} } end
    error("unexpected JSON fixture: " .. tostring(raw))
  end,
  null = {},
}

package.loaded["coro-http"] = {
  request = function(method, url, headers, body)
    requests[#requests + 1] = { method = method, url = url, headers = headers, body = body }
    return { code = 200 }, '{"loadType":"empty","data":{}}'
  end,
}
package.loaded["./utils"] = assert(loadfile("libs/utils.lua"))()
package.loaded["./Emitter"] = assert(loadfile("libs/Emitter.lua"))()
package.loaded["./RestHandler"] = assert(loadfile("libs/RestHandler.lua"))()

package.loaded["coro-websocket"] = {
  connect = function() error("offline") end,
}
package.loaded["uv"] = {
  new_timer = function()
    local timer = { closed = false }
    function timer:start(delay, _repeat, callback)
      timers[#timers + 1] = { delay = delay, callback = callback, timer = timer }
    end
    function timer:stop() end
    function timer:close() self.closed = true end
    return timer
  end,
  timer_start = function(timer, delay, repeat_interval, callback)
    timer:start(delay, repeat_interval, callback)
  end,
  timer_stop = function(timer) timer:stop() end,
  close = function(timer) timer:close() end,
  is_closing = function(timer) return timer.closed end,
}

local Node = assert(loadfile("libs/Node.lua"))()
local manager = {
  options = { clientId = "bot", clientName = "test", shards = 1 },
  emit = function(_self, event, ...)
    events[#events + 1] = { event, ... }
  end,
}

local node = Node.new(manager, {
  url = "https://music.example:8443",
  password = "secret",
  reconnectTries = 1,
  reconnectDelay = 25,
})
assert(node.options.host == "music.example")
assert(node.options.port == 8443)
assert(node.options.secure == true)
assert(node.options.authorization == "secret")

assert(node.rest:loadTracks("https://example.org/audio.mp3").loadType == "empty")
assert(requests[1].url:find("/v4/loadtracks", 1, true))

node:connect()
assert(events[1][1] == "nodeError")
assert(events[2][1] == "nodeReconnecting")
assert(timers[1].delay == 25)

node:disconnect("test complete")
assert(node._manualDisconnect == true)
print("node transport mock test: OK")
