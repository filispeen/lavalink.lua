local NULL = require("json").null

local FilterManager = {}
FilterManager.__index = FilterManager

local FILTERS = {
  "volume", "equalizer", "karaoke", "timescale", "tremolo", "vibrato",
  "rotation", "distortion", "channelMix", "lowPass", "pluginFilters",
  "echo", "chorus", "compressor", "highpass", "phaser", "spatial",
}

function FilterManager.new(player)
  local self = setmetatable({}, FilterManager)
  self.player = player
  self.data = {}
  return self
end

function FilterManager:_apply(filters)
  local node = self.player.node
  if not node or not node.sessionId then return end
  local restHandler = node.rest
  local ok, err = pcall(function()
    restHandler:updatePlayer(self.player.guildId, { filters = filters or self.data })
  end)
  if not ok then
    self.player.manager:emit("error", self.player, err)
  end
end

function FilterManager:setVolume(vol)
  self.data.volume = vol
  self:_apply()
  return self
end

function FilterManager:setEqualizer(bands)
  self.data.equalizer = bands
  self:_apply()
  return self
end

function FilterManager:setKaraoke(options)
  self.data.karaoke = options
  self:_apply()
  return self
end

function FilterManager:setTimescale(options)
  self.data.timescale = options
  self:_apply()
  return self
end

function FilterManager:setTremolo(options)
  self.data.tremolo = options
  self:_apply()
  return self
end

function FilterManager:setVibrato(options)
  self.data.vibrato = options
  self:_apply()
  return self
end

function FilterManager:setRotation(options)
  self.data.rotation = options
  self:_apply()
  return self
end

function FilterManager:setDistortion(options)
  self.data.distortion = options
  self:_apply()
  return self
end

function FilterManager:setChannelMix(options)
  self.data.channelMix = options
  self:_apply()
  return self
end

function FilterManager:setLowPass(options)
  self.data.lowPass = options
  self:_apply()
  return self
end

function FilterManager:setPluginFilters(filters)
  self.data.pluginFilters = filters
  self:_apply()
  return self
end

-- NodeLink-native filters.  They use the same Lavalink v4 `filters` payload,
-- so they can be combined with any of the standard filters above.
function FilterManager:setEcho(options)
  self.data.echo = options
  self:_apply()
  return self
end

function FilterManager:setChorus(options)
  self.data.chorus = options
  self:_apply()
  return self
end

function FilterManager:setCompressor(options)
  self.data.compressor = options
  self:_apply()
  return self
end

function FilterManager:setHighPass(options)
  self.data.highpass = options
  self:_apply()
  return self
end

function FilterManager:setPhaser(options)
  self.data.phaser = options
  self:_apply()
  return self
end

function FilterManager:setSpatial(options)
  self.data.spatial = options
  self:_apply()
  return self
end

function FilterManager:resetFilters()
  self.data = {}
  local filters = {}
  for _, name in ipairs(FILTERS) do filters[name] = NULL end
  self:_apply(filters)
  return self
end

function FilterManager:resetFilter(filterName)
  self.data[filterName] = nil
  local filters = self:getCurrentData()
  filters[filterName] = NULL
  self:_apply(filters)
  return self
end

function FilterManager:apply()
  self:_apply()
  return self
end

function FilterManager:apply()
  self:_apply()
  return self
end

function FilterManager:getCurrentData()
  local copy = {}
  for k, v in pairs(self.data) do
    copy[k] = v
  end
  return copy
end

return FilterManager
