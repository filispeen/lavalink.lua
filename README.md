# lavalink-lua

A feature-rich Lavalink v4 client for [Luvit](https://luvit.io/) Lua discord bots.

Modelled after [Tomato6966/lavalink-client](https://github.com/Tomato6966/lavalink-client).

---

## Requirements

- [Luvit](https://luvit.io/) runtime
- [Lit](https://luvit.io/lit.html) package manager
- Lavalink v4 server running

---

## Installation

```bash
lit install luvit/coro-http
lit install luvit/coro-websocket
lit install luvit/json
lit install luvit/timer
lit install luvit/utils
```

For the example bot, also install Discordia:

```bash
lit install SinisterRectus/discordia
```

---

## Project Structure

```
lavalink-lua/
├── init.lua                    -- Public API entry point
├── package.lua                 -- Lit package metadata
├── libs/
│   ├── LavalinkManager.lua     -- Top-level manager (multi-node, players, events)
│   ├── Node.lua                -- WebSocket connection to Lavalink, message dispatch
│   ├── Player.lua              -- Per-guild audio player (play/pause/skip/seek/repeat)
│   ├── Queue.lua               -- Track queue with history, shuffle, splice
│   ├── FilterManager.lua       -- All 10 Lavalink v4 audio filters
│   ├── RestHandler.lua         -- Full Lavalink v4 REST API client
│   ├── Emitter.lua             -- Event emitter (on/once/off/emit)
│   └── utils.lua               -- Utilities (buildQuery, deepCopy, etc.)
├── integrations/
│   └── discordia.lua           -- Discordia library integration shim
└── example/
    ├── bot.lua                 -- Full example bot (Discordia)
    └── commands.lua            -- All music commands
```

---

## Quick Start

```lua
local discordia = require("discordia")
local discordiaIntegration = require("path/to/lavalink-lua/integrations/discordia")

local client = discordia.Client()

client:on("ready", function()
  local lavalink = discordiaIntegration(client, {
    clientId = client.user.id,
    nodes = {
      {
        host          = "localhost",
        port          = 2333,
        authorization = "youshallnotpass",
      }
    },
    sendPayload = function(guildId, payload)
      -- forward to your shard's WS
    end,
  })

  lavalink:on("trackStart", function(player, track)
    print("Now playing: " .. track.info.title)
  end)

  lavalink:on("queueEnd", function(player)
    player:destroy("queue finished")
  end)

  lavalink:init()

  -- In a command handler:
  -- local player, created = lavalink:createPlayer({ guildId = "...", voiceChannelId = "..." })
  -- if created then player:connect() end
  -- local result = lavalink:search("never gonna give you up")
  -- player.queue:add(result.data[1])
  -- player:play()
end)

client:run("Bot TOKEN")
```

---

## Events Reference

### LavalinkManager events

| Event | Arguments | Description |
|-------|-----------|-------------|
| `nodeReady` | `node, resumed, sessionId` | Node WebSocket ready |
| `nodeConnect` | `node` | WebSocket connection opened |
| `nodeDisconnect` | `node, reason` | WebSocket disconnected |
| `nodeReconnecting` | `node, attempt, delayMs` | Reconnect scheduled |
| `nodeError` | `node, error` | Node-level error |
| `nodeStats` | `node, stats` | Periodic server stats |
| `nodeUnknownMessage` | `node, data` | Unknown WebSocket op |
| `playerCreate` | `player` | Player created |
| `playerDestroy` | `player, reason` | Player destroyed |
| `playerUpdate` | `player, state` | Position/ping update (every ~5s) |
| `playerRepeat` | `player, mode` | Repeat mode changed |
| `playerMoved` | `player, oldNode, newNode` | Player moved to new node |
| `playerPause` | `player` | Player paused |
| `playerResume` | `player` | Player resumed |
| `trackStart` | `player, track` | Track began playing |
| `trackEnd` | `player, track, reason` | Track ended |
| `trackError` | `player, track, error` | Track exception/loadFailed |
| `trackStuck` | `player, track, thresholdMs` | Track stuck |
| `queueEnd` | `player` | All tracks played |
| `socketClosed` | `player, code, reason, byRemote` | Discord voice WS closed |
| `error` | `player, error` | Generic player error |

---

## Player API

```lua
player:connect()                          -- Send OP4 to Discord
player:disconnect(destroyPlayer?)         -- Leave voice channel
player:destroy(reason?)                   -- DELETE REST + remove from manager

player:play(options?)                     -- Play current/next track
  -- options: { track, startTime, endTime, volume }
player:pause(state?)                      -- Toggle or set pause
player:resume()                           -- Alias for pause(false)
player:stop()                             -- Stop without clearing queue
player:stopPlaying(clearQueue?)           -- Stop + clear queue

player:skip(skipTo?, throwError?)         -- Skip to Nth track (default 1)
player:seek(positionMs)                   -- Seek to position
player:setVolume(0-1000)                  -- Set volume
player:setRepeatMode("off"|"track"|"queue")

player:getPosition()                      -- Client-side interpolated position
player:moveToNode(nodeId)                 -- Live-migrate to another node

player.queue:add(track|tracks)
player.queue:remove(start, end?)
player.queue:shuffle()
player.queue:clear()
player.queue.current                      -- Current track
player.queue.tracks                       -- Upcoming tracks table
player.queue.previous                     -- History (last 25)

player.filters:setTimescale({ speed, pitch, rate })
player.filters:setEqualizer(bands)        -- bands = [{band=0, gain=0.35}, ...]
player.filters:setRotation({ rotationHz })
player.filters:setKaraoke(options)
player.filters:setTremolo(options)
player.filters:setVibrato(options)
player.filters:setDistortion(options)
player.filters:setChannelMix(options)
player.filters:setLowPass(options)
player.filters:setVolume(multiplier)
player.filters:setPluginFilters(table)
player.filters:resetFilters()
player.filters:resetFilter(name)
```

---

## Example Bot Commands

| Command | Description |
|---------|-------------|
| `!play <query/url>` | Search and play, or add to queue |
| `!skip [n]` | Skip current (or to nth track) |
| `!stop` | Stop and clear queue |
| `!pause` | Toggle pause |
| `!resume` | Resume playback |
| `!queue` | Show current queue |
| `!nowplaying` | Show current track with position |
| `!volume [0-1000]` | Get or set volume |
| `!repeat <off\|track\|queue>` | Set repeat mode |
| `!shuffle` | Shuffle queue |
| `!seek <seconds>` | Seek to position |
| `!filter <name\|reset>` | Apply preset filter |
| `!dc` | Disconnect bot |
| `!nodes` | Show all node statuses |

---

## Running the Example Bot

```bash
export DISCORD_TOKEN="your_token"
export CLIENT_ID="your_client_id"
export LAVALINK_HOST="localhost"
export LAVALINK_PORT="2333"
export LAVALINK_PASS="youshallnotpass"

luvit example/bot.lua
```
