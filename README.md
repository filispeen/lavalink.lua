# lavalink.lua

Feature-rich Lavalink v4 client for [Luvit](https://luvit.io/) (Lua) Discord bots - multi-node support, queue management, audio filters, session resuming and Discordia integration.

---

## Installation

```bash
lit install filispeen/lavalink.lua
```

For the example bot, also install Discordia:

```bash
lit install SinisterRectus/discordia
```

---

## Requirements

- [Luvit](https://luvit.io/) runtime + [Lit](https://luvit.io/lit.html) package manager
- Lavalink v4 server

---

## Project Structure

```
lavalink.lua/
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
│   └── discordia.lua           -- Discordia integration shim
└── example/
    ├── bot.lua                 -- Full example bot (Discordia)
    ├── commands.lua            -- All music commands
    ├── env.lua                 -- .env file loader
    └── .env.example            -- Environment variable template
```

---

## Quick Start

```lua
local discordia   = require("discordia")
local lavalinklua = require("lavalink.lua")

local client = discordia.Client()

client:on("ready", function()
  local lavalink = lavalinklua.discordia(client, {
    clientId = client.user.id,
    nodes = {
      {
        id            = "main",
        host          = "localhost",
        port          = 2333,
        authorization = "youshallnotpass",
      },
    },
  })

  lavalink:on("trackStart", function(player, track)
    print("Now playing: " .. track.info.title)
  end)

  lavalink:on("queueEnd", function(player)
    player:destroy("queue finished")
  end)

  lavalink:init()
end)

client:run("Bot TOKEN")
```

Playing a track:

```lua
local player, created = lavalink:createPlayer({
  guildId        = guildId,
  voiceChannelId = voiceChannelId,
  textChannelId  = textChannelId,
  selfDeaf       = true,
})
if created then player:connect() end

local result = lavalink:search("never gonna give you up")
player.queue:add(result.data[1])
player:play()
```

---

## Events Reference

| Event | Arguments | Description |
|-------|-----------|-------------|
| `nodeReady` | `node, resumed, sessionId` | Node WebSocket ready |
| `nodeConnect` | `node` | WebSocket connection opened |
| `nodeDisconnect` | `node, reason` | WebSocket disconnected |
| `nodeReconnecting` | `node, attempt, delayMs` | Reconnect scheduled |
| `nodeError` | `node, error` | Node-level error |
| `nodeStats` | `node, stats` | Periodic server stats |
| `playerCreate` | `player` | Player created |
| `playerDestroy` | `player, reason` | Player destroyed |
| `playerUpdate` | `player, state` | Position/ping update |
| `playerPause` | `player` | Player paused |
| `playerResume` | `player` | Player resumed |
| `playerRepeat` | `player, mode` | Repeat mode changed |
| `playerMoved` | `player, oldNode, newNode` | Player moved to new node |
| `trackStart` | `player, track` | Track began playing |
| `trackEnd` | `player, track, reason` | Track ended |
| `trackError` | `player, track, error` | Track exception / load failed |
| `trackStuck` | `player, track, thresholdMs` | Track stuck |
| `queueEnd` | `player` | Queue finished |
| `socketClosed` | `player, code, reason, byRemote` | Discord voice WS closed |
| `error` | `player, error` | Generic player error |

---

## Player API

```lua
player:connect()                           -- Send OP4 to Discord (join voice)
player:disconnect(destroyPlayer?)          -- Leave voice channel
player:destroy(reason?)                    -- Delete player on Lavalink + cleanup

player:play(options?)                      -- Play current/next track
player:pause(state?)                       -- Toggle or set pause
player:resume()                            -- Alias for pause(false)
player:stop()                              -- Stop without clearing queue
player:stopPlaying(clearQueue?)            -- Stop + optionally clear queue
player:skip(skipTo?, throwError?)          -- Skip to Nth track
player:seek(positionMs)                    -- Seek to position
player:setVolume(0-1000)                   -- Set volume
player:setRepeatMode("off"|"track"|"queue")
player:moveToNode(nodeId)                  -- Live-migrate to another node
player:getPosition()                       -- Client-side interpolated position (ms)

-- Queue
player.queue:add(track|tracks)
player.queue:remove(startIndex, endIndex?)
player.queue:shuffle()
player.queue:clear()
player.queue.current    -- current track
player.queue.tracks     -- upcoming tracks
player.queue.previous   -- last 25 played

-- Filters
player.filters:setVolume(multiplier)
player.filters:setEqualizer(bands)         -- { {band=0, gain=0.35}, ... }
player.filters:setTimescale({ speed, pitch, rate })
player.filters:setRotation({ rotationHz })
player.filters:setKaraoke(options)
player.filters:setTremolo(options)
player.filters:setVibrato(options)
player.filters:setDistortion(options)
player.filters:setChannelMix(options)
player.filters:setLowPass(options)
player.filters:setPluginFilters(table)
player.filters:resetFilters()
player.filters:resetFilter(filterName)
player.filters:apply()                     -- Re-send current filter state to Lavalink
```

---

## LavalinkManager API

```lua
lavalink:addNode(options)                  -- Add a node at runtime
lavalink:removeNode(id)                    -- Disconnect and remove a node
lavalink:init()                            -- Connect all configured nodes
lavalink:getNode(id?)                      -- Get node by id, or least-loaded usable node
lavalink:getUsableNodes()                  -- List of connected + ready nodes
lavalink:getAllNodes()                     -- List of all nodes regardless of state

lavalink:createPlayer(options)             -- Create (or get existing) player for a guild
lavalink:getPlayer(guildId)                -- Get existing player, or nil
lavalink:destroyPlayer(guildId, reason?)   -- Destroy player for a guild

lavalink:search(query, options?)           -- REST loadTracks, options = { source?, node? }
lavalink:decodeTrack(encoded, nodeId?)
lavalink:decodeTracks(encodedList, nodeId?)

lavalink:handleVoiceUpdate(packet)         -- Feed raw VOICE_STATE_UPDATE / VOICE_SERVER_UPDATE
```

`createPlayer` options:

```lua
{
  guildId        = "...",   -- required
  voiceChannelId = "...",
  textChannelId  = "...",
  selfDeaf       = true,    -- default true
  selfMute       = false,
  node           = "main",  -- optional node id, defaults to least-loaded
  region         = "europe",
  volume         = 100,
}
```

---

## Node Options

```lua
{
  id             = "main",              -- defaults to "host:port"
  host           = "localhost",
  port           = 2333,
  authorization  = "youshallnotpass",
  secure         = false,               -- use wss/https
  resuming       = true,                -- enable session resuming
  resumeTimeout  = 60,                  -- seconds
  reconnectTries = 5,
  reconnectDelay = 5000,                -- ms, doubles on each attempt up to 60s
  regions        = { "eu-west" },       -- used by region-aware node selection
}
```

If you're not using the Discordia integration, call `lavalink:handleVoiceUpdate(packet)` yourself for every `VOICE_STATE_UPDATE` and `VOICE_SERVER_UPDATE` gateway event, and provide `sendPayload = function(guildId, payload) ... end` in the manager options to forward voice payloads (OP4) to your gateway.

---

## Example Bot

The `example/` folder contains a fully working Discordia bot.

**Setup:**

```bash
cd example
cp .env.example .env
# fill in .env with your values
luvit bot.lua
```

**Commands:**

| Command | Description |
|---------|-------------|
| `!play <query/url>` | Search and play, or add to queue |
| `!skip [n]` | Skip current (or to nth track) |
| `!stop` | Stop and clear queue |
| `!pause` | Toggle pause/resume |
| `!resume` | Resume playback |
| `!queue` | Show current queue |
| `!nowplaying` | Show current track with position |
| `!volume [0-1000]` | Get or set volume |
| `!repeat <off\|track\|queue>` | Set repeat mode |
| `!shuffle` | Shuffle queue |
| `!seek <seconds>` | Seek to position |
| `!filter <name\|reset>` | Apply preset filter (nightcore, vaporwave, 8d, bassboost) |
| `!dc` | Disconnect and destroy player |
| `!nodes` | Show all node statuses |

Enable debug logging by setting `DEBUG=true` in `.env`.

---

## License

MIT
